import KinpostCore
import SwiftUI

struct Editor: View {
  let desk: Desk
  @State var card: Card
  @State var revision: String
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        Section("Name") {
          TextField("First name", text: $card.first).textContentType(.givenName)
          TextField("Last name", text: $card.last).textContentType(.familyName)
        }
        Section("Phone numbers") {
          ForEach($card.phones) { $phone in
            HStack {
              Picker("Label", selection: $phone.label) {
                ForEach(["Mobile", "Home", "Work", "Other"], id: \.self) { Text($0) }
              }.labelsHidden().fixedSize()
              TextField("Number", text: $phone.number).keyboardType(.phonePad).textContentType(
                .telephoneNumber)
              Button(role: .destructive) {
                card.phones.removeAll { $0.id == phone.id }
              } label: {
                Image(systemName: "minus.circle")
              }.buttonStyle(.borderless).accessibilityLabel("Remove \(phone.label) number")
            }
          }
          Button("Add number", systemImage: "plus") { card.phones.append(Phone()) }
        }
        Section("Mailing address") {
          TextField("Street and apartment", text: $card.street, axis: .vertical).textContentType(
            .streetAddressLine1)
          TextField("City", text: $card.city).textContentType(.addressCity)
          TextField("State or region", text: $card.region).textContentType(.addressState)
          TextField("Postal code", text: $card.postal).textContentType(.postalCode)
          TextField("Country", text: $card.country).textContentType(.countryName)
        }
        Section("Personal dates") {
          OptionalDate(title: "Birthday", parts: $card.birthday)
          OptionalDate(title: "Anniversary", parts: $card.anniversary)
        }
        Section {
          if let partner = Binding($card.partner) {
            MemberFields(member: partner)
            Button("Remove partner", role: .destructive) { card.partner = nil }
          } else {
            Button("Add partner", systemImage: "plus") { card.partner = HouseholdMember() }
          }
        } header: {
          Text("Spouse or partner")
        } footer: {
          Text(
            "Family details are only included in the Household profile. Share them with your family’s permission."
          )
        }
        ForEach($card.children) { $child in
          Section("Child") {
            MemberFields(member: $child)
            Button("Remove child", role: .destructive) {
              card.children.removeAll { $0.id == child.id }
            }
          }
        }
        Section {
          Button("Add child", systemImage: "plus") { card.children.append(HouseholdMember()) }
        }
      }.scrollDismissesKeyboard(.interactively).navigationTitle("Edit card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") { Task { if await desk.save(card, basedOn: revision) { dismiss() } } }
              .disabled(desk.busy || card.name.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }
    }.interactiveDismissDisabled(desk.busy).deskErrors(desk)
  }
}
private struct MemberFields: View {
  @Binding var member: HouseholdMember
  var body: some View {
    TextField("Name", text: $member.name)
    TextField("Phone (optional)", text: $member.phone).keyboardType(.phonePad)
    OptionalDate(title: "Birthday", parts: $member.birthday)
  }
}
private struct OptionalDate: View {
  var title: String
  @Binding var parts: DateComponents?
  private var calendar: Calendar { Calendar(identifier: .gregorian) }
  var body: some View {
    if parts != nil {
      HStack {
        DatePicker(
          title,
          selection: Binding(
            get: { parts.flatMap { calendar.date(from: $0) } ?? Date() },
            set: { parts = calendar.dateComponents([.year, .month, .day], from: $0) }),
          displayedComponents: .date)
        Button(role: .destructive) {
          parts = nil
        } label: {
          Image(systemName: "minus.circle")
        }.buttonStyle(.borderless).accessibilityLabel("Remove \(title)")
      }
    } else {
      Button("Add \(title.lowercased())", systemImage: "plus") {
        parts = calendar.dateComponents([.year, .month, .day], from: .now)
      }
    }
  }
}
