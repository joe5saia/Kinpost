import KinpostCore
import SwiftUI
import UniformTypeIdentifiers

private struct CardExport: Transferable {
  let card: Card
  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .json) { value in
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      return try encoder.encode(value.card)
    }
  }
}

struct PrivacyView: View {
  let session: Session
  @State private var deletingRevision: String?
  @State private var exporting = false
  private static let policy = Bundle.main.url(forResource: "Privacy", withExtension: "txt").flatMap
  {
    try? String(contentsOf: $0, encoding: .utf8)
  }

  var body: some View {
    List {
      if !session.desk.book.card.name.isEmpty {
        Section {
          Button("Export my card", systemImage: "square.and.arrow.up") { exporting = true }
          Button("Delete my card", role: .destructive) {
            deletingRevision = session.desk.book.revision
          }
        } header: {
          Text("Your data")
        } footer: {
          Text(
            "An export is a file with all your card details, including household members. It won’t update and can’t be revoked."
          )
        }
      }
      if let policy = Self.policy {
        ForEach(policy.components(separatedBy: "\n\n"), id: \.self) { paragraph in
          let lines = paragraph.split(separator: "\n", maxSplits: 1)
          if lines.count == 2 {
            Section {
              Text(lines[1]).font(.body)
            } header: {
              Text(lines[0])
            }
          }
        }
      } else {
        Text("The bundled privacy policy could not be opened.")
      }
    }.navigationTitle("Privacy and data").navigationBarTitleDisplayMode(.inline)
      .toolbarVisibility(.hidden, for: .tabBar)
      .fileExporter(
        isPresented: $exporting, item: CardExport(card: session.desk.book.card),
        contentTypes: [.json], defaultFilename: "My Kinpost card"
      ) { result in
        if case .failure(let error) = result { session.desk.problem = error.localizedDescription }
      }
      .confirmationDialog(
        "Delete your card and all its shares?",
        isPresented: Binding(
          get: { deletingRevision != nil }, set: { if !$0 { deletingRevision = nil } }),
        titleVisibility: .visible, presenting: deletingRevision
      ) { revision in
        Button("Delete my card", role: .destructive) {
          Task { await session.changeSharing(.deleteCard(revision: revision)) }
        }
      } message: { _ in
        Text(
          "This can’t be undone. Cards shared with you and copies already saved to Contacts are not deleted."
        )
      }
  }
}
