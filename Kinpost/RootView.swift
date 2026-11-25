import KinpostCore
import SwiftUI

struct RootView: View {
  @Bindable var session: Session
  @State private var tab = 0
  @State private var edit = false
  @State private var share = false
  @State private var choosePerson = false
  private var desk: Desk { session.desk }
  var body: some View {
    TabView(selection: $tab) {
      Tab("My card", systemImage: "person.text.rectangle", value: 0) {
        NavigationStack {
          ScrollView {
            VStack(alignment: .leading, spacing: 18) {
              VStack(alignment: .leading, spacing: 5) {
                Text("My card").font(.largeTitle.bold())
                Text("One card that stays current.").foregroundStyle(.secondary)
              }
              if session.cloud != nil && desk.book.owner.isEmpty {
                ContentUnavailableView {
                  Label("Connect to iCloud", systemImage: "icloud")
                } description: {
                  Text(
                    "Sign in to iCloud in Settings and connect to the internet to load your private card."
                  )
                } actions: {
                  Button(desk.busy ? "Connecting…" : "Try again") {
                    Task { await session.refresh() }
                  }.disabled(desk.busy)
                }
              } else {
                CallingCard(card: desk.book.card)
                Button {
                  if desk.book.card.name.isEmpty { edit = true } else { share = true }
                } label: {
                  MainButton(
                    title: desk.book.card.name.isEmpty ? "Create my card" : "Share my card",
                    icon: desk.book.card.name.isEmpty ? "plus" : "square.and.arrow.up")
                }.buttonStyle(.glassProminent).controlSize(.large).disabled(
                  desk.busy || desk.book.owner.isEmpty)
                HStack {
                  Text("Card details").font(.title2.bold())
                  Spacer()
                  Button("Edit") { edit = true }.font(.subheadline.weight(.semibold)).disabled(
                    desk.book.owner.isEmpty)
                }.padding(.top, 5)
                CardDetails(card: desk.book.card)
              }
            }.padding(.horizontal, 20).padding(.vertical, 10)
          }.background(Color.paper).refreshable { await session.refresh() }.toolbar { brandToolbar }
            .navigationBarTitleDisplayMode(.inline)
        }
      }
      Tab("People", systemImage: "person.2", value: 1) {
        NavigationStack { PeopleView(session: session).toolbar { brandToolbar } }
      }
      Tab("Access", systemImage: "key.horizontal", value: 2) {
        NavigationStack { AccessView(session: session).toolbar { brandToolbar } }
      }.badge(desk.book.access.filter { $0.state == .requested }.count)
    }
    .sheet(isPresented: $edit) {
      Editor(desk: desk, card: desk.book.card, revision: desk.book.revision)
    }
    .sheet(isPresented: $share) { SharingView(session: session) }
    .sheet(isPresented: $choosePerson) {
      NavigationStack {
        List {
          Section {
            ForEach(SampleExchange.identities, id: \.self) { id in
              Button {
                choosePerson = false
                Task { await session.changePerson(id) }
              } label: {
                HStack {
                  Text(session.sample?.name(id) ?? id)
                  Spacer()
                  if desk.book.owner == id { Image(systemName: "checkmark") }
                }
              }
            }
          } footer: {
            Text(
              "These three fictional people share an address book on this simulator. Switch people to request, approve, and see live changes. No iCloud sign-in is needed."
            )
          }
        }
        .navigationTitle("Sample people").toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { choosePerson = false } }
        }
      }.presentationDetents([.medium, .large])
    }
    .sheet(
      isPresented: Binding(
        get: { session.incoming != nil }, set: { if !$0 { session.incoming = nil } })
    ) { RequestView(session: session, initial: session.incoming?.absoluteString ?? "") }
    .deskErrors(desk)
  }
  @ToolbarContentBuilder private var brandToolbar: some ToolbarContent {
    ToolbarItem(placement: .principal) {
      HStack(spacing: 6) {
        Image(systemName: "paperplane.fill").font(.caption)
        Text("Kinpost").font(.system(.headline, design: .serif, weight: .semibold)).italic()
      }.fixedSize().foregroundStyle(.postBlue).accessibilityElement(children: .combine)
    }
    if session.sample != nil {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Sample") { choosePerson = true }.accessibilityLabel("Switch sample person")
          .disabled(desk.busy)
      }
    }
  }
}

struct CardDetails: View {
  var card: Card
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if card.phones.isEmpty && card.address.isEmpty && card.birthday == nil
        && card.anniversary == nil && card.partner == nil && card.children.isEmpty
      {
        Text("No details added yet.").foregroundStyle(.secondary).padding()
      }
      ForEach(card.phones) { phone in row("phone", phone.label, phone.number) }
      if !card.address.isEmpty {
        row(
          "house", "Home address",
          [
            card.street, [card.city, card.region].filter { !$0.isEmpty }.joined(separator: ", "),
            card.postal, card.country,
          ].filter { !$0.isEmpty }.joined(separator: " · "))
      }
      if let birthday = displayDate(card.birthday) { row("birthday.cake", "Birthday", birthday) }
      if let anniversary = displayDate(card.anniversary) {
        row("calendar", "Anniversary", anniversary)
      }
      if let partner = card.partner { member(partner, "Partner") }
      ForEach(card.children) { member($0, "Child") }
    }.frame(maxWidth: .infinity, alignment: .leading).background(
      .pageRow, in: RoundedRectangle(cornerRadius: 18)
    ).clipShape(RoundedRectangle(cornerRadius: 18))
  }
  private func row(_ symbol: String, _ title: String, _ value: String) -> some View {
    VStack(spacing: 0) {
      DetailLine(icon: symbol, label: title, value: value).padding(.horizontal, 14).padding(
        .vertical, 7)
      Divider().padding(.leading, 66)
    }
  }
  private func member(_ member: HouseholdMember, _ relationship: String) -> some View {
    row(
      "person.2", relationship,
      [member.name, member.phone, displayDate(member.birthday) ?? ""].filter { !$0.isEmpty }.joined(
        separator: " · "))
  }
}

extension View {
  func deskErrors(_ desk: Desk) -> some View {
    alert(
      "Kinpost",
      isPresented: Binding(get: { desk.problem != nil }, set: { if !$0 { desk.problem = nil } })
    ) {
      Button("OK") { desk.problem = nil }
    } message: {
      Text(desk.problem ?? "")
    }
  }
}
