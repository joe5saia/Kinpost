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
  private func card(_ record: CKRecord) throws -> Card {
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
  private func label(_ who: CKUserIdentity) -> String {
    if let n = who.nameComponents {
      let name = PersonNameComponentsFormatter().string(from: n)
      if !name.isEmpty { return name }
    }
    return who.lookupInfo?.emailAddress ?? who.lookupInfo?.phoneNumber ?? "iCloud participant"
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
          let sub = CKDatabaseSubscription(subscriptionID: "kinpost-changes-\(database.databaseScope.rawValue)-v1")
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
      owner: user.recordName, card: try master.map(card) ?? Card(),
      revision: master?.recordChangeTag ?? "")
    for tier in Audience.allCases {
      guard let s = try await share(tier) else { continue }
      book.access += s.requesters.map {
        Access(key: key($0), name: label($0.userIdentity), audience: tier, pending: true)
      }
      book.access += s.participants.filter { $0.role != .owner }.map {
        Access(key: $0.participantID, name: label($0.userIdentity), audience: tier, pending: false)
      }
    }
    let shared = container.sharedCloudDatabase
    var incoming: [String: Connection] = [:]
    for zone in try await shared.allRecordZones()
    where zone.zoneID.zoneName == self.zone.zoneID.zoneName {
      var token: CKServerChangeToken?
      var more = true
      while more {
        let page = try await shared.recordZoneChanges(inZoneWith: zone.zoneID, since: token)
        for result in page.modificationResultsByID.values {
          let record = try result.get().record
          guard record.recordType == "Edition",
            let tier = Audience(rawValue: record.recordID.recordName), let ref = record.share,
            incoming[zone.zoneID.ownerName].map({ $0.audience.index <= tier.index }) ?? true,
            let s = try await shared.record(for: ref.recordID) as? CKShare, let url = s.url
          else { continue }
          incoming[zone.zoneID.ownerName] = Connection(
            id: zone.zoneID.ownerName, card: try card(record).visible(to: tier), audience: tier,
            url: url)
        }
        more = page.moreComing
        token = page.changeToken
      }
    }
    book.people = incoming.values.sorted {
      $0.card.name.localizedCaseInsensitiveCompare($1.card.name) == .orderedAscending
    }
    try await verifyAccount()
    return book
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
  func request(_ url: URL) async throws {
    try await verifyAccount()
    guard url.scheme == "https",
      ["www.icloud.com", "icloud.com"].contains(url.host?.lowercased() ?? ""),
      url.path.hasPrefix("/share/")
    else { throw BookError.message("Paste an iCloud sharing link from Kinpost.") }
    if let metadata = try? await container.shareMetadata(for: url),
      metadata.containerIdentifier == Self.containerID,
      [.pending, .accepted].contains(metadata.participantStatus)
    {
      try await accept(metadata)
      return
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let op = CKShareRequestAccessOperation(shareURLs: [url])
      op.shareAccessRequestResultBlock = { continuation.resume(with: $0) }
      container.add(op)
    }
  }
  func accept(_ metadata: CKShare.Metadata) async throws {
    guard metadata.containerIdentifier == Self.containerID else {
      throw BookError.message("This invitation is for another app.")
    }
    if metadata.participantStatus != .accepted { _ = try await container.accept(metadata) }
  }
  func decide(_ access: Access, allow: Bool) async throws {
    try await verifyAccount()
    guard let s = try await share(access.audience) else {
      throw BookError.message("This invitation is no longer available.")
    }
    if access.pending, let r = s.requesters.first(where: { key($0) == access.key }) {
      if allow {
        let info = r.participantLookupInfo
        guard let participant = try await container.shareParticipants(for: [info])[info]?.get()
        else { throw BookError.message("The requester’s account is unavailable.") }
        participant.permission = .readOnly
        s.addParticipant(participant)
      } else {
        s.denyRequesters([r])
      }
    } else if !access.pending, !allow,
      let p = s.participants.first(where: { $0.role != .owner && $0.participantID == access.key })
    {
      s.removeParticipant(p)
    } else {
      throw BookError.message("This request changed. Refresh and try again.")
    }
    _ = try await db.save(s)
  }
}
