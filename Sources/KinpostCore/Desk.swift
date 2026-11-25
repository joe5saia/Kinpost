import Foundation
import Observation

@MainActor public protocol Exchange: AnyObject {
  func read() async throws -> Book
  func save(_ card: Card, basedOn revision: String) async throws
  func invitation(_ audience: Audience) async throws -> URL
  func request(_ url: URL) async throws
  func decide(_ access: Access, allow: Bool) async throws
}

/// The iPhone and command-line hosts drive the same actions. SwiftUI owns only presentation and drafts.
@MainActor @Observable public final class Desk {
  public private(set) var book = Book()
  public private(set) var busy = false
  public var problem: String?
  private let exchange: any Exchange
  public init(_ exchange: any Exchange) { self.exchange = exchange }

  private func perform<T>(_ work: () async throws -> T) async -> T? {
    guard !busy else { return nil }
    busy = true
    defer { busy = false }
    do { return try await work() } catch {
      problem = error.localizedDescription
      return nil
    }
  }
  @discardableResult public func refresh() async -> Bool {
    await perform {
      book = try await exchange.read()
      return true
    } ?? false
  }
  public func clearSession() { book = Book() }
  public func save(_ card: Card, basedOn revision: String) async -> Bool {
    await perform {
      try await exchange.save(card.cleaned(), basedOn: revision)
      book = try await exchange.read()
      return true
    } ?? false
  }
  public func invitation(_ audience: Audience) async -> URL? {
    await perform {
      guard !book.card.name.isEmpty else {
        throw BookError.message("Add your name before sharing a card.")
      }
      return try await exchange.invitation(audience)
    }
  }
  public func request(_ url: URL) async -> Bool {
    await perform {
      try await exchange.request(url)
      book = try await exchange.read()
      return true
    } ?? false
  }
  public func decide(_ access: Access, allow: Bool) async {
    _ = await perform {
      try await exchange.decide(access, allow: allow)
      book = try await exchange.read()
    }
  }
}
