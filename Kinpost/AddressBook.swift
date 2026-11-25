import ContactsUI
import CryptoKit
import KinpostCore
import SwiftUI

/// Local-only bookkeeping. Keep field identifiers, not a second copy of the contact data.
@MainActor @Observable final class AddressBook {
  private struct Link: Codable {
    var contact = "", created = false, owned: [String] = [], digest = ""
    var needsRelink: Bool?
  }
  private var links: [String: Link]
  private(set) var problems: [String: String] = [:]
  private let store = CNContactStore()
  private let key = "kinpost.contact-links.v1"
  init() {
    links =
      (UserDefaults.standard.data(forKey: key).flatMap {
        try? JSONDecoder().decode([String: Link].self, from: $0)
      }) ?? [:]
  }
  private func save() throws {
    UserDefaults.standard.set(try JSONEncoder().encode(links), forKey: key)
  }
  func linked(_ id: String) -> Bool { links[id] != nil }
  func unlink(_ id: String) throws {
    links.removeValue(forKey: id)
    problems[id] = nil
    try save()
  }
  func authorize() async throws {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .limited || status == .authorized { return }
    guard try await store.requestAccess(for: .contacts) else {
      throw BookError.message(
        "Allow Contacts access in Settings, or keep this card in Kinpost only.")
    }
  }
  private func canonicalIDs() -> [String: String] {
    var result: [String: String] = [:]
    for identifier in Set(links.values.map(\.contact)) {
      result[identifier] = try? store.unifiedContact(
        withIdentifier: identifier,
        keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
      ).identifier
    }
    return result
  }
  func sync(_ person: Connection, owner: String, existing: String? = nil) throws {
    try sync(person, owner: owner, existing: existing, canonical: canonicalIDs())
  }
  private func sync(
    _ person: Connection, owner: String, existing: String?, canonical: [String: String]
  ) throws {
    let id = owner + "/" + person.id
    var link = links[id] ?? Link()
    if existing == nil, link.needsRelink == true {
      throw BookError.message(
        "Two cards were linked to the same Apple contact. Choose a contact to resume sync.")
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let c = person.card
    let digest = Data(SHA256.hash(data: try encoder.encode(c))).base64EncodedString()
    let keys =
      [
        CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey,
        CNContactPostalAddressesKey, CNContactBirthdayKey, CNContactDatesKey, CNContactRelationsKey,
      ] as [CNKeyDescriptor]
    let target: CNMutableContact
    let request = CNSaveRequest()
    let targetID = existing ?? (link.contact.isEmpty ? nil : link.contact)
    if let targetID {
      let resolved = try store.unifiedContact(withIdentifier: targetID, keysToFetch: keys)
      let conflicts = links.filter { key, other in
        key != id
          && (other.contact == resolved.identifier
            || canonical[other.contact] == resolved.identifier
            || resolved.isUnifiedWithContact(withIdentifier: other.contact))
      }
      if !conflicts.isEmpty {
        let message =
          "Another card links to this Apple contact. Choose a different contact or stop syncing."
        if existing == nil {
          for key in Array(conflicts.keys) + [id] {
            links[key]?.needsRelink = true
            problems[key] = message
          }
          try save()
        }
        throw BookError.message(message)
      }
      if existing != nil {
        if canonical[link.contact] != resolved.identifier { link = Link() }
        link.created = false
        link.needsRelink = nil
      } else if link.digest == digest {
        return
      }
      target = resolved.mutableCopy() as! CNMutableContact
    } else {
      target = CNMutableContact()
      link.created = true
    }

    if link.created {
      target.givenName = c.first
      target.familyName = c.last
      target.birthday = c.birthday
    }
    // Remove only the entries we previously added; leave local phone numbers, addresses, and relations alone.
    let old = Set(link.owned)
    link.owned = []
    target.phoneNumbers.removeAll { old.contains($0.identifier) }
    target.postalAddresses.removeAll { old.contains($0.identifier) }
    target.dates.removeAll { old.contains($0.identifier) }
    target.contactRelations.removeAll { old.contains($0.identifier) }
    for p in c.phones {
      let digits = p.number.filter(\.isNumber)
      if let match = target.phoneNumbers.first(where: {
        $0.value.stringValue.filter(\.isNumber) == digits
      }) {
        if existing != nil { link.owned.append(match.identifier) }
        continue
      }
      let v = CNLabeledValue(label: p.label, value: CNPhoneNumber(stringValue: p.number))
      target.phoneNumbers.append(v)
      link.owned.append(v.identifier)
    }
    if !c.address.isEmpty {
      let a = CNMutablePostalAddress()
      a.street = c.street
      a.city = c.city
      a.state = c.region
      a.postalCode = c.postal
      a.country = c.country
      if let match = target.postalAddresses.first(where: { $0.value.isEqual(a) }) {
        if existing != nil { link.owned.append(match.identifier) }
      } else {
        let v = CNLabeledValue<CNPostalAddress>(label: CNLabelHome, value: a)
        target.postalAddresses.append(v)
        link.owned.append(v.identifier)
      }
    }
    if let anniversary = c.anniversary {
      let v = CNLabeledValue<NSDateComponents>(
        label: CNLabelDateAnniversary, value: anniversary as NSDateComponents)
      target.dates.append(v)
      link.owned.append(v.identifier)
    }
    for (name, label) in (c.partner.map { [($0.name, CNLabelContactRelationSpouse)] } ?? [])
      + c.children.map({ ($0.name, CNLabelContactRelationChild) })
    {
      let v = CNLabeledValue(label: label, value: CNContactRelation(name: name))
      target.contactRelations.append(v)
      link.owned.append(v.identifier)
    }
    if targetID == nil {
      request.add(target, toContainerWithIdentifier: nil)
    } else {
      request.update(target)
    }
    try store.execute(request)
    link.contact = targetID ?? target.identifier
    link.digest = digest
    links[id] = link
    try save()
    problems[id] = nil
  }
  func reconcile(_ book: Book) {
    problems = [:]
    // Forget the opt-in after a confirmed loss of access. An unreadable owner is not a revocation.
    let prefix = book.owner + "/"
    let retained = Set(book.people.map(\.id)).union(book.unavailablePeople)
    let obsolete = links.keys.filter {
      $0.hasPrefix(prefix) && !retained.contains(String($0.dropFirst(prefix.count)))
    }
    if !obsolete.isEmpty {
      for key in obsolete { links.removeValue(forKey: key) }
      try? save()
    }
    let linkedPeople = book.people.filter { linked(book.owner + "/" + $0.id) }
    guard !linkedPeople.isEmpty else { return }
    let status = CNContactStore.authorizationStatus(for: .contacts)
    guard status == .authorized || status == .limited else {
      for person in linkedPeople {
        problems[book.owner + "/" + person.id] = "Contacts access is off."
      }
      return
    }
    let canonical = canonicalIDs()
    for person in linkedPeople {
      do { try sync(person, owner: book.owner, existing: nil, canonical: canonical) } catch let
        error as CNError
        where error.code == .recordDoesNotExist || error.code == .authorizationDenied
      {
        problems[book.owner + "/" + person.id] =
          "The linked contact was deleted or is no longer accessible to Kinpost."
      } catch { problems[book.owner + "/" + person.id] = error.localizedDescription }
    }
  }
  typealias ContactChoice = (id: String, name: String, phone: String?)
  @concurrent static func permittedContacts() async throws -> [ContactChoice] {
    let request = CNContactFetchRequest(keysToFetch: [
      CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
      CNContactPhoneNumbersKey as CNKeyDescriptor,
    ])
    request.sortOrder = .userDefault
    var contacts: [ContactChoice] = []
    try CNContactStore().enumerateContacts(with: request) { contact, _ in
      contacts.append(
        (
          contact.identifier,
          CNContactFormatter.string(from: contact, style: .fullName) ?? "Unnamed contact",
          contact.phoneNumbers.first?.value.stringValue
        ))
    }
    return contacts
  }
}

struct ContactPicker: UIViewControllerRepresentable {
  var selected: (String?) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(selected) }
  final class Coordinator: NSObject, CNContactPickerDelegate {
    let selected: (String?) -> Void
    init(_ selected: @escaping (String?) -> Void) { self.selected = selected }
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
      selected(contact.identifier)
    }
    func contactPickerDidCancel(_ picker: CNContactPickerViewController) { selected(nil) }
  }
  func makeUIViewController(context: Context) -> CNContactPickerViewController {
    let picker = CNContactPickerViewController()
    picker.delegate = context.coordinator
    return picker
  }
  func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}
}
