import Foundation

/// A local, persistent three-person post office for exploring both sides of the exchange.
/// This transport accepts only its own opaque links, never iCloud URLs or real accounts.
@MainActor public final class SampleExchange: Exchange {
  public static let identities = ["avery", "mira", "theo"]
  struct Edition: Codable {
    var token = UUID()
    var owner: String
    var audience: Audience
    var readers: [String] = []
    var requests: [String] = []
    var invited: [String]?, blocked: [String]?, stopped: Bool?, instance: UUID?
    var shareID: String { (instance ?? token).uuidString }
  }
  struct State: Codable {
    var cards: [String: Card]
    var editions: [Edition]
    var revisions: [String: String] = [:]
    var identity = "avery"
  }
  private var state: State
  private let file: URL?
  public var identity: String { state.identity }
  public func name(_ key: String) -> String {
    guard let name = state.cards[key]?.name, !name.isEmpty else { return key.capitalized }
    return name
  }
  public init(file: URL? = nil) throws {
    self.file = file
    if let file, FileManager.default.fileExists(atPath: file.path) {
      state = try JSONDecoder().decode(State.self, from: Data(contentsOf: file))
      return
    }
    var a = Card()
    a.first = "Avery"
    a.last = "Morgan"
    a.phones = [Phone("Mobile", "(415) 555-0142")]
    a.street = "24 Laurel Street"
    a.city = "San Francisco"
    a.region = "CA"
    a.postal = "94118"
    a.birthday = .init(year: 1992, month: 6, day: 12)
    a.anniversary = .init(year: 2018, month: 9, day: 8)
    a.partner = .init(name: "Jamie Morgan", phone: "(415) 555-0168")
    a.children = [.init(name: "Robin", birthday: .init(year: 2021, month: 5, day: 7))]
    var m = Card()
    m.first = "Mira"
    m.last = "Chen"
    m.phones = [Phone("Mobile", "(212) 555-0184")]
    m.city = "Brooklyn"
    m.region = "NY"
    var t = Card()
    t.first = "Theo"
    t.last = "Brooks"
    t.phones = [Phone("Work", "(617) 555-0106")]
    state = State(
      cards: ["avery": a, "mira": m, "theo": t],
      editions: [.init(owner: "mira", audience: .home, readers: ["avery"])])
    try persist(state)
  }
  private func persist(_ next: State) throws {
    if let file {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(next).write(to: file, options: .atomic)
    }
    state = next
  }
  public func switchTo(_ id: String) throws {
    guard Self.identities.contains(id) else { throw BookError.message("Unknown sample person.") }
    var next = state
    next.identity = id
    try persist(next)
  }
  private func url(_ e: Edition) -> URL { URL(string: "kinpost://sample/" + e.token.uuidString)! }
  public func read() async throws -> Book {
    var people: [String: Connection] = [:]
    var book = Book(
      owner: identity, card: state.cards[identity]!, revision: state.revisions[identity] ?? "")
    for e in state.editions.sorted(by: { $0.audience.index < $1.audience.index })
    where e.stopped != true {
      if e.readers.contains(identity), let card = state.cards[e.owner] {
        people[e.owner] = Connection(
          id: e.owner, card: card.visible(to: e.audience), audience: e.audience, url: url(e),
          shareID: e.shareID)
      }
      if e.owner == identity {
        book.shares[e.audience] = e.shareID
        let groups: [(AccessState, [String])] = [
          (.accepted, e.readers), (.requested, e.requests), (.invited, e.invited ?? []),
          (.blocked, e.blocked ?? []),
        ]
        for (status, ids) in groups {
          book.access += ids.map {
            Access(
              key: $0, name: name($0), handle: "\($0)@example.com", audience: e.audience,
              state: status, shareID: e.shareID)
          }
        }
      }
    }
    book.people = people.values.sorted(by: { $0.card.name < $1.card.name })
    return book
  }
  public func save(_ card: Card, basedOn revision: String) async throws {
    guard revision == state.revisions[identity, default: ""] else {
      throw BookError.message("Your card changed. Reopen the editor with the latest version.")
    }
    var next = state
    next.cards[identity] = try card.cleaned()
    next.revisions[identity] = UUID().uuidString
    try persist(next)
  }
  public func invitation(_ audience: Audience) async throws -> URL {
    if let i = state.editions.firstIndex(where: {
      $0.owner == identity && $0.audience == audience
    }) {
      if state.editions[i].stopped == true {
        var next = state
        next.editions[i].stopped = false
        next.editions[i].instance = UUID()
        try persist(next)
      }
      return url(state.editions[i])
    }
    let e = Edition(owner: identity, audience: audience)
    var next = state
    next.editions.append(e)
    try persist(next)
    return url(e)
  }
  public func request(_ url: URL) async throws {
    guard let i = state.editions.firstIndex(where: { self.url($0) == url && $0.stopped != true })
    else {
      throw BookError.message("That invitation isn’t part of this sample address book.")
    }
    let e = state.editions[i]
    guard e.owner != identity else {
      throw BookError.message(
        "This is your invitation. Switch to another sample person to request it.")
    }
    if e.readers.contains(identity) || e.requests.contains(identity) { return }
    var next = state
    if e.invited?.contains(identity) == true {
      next.editions[i].invited?.removeAll { $0 == identity }
      next.editions[i].readers.append(identity)
    } else if e.blocked?.contains(identity) != true {
      next.editions[i].requests.append(identity)
    }
    try persist(next)
  }
  public func changeSharing(_ change: SharingChange, owner: String) async throws {
    let stale = BookError.message("Sharing changed. Refresh before continuing.")
    guard owner == identity else { throw stale }
    var next = state
    switch change {
    case .respond(let access, let decision):
      guard
        let i = next.editions.firstIndex(where: {
          $0.owner == owner && $0.shareID == access.shareID && $0.stopped != true
        })
      else { throw stale }
      let key = access.key
      var e = next.editions[i]
      switch decision {
      case .approve, .deny, .block:
        guard access.state == .requested, e.requests.contains(key) else { throw stale }
        e.requests.removeAll { $0 == key }
        if decision == .approve { e.invited = (e.invited ?? []) + [key] }
        if decision == .block { e.blocked = (e.blocked ?? []) + [key] }
      case .unblock:
        guard access.state == .blocked, e.blocked?.contains(key) == true else { throw stale }
        e.blocked?.removeAll { $0 == key }
      case .revoke:
        guard e.readers.contains(key) || e.invited?.contains(key) == true else { throw stale }
        e.readers.removeAll { $0 == key }
        e.invited?.removeAll { $0 == key }
      }
      next.editions[i] = e
    case .stop(let tier, let id):
      guard
        let i = next.editions.firstIndex(where: {
          $0.owner == owner && $0.audience == tier && $0.shareID == id && $0.stopped != true
        })
      else { throw stale }
      next.editions[i] = Edition(
        token: next.editions[i].token, owner: owner, audience: tier, stopped: true)
    case .leave(let person):
      guard
        let i = next.editions.firstIndex(where: {
          $0.owner == person.id && $0.shareID == person.shareID && $0.readers.contains(identity)
        })
      else { throw stale }
      next.editions[i].readers.removeAll { $0 == identity }
    case .deleteCard(let revision):
      guard revision == next.revisions[owner, default: ""] else { throw stale }
      next.editions.removeAll { $0.owner == owner }
      next.cards[owner] = Card()
      next.revisions[owner] = ""
    }
    try persist(next)
  }
}
