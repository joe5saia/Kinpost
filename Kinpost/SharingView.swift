import CoreImage.CIFilterBuiltins
import KinpostCore
import SwiftUI

struct SharingView: View {
  let session: Session
  @Environment(\.dismiss) private var dismiss
  @State private var tier = Audience.phone
  @State private var invitation: (url: URL, audience: Audience)?
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Kicker(invitation == nil ? "01 / Sharing profile" : "02 / Invitation").foregroundStyle(
            .postBlue)
          VStack(alignment: .leading, spacing: 8) {
            Text(invitation == nil ? "What goes with it?" : "Ready to share.").font(
              .largeTitle.bold())
            Text(
              invitation == nil
                ? "Choose which details this person can see, now and when your card changes."
                : "Send the invitation or let someone scan it with their iPhone camera."
            ).foregroundStyle(.secondary)
          }
          if let invitation {
            let (link, tier) = invitation
            VStack(spacing: 12) {
              QRView(url: link)
              Text(tier.title).font(.system(.title2, design: .serif, weight: .semibold))
              Kicker("Approval required").foregroundStyle(.postBlue)
            }.padding(20).frame(maxWidth: .infinity).background(
              .pageRow, in: RoundedRectangle(cornerRadius: 20))
            ShareLink(
              item: link, subject: Text("My Kinpost card"),
              message: Text("Request access to my \(tier.title.lowercased()) card.")
            ) { MainButton(title: "Send invitation", icon: "square.and.arrow.up") }.buttonStyle(
              .glassProminent
            ).controlSize(.large)
            Button("Choose another profile", systemImage: "chevron.backward") {
              self.invitation = nil
            }
            if let sample = session.sample {
              VStack(alignment: .leading, spacing: 8) {
                Kicker("Simulator only").foregroundStyle(.secondary)
                Text("Try the receiving side without another phone.").font(.subheadline)
                Menu("Open as sample person", systemImage: "person.2") {
                  ForEach(SampleExchange.identities.filter { $0 != sample.identity }, id: \.self) {
                    id in
                    Button(sample.name(id)) {
                      Task {
                        await session.changePerson(id)
                        session.opening = link.absoluteString
                      }
                    }
                  }
                }.buttonStyle(.bordered)
              }.padding(.top, 4)
            }
          } else {
            VStack(spacing: 0) {
              ForEach(Audience.allCases) { a in
                Button {
                  tier = a
                } label: {
                  let icon = Image(systemName: a.symbol).frame(width: 38, height: 38)
                    .foregroundStyle(.postBlue)
                    .background(.postBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                  let check = Image(systemName: tier == a ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(tier == a ? Color.postBlue : Color.secondary.opacity(0.5))
                  let text = VStack(alignment: .leading, spacing: 4) {
                    Text(a.title).font(.headline)
                    Text(a.detail).font(.subheadline).foregroundStyle(.secondary)
                  }
                  Group {
                    // Give the description the full row width at accessibility sizes.
                    if typeSize.isAccessibilitySize {
                      VStack(alignment: .leading, spacing: 8) {
                        HStack {
                          icon
                          Spacer()
                          check
                        }
                        text
                      }.frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                      HStack(spacing: 13) {
                        icon
                        text
                        Spacer()
                        check
                      }
                    }
                  }.padding(15).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(tier == a ? .isSelected : [])
                if a != .household {
                  Divider().padding(.leading, typeSize.isAccessibilitySize ? 15 : 66)
                }
              }
            }.background(.pageRow, in: RoundedRectangle(cornerRadius: 18)).disabled(
              session.desk.busy)
            Label(
              "You approve who can read this card. Apple may show account details in the invitation or participant list.",
              systemImage: "lock"
            ).font(.footnote).foregroundStyle(.secondary)
            Button {
              Task { [tier] in
                if let url = await session.desk.invitation(tier) { invitation = (url, tier) }
              }
            } label: {
              MainButton(
                title: session.desk.busy ? "Preparing…" : "Create invitation", icon: "link")
            }.buttonStyle(.glassProminent).controlSize(.large).disabled(session.desk.busy)
          }
        }.padding(22)
      }.background(Color.paper).navigationTitle("Share card").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") { dismiss() }
          }
        }
    }.deskErrors(session.desk)
  }
}
private struct QRView: View {
  let url: URL
  var body: some View {
    let filter = CIFilter.qrCodeGenerator()
    let _ = {
      filter.message = Data(url.absoluteString.utf8)
      filter.correctionLevel = "M"
    }()
    if let image = filter.outputImage, let cg = CIContext().createCGImage(image, from: image.extent)
    {
      Image(decorative: cg, scale: 1).interpolation(.none).resizable().scaledToFit().frame(
        maxWidth: 170, maxHeight: 170
      ).padding(22).background(.white, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel(
        "Invitation QR code")
    }
  }
}

struct RequestView: View {
  let session: Session
  @State var initial: String
  @State private var outcome: InvitationOutcome?
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        if let outcome {
          Section {
            switch outcome {
            case .accepted(let owner):
              if let person = session.desk.book.people.first(where: { $0.id == owner }) {
                Label("\(person.card.name)’s card is in People", systemImage: "checkmark.seal")
                  .font(.headline)
                Text("It stays current as they update it.").foregroundStyle(.secondary)
              } else {
                Label("Invitation accepted", systemImage: "checkmark.seal").font(.headline)
                Text("Refresh People to load the card.").foregroundStyle(.secondary)
              }
            case .requested:
              Label("Request sent", systemImage: "paperplane").font(.headline)
              Text(
                "The owner decides whether to approve it. Once they do, open this same link again to accept. The card then appears in People."
              ).foregroundStyle(.secondary)
            }
          }
        } else {
          Section {
            TextField("Invitation link", text: $initial, axis: .vertical).keyboardType(.URL)
              .textInputAutocapitalization(.never).autocorrectionDisabled()
            PasteButton(payloadType: String.self) { strings in
              if let link = strings.first {
                initial = link.trimmingCharacters(in: .whitespacesAndNewlines)
              }
            }
          } footer: {
            Text(
              "If you’ve already been invited, continuing accepts the invitation. Otherwise Apple can show the owner your name and email or phone so they can decide. Forwarding a link does not grant access."
            )
          }
          Section {
            Button("Accept or request access", systemImage: "paperplane") {
              guard let url = URL(string: initial.trimmingCharacters(in: .whitespacesAndNewlines))
              else {
                session.desk.problem = "Enter a valid Kinpost invitation link."
                return
              }
              Task { outcome = await session.desk.request(url) }
            }.disabled(initial.isEmpty || session.desk.busy)
          }
        }
      }.navigationTitle("Open invitation").navigationBarTitleDisplayMode(.inline).toolbar {
        if outcome == nil {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        } else {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
      }
    }.presentationDetents([.medium, .large]).deskErrors(session.desk)
  }
}
