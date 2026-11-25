import ContactsUI
import CryptoKit
import KinpostCore
import SwiftUI

/// Local-only bookkeeping. Keep field identifiers, not a second copy of the contact data.
@MainActor @Observable final class AddressBook {
  private struct Link: Codable {
    var contact = "", created = false, owned: [String] = [], digest = ""
  }
  private var links: [String: Link]
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
    try save()
  }
  func authorize() async throws {
    guard try await store.requestAccess(for: .contacts) else {
      throw BookError.message(
        "Allow Contacts access in Settings, or keep this card in Kinpost only.")
    }
  }
  func sync(_ person: Connection, owner: String, existing: String? = nil) throws {
    let id = owner + "/" + person.id
    var link = links[id] ?? Link()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let c = person.card
    let digest = Data(SHA256.hash(data: try encoder.encode(c))).base64EncodedString()
    guard link.digest != digest else { return }
    let keys =
      [
        CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey,
        CNContactPostalAddressesKey, CNContactBirthdayKey, CNContactDatesKey, CNContactRelationsKey,
      ] as [CNKeyDescriptor]
    let target: CNMutableContact
    let request = CNSaveRequest()
    let targetID = existing ?? (link.contact.isEmpty ? nil : link.contact)
    if let targetID {
      guard !links.contains(where: { $0.key != id && $0.value.contact == targetID }) else {
        throw BookError.message("Another card is already linked to this contact.")
      }
      target =
        try store.unifiedContact(withIdentifier: targetID, keysToFetch: keys).mutableCopy()
        as! CNMutableContact
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
    link.contact = target.identifier
    link.digest = digest
    links[id] = link
    try save()
  }
  func reconcile(_ book: Book) throws {
    for person in book.people where linked(book.owner + "/" + person.id) {
      try sync(person, owner: book.owner)
    }
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
