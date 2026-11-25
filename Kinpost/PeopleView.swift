import KinpostCore
import SwiftUI

struct PeopleView: View {
  let session: Session
  @State private var request = false
  var body: some View {
    List {
      Section { Button("Open invitation", systemImage: "link") { request = true } }
      Section {
        if session.desk.book.people.isEmpty {
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
                Text(p.audience.title).font(.subheadline).foregroundStyle(.secondary)
              }
            }.padding(.vertical, 3)
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
  var body: some View {
    Group {
      if let p = session.desk.book.people.first(where: { $0.id == id }) {
        let key = session.desk.book.owner + "/" + p.id
        ScrollView {
          VStack(alignment: .leading, spacing: 19) {
            Kicker("Received card / \(p.audience.title)").foregroundStyle(.postBlue)
            Text(p.card.name).font(.system(.largeTitle, design: .serif, weight: .semibold))
            CardDetails(card: p.card)
            VStack(alignment: .leading, spacing: 12) {
              Text("Apple Contacts").font(.headline)
              Text(
                session.contacts.linked(key)
                  ? "Linked on this iPhone. New details are applied when Kinpost refreshes."
                  : "Create a contact or choose an existing one. Other numbers and addresses stay intact."
              ).font(.subheadline).foregroundStyle(.secondary)
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
          }.padding(20)
        }.refreshable { await session.refresh() }
          .confirmationDialog(
            "Link this card to Apple Contacts?", isPresented: $options, titleVisibility: .visible
          ) {
            Button("Create new contact") {
              Task {
                do {
                  try await session.contacts.authorize()
                  try session.contacts.sync(p, owner: session.desk.book.owner)
                } catch { session.desk.problem = error.localizedDescription }
              }
            }
            Button("Choose existing contact") {
              Task {
                do {
                  try await session.contacts.authorize()
                  pick = true
                } catch { session.desk.problem = error.localizedDescription }
              }
            }
          } message: {
            Text(
              "Kinpost will update numbers and addresses it adds or matches. Other entries stay yours. Revoking access won’t erase the saved copy."
            )
          }
          .sheet(isPresented: $pick) {
            ContactPicker { identifier in
              pick = false
              if let identifier {
                do {
                  try session.contacts.sync(p, owner: session.desk.book.owner, existing: identifier)
                } catch { session.desk.problem = error.localizedDescription }
              }
            }
          }
      } else {
        ContentUnavailableView(
          "Card unavailable", systemImage: "lock",
          description: Text("You no longer have access to this card."))
      }
    }.background(Color.paper).navigationBarTitleDisplayMode(.inline)
  }
}

struct AccessView: View {
  let session: Session
  @State private var decision: Access?
  var body: some View {
    List {
      Section {
        Label(
          "You choose who sees each version of your card. An invitation alone never grants access.",
          systemImage: "lock.shield"
        ).font(.subheadline).foregroundStyle(.secondary)
      }
      ForEach([true, false], id: \.self) { pending in
        Section {
          let entries = session.desk.book.access.filter { $0.pending == pending }
          if entries.isEmpty {
            Text(pending ? "No pending requests" : "No one has access yet").foregroundStyle(
              .secondary)
          }
          ForEach(entries) { a in
            Button {
              decision = a
            } label: {
              HStack {
                DetailLine(icon: a.audience.symbol, label: a.audience.title, value: a.name)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
              }.contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
        } header: {
          Kicker(pending ? "Requests" : "Shared with")
        }
      }
    }.scrollContentBackground(.hidden).background(Color.paper).navigationTitle("Access").refreshable
    { await session.refresh() }
    .confirmationDialog(
      decision.map { "\($0.name) · \($0.audience.title)" } ?? "Card access",
      isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } }),
      titleVisibility: .visible, presenting: decision
    ) { a in
      if a.pending {
        Button("Approve \(a.audience.title.lowercased()) access") {
          Task { await session.desk.decide(a, allow: true) }
        }
      }
      Button(a.pending ? "Decline request" : "Revoke access", role: .destructive) {
        Task { await session.desk.decide(a, allow: false) }
      }
    } message: { a in
      Text(
        a.pending
          ? "This person will receive: \(a.audience.detail.lowercased())."
          : "This stops updates for this profile. It cannot recall a copy already saved in Contacts."
      )
    }
  }
}
