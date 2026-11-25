import Foundation

public enum Audience: String, Codable, CaseIterable, Identifiable, Sendable {
  case phone, home, personal, household
  public var id: Self { self }
  public var title: String {
    switch self {
    case .phone: "Phone only"
    case .home: "Home"
    case .personal: "Personal"
    case .household: "Household"
    }
  }
  public var detail: String {
    switch self {
    case .phone: "Name and phone numbers"
    case .home: "Phone numbers and mailing address"
    case .personal: "Home details, birthday and anniversary"
    case .household: "Personal details, partner and children"
    }
  }
  public var index: Int { Self.allCases.firstIndex(of: self)! }
}

public struct Phone: Identifiable, Codable, Equatable, Sendable {
  public var id = UUID()
  public var label: String
  public var number: String
  public init(_ label: String = "Mobile", _ number: String = "") {
    self.label = label
    self.number = number
  }
}

public struct HouseholdMember: Identifiable, Codable, Equatable, Sendable {
  public var id = UUID()
  public var name = ""
  public var birthday: DateComponents?
  public var phone = ""
  public init(name: String = "", birthday: DateComponents? = nil, phone: String = "") {
    self.name = name
    self.birthday = birthday
    self.phone = phone
  }
}

public struct Card: Codable, Equatable, Sendable {
  public var first = "", last = ""
  public var phones: [Phone] = []
  public var street = "", city = "", region = "", postal = "", country = ""
  public var birthday: DateComponents?, anniversary: DateComponents?
  public var partner: HouseholdMember?, children: [HouseholdMember] = []
  public init() {}
  public var name: String { [first, last].filter { !$0.isEmpty }.joined(separator: " ") }
  public var initials: String {
    [first, last].compactMap(\.first).map(String.init).joined().uppercased()
  }
  public var address: String {
    [street, [city, region].filter { !$0.isEmpty }.joined(separator: ", "), postal, country].filter
    { !$0.isEmpty }.joined(separator: " · ")
  }
  /// Allowlist at the publication boundary. New fields are private by default.
  public func visible(to audience: Audience) -> Card {
    var result = Card()
    result.first = first
    result.last = last
    result.phones = phones
    if audience.index >= Audience.home.index {
      result.street = street
      result.city = city
      result.region = region
      result.postal = postal
      result.country = country
    }
    if audience.index >= Audience.personal.index {
      result.birthday = birthday
      result.anniversary = anniversary
    }
    if audience == .household {
      result.partner = partner
      result.children = children
    }
    return result
  }

  public func cleaned() throws -> Card {
    func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    var copy = self
    for key in [\Card.first, \.last, \.street, \.city, \.region, \.postal, \.country] {
      copy[keyPath: key] = trim(self[keyPath: key])
    }
    guard !copy.name.isEmpty else {
      throw BookError.message("Enter a first or last name for your card.")
    }
    copy.phones = phones.compactMap {
      var p = $0
      p.number = trim(p.number)
      return p.number.isEmpty ? nil : p
    }
    if let partner, trim(partner.name).isEmpty {
      throw BookError.message("Give your partner a name or remove the entry.")
    }
    guard children.allSatisfy({ !trim($0.name).isEmpty }) else {
      throw BookError.message("Give each child a name or remove the empty entry.")
    }
    return copy
  }
}

public enum BookError: LocalizedError {
  case message(String)
  public var errorDescription: String? {
    if case .message(let message) = self { return message }
    return nil
  }
}

public struct Connection: Identifiable, Equatable, Sendable {
  public let id: String, card: Card, audience: Audience, url: URL, shareID: String
  public init(id: String, card: Card, audience: Audience, url: URL, shareID: String) {
    self.id = id
    self.card = card
    self.audience = audience
    self.url = url
    self.shareID = shareID
  }
}

public enum AccessState: String, CaseIterable, Sendable {
  case requested, invited, accepted, blocked
}

public struct Access: Identifiable, Equatable, Sendable {
  public let key: String, name: String, handle: String?, audience: Audience, state: AccessState,
    shareID: String
  public var id: String { shareID + ":" + state.rawValue + ":" + key }
  public init(
    key: String, name: String, handle: String?, audience: Audience, state: AccessState,
    shareID: String
  ) {
    self.key = key
    self.name = name
    self.handle = handle
    self.audience = audience
    self.state = state
    self.shareID = shareID
  }
}

public enum AccessDecision: String, Sendable { case approve, deny, revoke, block, unblock }
public enum SharingChange: Sendable {
  case respond(Access, AccessDecision)
  case stop(Audience, shareID: String)
  case leave(Connection)
  case deleteCard(revision: String)
}

public struct Book: Sendable {
  public var owner: String, card: Card, revision: String, people: [Connection], access: [Access]
  public var shares: [Audience: String] = [:]
  /// IDs, not cached card fields: an unreadable share must never authorize a Contacts write.
  public var unavailablePeople: Set<String> = []
  public init(
    owner: String = "", card: Card = Card(), revision: String = "", people: [Connection] = [],
    access: [Access] = []
  ) {
    self.owner = owner
    self.card = card
    self.revision = revision
    self.people = people
    self.access = access
  }
}
