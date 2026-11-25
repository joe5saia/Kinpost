import CloudKit
import Contacts
import KinpostCore

@MainActor final class CloudExchange: Exchange {
  static let containerID = "iCloud." + (Bundle.main.bundleIdentifier ?? "app.kinpost.Kinpost")
  let container = CKContainer(identifier: containerID)
  private var db: CKDatabase { container.privateCloudDatabase }
  private let zone = CKRecordZone(zoneName: "Kinpost")
  private var account: CKRecord.ID?
  private var subscribed = false
  private func id(_ name: String) -> CKRecord.ID { .init(recordName: name, zoneID: zone.zoneID) }
  private func fetch(_ id: CKRecord.ID) async throws -> CKRecord? {
    do { return try await db.record(for: id) } catch let e as CKError where e.code == .unknownItem {
      return nil
    }
  }
  private func verifyAccount() async throws {
    guard let account, try await container.userRecordID() == account else {
      throw BookError.message("Your iCloud account changed. Refresh before continuing.")
    }
  }
  private func commit(_ records: [CKRecord]) async throws {
    let results = try await db.modifyRecords(
      saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
    for result in results.saveResults.values { _ = try result.get() }
  }
  private static func card(_ record: CKRecord) throws -> Card {
    guard let data = record.encryptedValues["payload"] as? Data else {
      throw BookError.message("This card could not be read.")
    }
    return try JSONDecoder().decode(Card.self, from: data)
  }
  private func share(_ tier: Audience) async throws -> CKShare? {
    guard let ref = try await fetch(id(tier.rawValue))?.share else { return nil }
    return try await fetch(ref.recordID) as? CKShare
  }
  private func key(_ r: CKShare.AccessRequester) -> String {
    r.participantLookupInfo.userRecordID?.recordName ?? r.participantLookupInfo.emailAddress ?? r
      .participantLookupInfo.phoneNumber ?? ""
  }
  private func handle(_ info: CKUserIdentity.LookupInfo?) -> String? {
    [info?.emailAddress, info?.phoneNumber].compactMap { $0 }.first { !$0.isEmpty }
  }
  private func label(_ who: CKUserIdentity) -> String {
    if let n = who.nameComponents {
      let name = PersonNameComponentsFormatter().string(from: n)
      if !name.isEmpty { return name }
    }
    return "iCloud participant"
  }

  func read() async throws -> Book {
    let user = try await container.userRecordID()
    if account != user {
      _ = try await db.save(zone)
      account = user
      subscribed = false
    }
    if !subscribed {
      do {
        for database in [db, container.sharedCloudDatabase] {
          let sub = CKDatabaseSubscription(
            subscriptionID: "kinpost-changes-\(database.databaseScope.rawValue)-v1")
          let info = CKSubscription.NotificationInfo()
          info.shouldSendContentAvailable = true
          sub.notificationInfo = info
          _ = try await database.save(sub)
        }
        subscribed = true
      } catch { /* Foreground reconciliation still works without push permission or APNs. */  }
    }
    let master = try await fetch(id("master"))
    var book = Book(
      owner: user.recordName, card: try master.map(Self.card) ?? Card(),
      revision: master?.recordChangeTag ?? "")
    for tier in Audience.allCases {
      guard let s = try await share(tier) else { continue }
      let shareID = s.recordID.recordName
      book.shares[tier] = shareID
      book.access += s.requesters.map {
        Access(
          key: key($0), name: label($0.userIdentity), handle: handle($0.participantLookupInfo),
          audience: tier, state: .requested, shareID: shareID)
      }
      book.access += s.participants.compactMap {
        guard $0.role != .owner, [.pending, .accepted].contains($0.acceptanceStatus) else {
          return nil
        }
        return Access(
          key: $0.participantID, name: label($0.userIdentity),
          handle: handle($0.userIdentity.lookupInfo), audience: tier,
          state: $0.acceptanceStatus == .accepted ? .accepted : .invited, shareID: shareID)
      }
      book.access += s.blockedIdentities.compactMap {
        let who = $0.userIdentity
        guard let id = who.userRecordID?.recordName ?? handle(who.lookupInfo) else { return nil }
        return Access(
          key: id, name: label(who), handle: handle(who.lookupInfo), audience: tier,
          state: .blocked, shareID: shareID)
      }
    }
    let shared = container.sharedCloudDatabase
    for zone in try await shared.allRecordZones()
    where zone.zoneID.zoneName == self.zone.zoneID.zoneName {
      var editions: [Audience: Result<CKRecord, Error>] = [:]
      do {
        var token: CKServerChangeToken?
        var more = true
        while more {
          let page = try await shared.recordZoneChanges(inZoneWith: zone.zoneID, since: token)
          for (id, result) in page.modificationResultsByID {
            if let tier = Audience(rawValue: id.recordName) {
              editions[tier] = result.map(\.record)
            }
          }
          for deletion in page.deletions {
            if let tier = Audience(rawValue: deletion.recordID.recordName) { editions[tier] = nil }
          }
          more = page.moreComing
          token = page.changeToken
        }
      } catch let error as CKError
        where [.zoneNotFound, .userDeletedZone, .permissionFailure].contains(error.code)
      {
        book.unavailablePeople.insert(zone.zoneID.ownerName)
        continue
      }
      await Self.receive(editions, from: zone.zoneID.ownerName, into: &book) { record in
        guard let ref = record.share else { return nil }
        guard let share = try await shared.record(for: ref.recordID) as? CKShare,
          share.currentUserParticipant?.acceptanceStatus == .accepted, let url = share.url
        else { return nil }
        return (url, share.recordID.recordName)
      }
    }
    book.people.sort {
      $0.card.name.localizedCaseInsensitiveCompare($1.card.name) == .orderedAscending
    }
    try await verifyAccount()
    return book
  }

  static func receive(
    _ editions: [Audience: Result<CKRecord, Error>], from owner: String, into book: inout Book,
    acceptedShare: (CKRecord) async throws -> (URL, String)?
  ) async {
    // An unreadable broad edition is not a downgrade. Never apply a partial card to Contacts.
    guard let tier = Audience.allCases.reversed().first(where: { editions[$0] != nil }),
      let result = editions[tier]
    else { return }
    do {
      let record = try result.get()
      guard record.recordType == "Edition", let (url, shareID) = try await acceptedShare(record)
      else {
        throw BookError.message("Missing shared edition.")
      }
      book.people.append(
        Connection(
          id: owner, card: try card(record).visible(to: tier), audience: tier, url: url,
          shareID: shareID))
    } catch { book.unavailablePeople.insert(owner) }
  }

  func save(_ card: Card, basedOn revision: String) async throws {
    try await verifyAccount()
    let master =
      try await fetch(id("master")) ?? CKRecord(recordType: "PrivateCard", recordID: id("master"))
    guard master.recordChangeTag ?? "" == revision else {
      throw BookError.message("Your card changed on another device. Refresh and reopen the editor.")
    }
    let encoder = JSONEncoder()
    let clean = try card.cleaned()
    master.encryptedValues["payload"] = try encoder.encode(clean)
    var records = [master]
    for tier in Audience.allCases {
      let record =
        try await fetch(id(tier.rawValue))
        ?? CKRecord(recordType: "Edition", recordID: id(tier.rawValue))
      record.encryptedValues["payload"] = try encoder.encode(clean.visible(to: tier))
      records.append(record)
    }
    try await commit(records)
  }
  func invitation(_ tier: Audience) async throws -> URL {
    try await verifyAccount()
    if let existing = try await share(tier)?.url { return existing }
    guard let record = try await fetch(id(tier.rawValue)) else {
      throw BookError.message("Save your card before sharing.")
    }
    let s = CKShare(rootRecord: record)
    s.publicPermission = .none
    s.allowsAccessRequests = true
    s[CKShare.SystemFieldKey.title] = "Kinpost · \(tier.title)"
    try await commit([record, s])
    guard let url = try await share(tier)?.url else {
      throw BookError.message("iCloud hasn’t finished creating the link. Try again.")
    }
    return url
  }
  func request(_ url: URL) async throws -> InvitationOutcome {
    try await verifyAccount()
    guard url.scheme == "https",
      ["www.icloud.com", "icloud.com"].contains(url.host?.lowercased() ?? ""),
      url.path.hasPrefix("/share/")
    else { throw BookError.message("Paste an iCloud sharing link from Kinpost.") }
    let metadata: CKShare.Metadata?
    do { metadata = try await container.shareMetadata(for: url) } catch let error as CKError
      where [.unknownItem, .permissionFailure].contains(error.code)
    { metadata = nil } catch let error as CKError
      where error.code == .participantMayNeedVerification
    {
      throw BookError.message(
        "Open the original iCloud link in Messages or Safari so Apple can verify your invitation.")
    }
    if let metadata {
      guard metadata.containerIdentifier == Self.containerID else {
        throw BookError.message("This invitation is for another app.")
      }
      if [.pending, .accepted].contains(metadata.participantStatus) {
        try await accept(metadata)
        return .accepted(owner: metadata.share.recordID.zoneID.ownerName)
      }
    }
    do {
      let results = try await container.requestShareAccess(for: [url])
      guard let result = results[url] else {
        throw BookError.message("iCloud did not confirm processing this request.")
      }
      try result.get()
      return .requested
    } catch let error as CKError where error.code == .participantAlreadyInvited {
      throw BookError.message(
        "You’ve already been invited. Open the original iCloud link to accept.")
    }
  }
  func accept(_ metadata: CKShare.Metadata) async throws {
    guard metadata.containerIdentifier == Self.containerID else {
      throw BookError.message("This invitation is for another app.")
    }
    switch metadata.participantStatus {
    case .accepted: return
    case .pending: _ = try await container.accept(metadata)
    default:
      throw BookError.message(
        "There is no invitation to accept. Request access from the owner first.")
    }
  }
  func changeSharing(_ change: SharingChange, owner: String) async throws {
    try await verifyAccount()
    let stale = BookError.message("Sharing changed. Refresh before continuing.")
    guard owner == account?.recordName else { throw stale }
    switch change {
    case .leave(let person):
      let zoneID = CKRecordZone.ID(zoneName: zone.zoneID.zoneName, ownerName: person.id)
      _ = try await container.sharedCloudDatabase.deleteRecord(
        withID: .init(recordName: person.shareID, zoneID: zoneID))
    case .stop(let tier, let shareID):
      guard let s = try await share(tier), s.recordID.recordName == shareID else { throw stale }
      _ = try await db.deleteRecord(withID: s.recordID)
    case .deleteCard(let revision):
      guard let master = try await fetch(id("master")), master.recordChangeTag == revision else {
        throw stale
      }
      // Deleting a hierarchy root also deletes its CKShare. Never touch the reader's shared database.
      let ids = [master.recordID] + Audience.allCases.map { id($0.rawValue) }
      let result = try await db.modifyRecords(saving: [], deleting: ids, atomically: true)
      for deleted in result.deleteResults.values { try deleted.get() }
    case .respond(let access, let decision):
      guard let s = try await share(access.audience), s.currentUserParticipant?.role == .owner,
        s.recordID.recordName == access.shareID,
        s.publicPermission == .none, !access.key.isEmpty
      else { throw stale }
      switch decision {
      case .approve, .deny, .block:
        guard access.state == .requested,
          let r = s.requesters.first(where: { key($0) == access.key })
        else { throw stale }
        if decision == .deny {
          s.denyRequesters([r])
        } else if decision == .block {
          s.blockRequesters([r])
        } else {
          let info = r.participantLookupInfo
          guard let current = handle(info), current == access.handle else {
            throw BookError.message(
              "The requester’s email or phone is unavailable or changed. Refresh before approving.")
          }
          guard let participant = try await container.shareParticipants(for: [info])[info]?.get()
          else { throw BookError.message("The requester’s account is unavailable.") }
          participant.permission = .readOnly
          s.addParticipant(participant)
        }
      case .revoke:
        guard [.invited, .accepted].contains(access.state),
          let p = s.participants.first(where: {
            $0.role != .owner && $0.participantID == access.key
          })
        else { throw stale }
        s.removeParticipant(p)
      case .unblock:
        guard access.state == .blocked,
          let b = s.blockedIdentities.first(where: {
            ($0.userIdentity.userRecordID?.recordName ?? handle($0.userIdentity.lookupInfo))
              == access.key
          })
        else { throw stale }
        s.unblockIdentities([b])
      }
      try await commit([s])
    }
  }
}
