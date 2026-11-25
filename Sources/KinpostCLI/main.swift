import Foundation
import KinpostCore

@main struct KinpostCLI {
  @MainActor static func main() async throws {
    let file = ProcessInfo.processInfo.environment["KINPOST_SAMPLE_FILE"].map {
      URL(fileURLWithPath: $0)
    }
    let exchange = try SampleExchange(file: file)
    let desk = Desk(exchange)
    var lastLink: URL?
    print("Kinpost sample desk · type help for commands")
    await desk.refresh()
    while let line = readLine() {
      let words = line.split(separator: " ", maxSplits: 1).map(String.init)
      guard let command = words.first else { continue }
      let arg = words.count == 2 ? words[1] : ""
      do {
        switch command {
        case "help":
          print(
            "as avery|mira|theo • ls • card • people • access • invite phone|home|personal|household • request [URL] • approve|deny|block|unblock|revoke PERSON:TIER • stop TIER • leave PERSON • delete-card • number NUMBER • view PERSON • quit"
          )
        case "as":
          try exchange.switchTo(arg)
          await desk.refresh()
        case "card": try printCard(desk.book.card)
        case "ls":
          print(
            "\(desk.book.owner): \(desk.book.card.name); people=\(desk.book.people.count) requests=\(desk.book.access.filter { $0.state == .requested }.count)"
          )
        case "people":
          for p in desk.book.people { print("\(p.id): \(p.card.name) · \(p.audience.title)") }
        case "view":
          guard let person = desk.book.people.first(where: { $0.id == arg }) else {
            throw BookError.message("No visible card for \(arg)")
          }
          try printCard(person.card)
        case "access":
          for a in desk.book.access {
            print("\(a.key):\(a.audience.rawValue) \(a.state.rawValue)")
          }
        case "invite":
          guard let tier = Audience(rawValue: arg) else {
            throw BookError.message("Unknown audience")
          }
          lastLink = await desk.invitation(tier)
          if let lastLink { print(lastLink.absoluteString) }
        case "request":
          guard let link = arg.isEmpty ? lastLink : URL(string: arg) else {
            throw BookError.message("Create an invitation first")
          }
          _ = await desk.request(link)
        case "approve", "deny", "block", "unblock", "revoke":
          guard let decision = AccessDecision(rawValue: command),
            let access = desk.book.access.first(where: {
              "\($0.key):\($0.audience.rawValue)" == arg
            })
          else { throw BookError.message("No matching access entry") }
          await desk.changeSharing(.respond(access, decision))
        case "stop":
          guard let tier = Audience(rawValue: arg), let id = desk.book.shares[tier] else {
            throw BookError.message("No matching share")
          }
          await desk.changeSharing(.stop(tier, shareID: id))
        case "leave":
          guard let person = desk.book.people.first(where: { $0.id == arg }) else {
            throw BookError.message("No matching card")
          }
          await desk.changeSharing(.leave(person))
        case "delete-card": await desk.changeSharing(.deleteCard(revision: desk.book.revision))
        case "number":
          var c = desk.book.card
          c.phones = [Phone("Mobile", arg)]
          _ = await desk.save(c, basedOn: desk.book.revision)
        case "quit": return
        default: throw BookError.message("Unknown command. Type help.")
        }
        if let error = desk.problem {
          desk.problem = nil
          throw BookError.message(error)
        }
      } catch { print("Error: \(error.localizedDescription)") }
    }
  }
  static func printCard(_ card: Card) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    print(String(decoding: try enc.encode(card), as: UTF8.self))
  }
}
