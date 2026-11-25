import ContactsUI
import KinpostCore
import SwiftUI

struct PeopleView: View {
  let session: Session
  @State private var request = false
  var body: some View {
    List {
      Section { Button("Open invitation", systemImage: "link") { request = true } }
      Section {
        if session.desk.book.people.isEmpty && session.desk.book.unavailablePeople.isEmpty {
          ContentUnavailableView(
            "No cards yet", systemImage: "tray",
            description: Text("Open a friend’s invitation to request their card."))
        }
        ForEach(session.desk.book.people) { p in
          NavigationLink(value: p.id) {
            HStack(spacing: 12) {
              Text(p.card.initials).font(.system(.headline, design: .serif)).foregroundStyle(
                .postBlue
              ).frame(width: 43, height: 43).background(.postBlue.opacity(0.09), in: Circle())
              VStack(alignment: .leading, spacing: 3) {
                Text(p.card.name).font(.headline)
                if session.contacts.problems[session.desk.book.owner + "/" + p.id] != nil {
                  Label("Contacts sync paused", systemImage: "exclamationmark.circle").font(
                    .subheadline)
                } else {
                  Text(p.audience.title).font(.subheadline).foregroundStyle(.secondary)
                }
              }
            }.padding(.vertical, 3)
          }
        }
        ForEach(session.desk.book.unavailablePeople.sorted(), id: \.self) { id in
          VStack(alignment: .leading, spacing: 4) {
            Label("Shared card unavailable (…\(id.suffix(6)))", systemImage: "icloud.slash")
            Text("Pull to refresh. No Contacts update was applied.").font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
      } header: {
        Kicker("Received cards")
      } footer: {
        Text("Cards stay here unless you choose to link them to Apple Contacts.")
      }
    }.scrollContentBackground(.hidden).background(Color.paper).navigationTitle("People").refreshable
    { await session.refresh() }
    .navigationDestination(for: String.self) { id in PersonView(session: session, id: id) }
    .sheet(isPresented: $request) { RequestView(session: session, initial: "") }
  }
}

private struct PersonView: View {
  let session: Session, id: String
  @State private var pick = false
  @State private var options = false
  @State private var leaving: Connection?
  var body: some View {
    Group {
      if let p = session.desk.book.people.first(where: { $0.id == id }) {
        let owner = session.desk.book.owner
        let key = owner + "/" + p.id
        ScrollView {
          VStack(alignment: .leading, spacing: 19) {
            Kicker("Received card / \(p.audience.title)").foregroundStyle(.postBlue)
            Text(p.card.name).font(.system(.largeTitle, design: .serif, weight: .semibold))
            CardDetails(card: p.card)
            VStack(alignment: .leading, spacing: 12) {
              Text("Apple Contacts").font(.headline)
              if let problem = session.contacts.problems[key] {
                Label("Sync paused", systemImage: "exclamationmark.circle").font(
                  .subheadline.bold())
                Text(problem).font(.subheadline).foregroundStyle(.secondary)
                Button("Choose a contact to relink") { chooseContact() }.buttonStyle(.bordered)
              } else {
                Text(
                  session.contacts.linked(key)
                    ? "Linked on this iPhone. New details are applied when Kinpost refreshes."
                    : "Create a contact or choose an existing one. Other numbers and addresses stay intact."
                ).font(.subheadline).foregroundStyle(.secondary)
              }
              if session.contacts.linked(key) {
                Button("Stop syncing", role: .destructive) {
                  do { try session.contacts.unlink(key) } catch {
                    session.desk.problem = error.localizedDescription
                  }
                }
              } else {
                Button("Link to Contacts", systemImage: "person.crop.circle.badge.plus") {
                  options = true
                }.buttonStyle(.bordered)
              }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
              .pageRow, in: RoundedRectangle(cornerRadius: 18))
            ShareLink(item: p.url) {
              Label("Forward request link", systemImage: "arrowshape.turn.up.right")
            }
            Text("The owner decides who gets access.").font(.footnote).foregroundStyle(.secondary)
            Button("Leave this profile", role: .destructive) { leaving = p }
          }.padding(20)
        }.refreshable { await session.refresh() }
          .confirmationDialog(
            "Leave this profile?",
            isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
            titleVisibility: .visible, presenting: leaving
          ) { person in
            Button("Leave \(person.audience.title)", role: .destructive) {
              Task { await session.changeSharing(.leave(person)) }
            }
          } message: { person in
            Text(
              "You’ll stop receiving \(person.card.name)’s \(person.audience.title) profile. Other profiles you’ve accepted still work. Contacts copies aren’t deleted."
            )
          }
          .confirmationDialog(
            "Link this card to Apple Contacts?", isPresented: $options, titleVisibility: .visible
          ) {
            Button("Create new contact") {
              Task {
                do {
                  try await session.contacts.authorize()
                  await link(p, owner: owner)
                } catch { session.desk.problem = error.localizedDescription }
              }
            }
            Button("Choose existing contact") { chooseContact() }
          } message: {
            Text(
              "Kinpost will update numbers and addresses it adds or matches. Other entries stay yours. Revoking access won’t erase the saved copy."
            )
          }
          .sheet(isPresented: $pick) {
            let selected: (String?) -> Void = { identifier in
              pick = false
              if let identifier {
                Task { await link(p, owner: owner, existing: identifier) }
              }
            }
            if CNContactStore.authorizationStatus(for: .contacts) == .limited {
              PermittedContactPicker(selected: selected)
            } else {
              ContactPicker(selected: selected)
            }
          }
      } else {
        ContentUnavailableView(
          "Card unavailable", systemImage: "lock",
          description: Text(
            session.desk.book.unavailablePeople.contains(id)
              ? "This card couldn’t be read. Refresh People to try again."
              : "You no longer have access to this card."))
      }
    }.background(Color.paper).navigationBarTitleDisplayMode(.inline)
  }
  private func link(_ shown: Connection, owner: String, existing: String? = nil) async {
    // The picker or permission prompt can outlive the account or the grant.
    guard await session.desk.refresh() else { return }
    guard session.desk.book.owner == owner,
      let current = session.desk.book.people.first(where: {
        $0.id == shown.id && $0.shareID == shown.shareID
      })
    else {
      session.desk.problem = "Access changed. Reopen the card before linking it."
      return
    }
    do { try session.contacts.sync(current, owner: owner, existing: existing) } catch {
      session.desk.problem = error.localizedDescription
    }
  }
  private func chooseContact() {
    Task {
      do {
        try await session.contacts.authorize()
        pick = true
      } catch { session.desk.problem = error.localizedDescription }
    }
  }
}

private struct PermittedContactPicker: View {
  let selected: (String?) -> Void
  @State private var permitted: [AddressBook.ContactChoice] = []
  @State private var grant = false
  @State private var problem: String?
  var body: some View {
    NavigationStack {
      List {
        Section {
          Button("Manage allowed contacts", systemImage: "person.badge.plus") { grant = true }
        } footer: {
          Text("Allow Kinpost to update a contact, then choose it below to link this card.")
        }
        Section("Allowed contacts") {
          if let problem {
            Text(problem)
          } else if permitted.isEmpty {
            Text("No contacts allowed yet.").foregroundStyle(.secondary)
          }
          ForEach(permitted, id: \.id) { person in
            Button {
              selected(person.id)
            } label: {
              VStack(alignment: .leading) {
                Text(person.name)
                if let phone = person.phone {
                  Text(phone).font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }.navigationTitle("Choose contact").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selected(nil) } }
      }.task { await load() }.contactAccessPicker(isPresented: $grant) { @Sendable _ in
        Task { @MainActor in await load() }
      }
    }
  }
  private func load() async {
    do {
      permitted = try await AddressBook.permittedContacts()
      problem = nil
    } catch {
      permitted = []
      problem = error.localizedDescription
    }
  }
}

struct AccessView: View {
  let session: Session
  @State private var decision: Access?
  @State private var stopping: (tier: Audience, id: String)?
  private func title(_ state: AccessState) -> String {
    switch state {
    case .requested: "Requests"
    case .invited: "Invited · awaiting acceptance"
    case .accepted: "Sharing with"
    case .blocked: "Blocked requests"
    }
  }
  var body: some View {
    List {
      Section {
        Label(
          "You choose who sees each version of your card. An invitation alone never grants access.",
          systemImage: "lock.shield"
        ).font(.subheadline).foregroundStyle(.secondary)
      }
      ForEach(AccessState.allCases, id: \.self) { state in
        let entries = session.desk.book.access.filter { $0.state == state }
        if state == .requested || !entries.isEmpty {
          Section {
            if entries.isEmpty {
              Text("No pending requests").foregroundStyle(.secondary)
            }
            ForEach(entries) { entry($0) }
          } header: {
            Kicker(title(state))
          }
        }
      }
      Section {
        if session.desk.book.shares.isEmpty {
          Text("No active sharing links").foregroundStyle(.secondary)
        }
        ForEach(Audience.allCases) { tier in
          if let id = session.desk.book.shares[tier] {
            Button {
              stopping = (tier, id)
            } label: {
              Label(tier.title, systemImage: tier.symbol)
            }.accessibilityHint("Manage sharing for this profile")
              .confirmationDialog(
                "Stop sharing \(tier.title)?",
                isPresented: Binding(
                  get: { stopping?.id == id }, set: { if !$0 { stopping = nil } }),
                titleVisibility: .visible, presenting: stopping
              ) { link in
                Button("Stop sharing with everyone", role: .destructive) {
                  Task { await session.changeSharing(.stop(link.tier, shareID: link.id)) }
                }
              } message: { _ in
                Text(
                  "All invitations, requests and grants for this profile end. You keep your card. Other profiles and saved copies aren’t affected. If you share it again, the same link may work for new requests."
                )
              }
          }
        }
      } header: {
        Kicker("Active sharing links")
      } footer: {
        Text("Select a profile to stop sharing it with everyone.")
      }
      Section {
        NavigationLink("Privacy and data") { PrivacyView(session: session) }
      }
    }.scrollContentBackground(.hidden).background(Color.paper).navigationTitle("Access").refreshable
    { await session.refresh() }
  }
  private func entry(_ a: Access) -> some View {
    Button {
      decision = a
    } label: {
      HStack {
        DetailLine(
          icon: a.audience.symbol, label: a.audience.title,
          value: [
            a.name, a.handle ?? (a.state == .requested ? "Account details unavailable" : nil),
          ].compactMap { $0 }.joined(separator: "\n"))
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
      }.contentShape(Rectangle())
    }.buttonStyle(.plain)
      .confirmationDialog(
        [a.name, a.handle, a.audience.title].compactMap { $0 }.joined(separator: " · "),
        isPresented: Binding(get: { decision == a }, set: { if !$0 { decision = nil } }),
        titleVisibility: .visible, presenting: decision
      ) { a in
        switch a.state {
        case .requested:
          Button("Approve \(a.audience.title.lowercased()) access") {
            respond(a, .approve)
          }.disabled(a.handle == nil)
          Button("Decline request", role: .destructive) { respond(a, .deny) }
          Button("Block requests for this profile", role: .destructive) { respond(a, .block) }
        case .accepted, .invited:
          Button(a.state == .accepted ? "Revoke access" : "Withdraw invitation", role: .destructive)
          {
            respond(a, .revoke)
          }
        case .blocked:
          Button("Unblock requests") { respond(a, .unblock) }
        }
      } message: { a in
        switch a.state {
        case .requested:
          Text(
            "If approved, they can accept an invitation to see \(a.audience.detail.lowercased()). Declining lets them ask again; blocking prevents new requests for this profile."
          )
        case .invited, .accepted:
          Text(
            "Removing this person stops access to this profile only. They can request it again. Other grants and copies already saved in Contacts are not removed."
          )
        case .blocked: Text("They can ask again. Unblocking does not give them your card.")
        }
      }
  }
  private func respond(_ access: Access, _ decision: AccessDecision) {
    Task { await session.changeSharing(.respond(access, decision)) }
  }
}
