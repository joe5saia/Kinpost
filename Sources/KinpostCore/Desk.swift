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
  @ObservationIgnored private var refreshWaiters: [CheckedContinuation<Bool, Never>] = []
  public init(_ exchange: any Exchange) { self.exchange = exchange }

  private func perform<T>(_ work: () async throws -> T) async -> T? {
    guard !busy else { return nil }
    busy = true
    let result: T?
    do { result = try await work() } catch {
      problem = error.localizedDescription
      result = nil
    }
    await finishRefreshing()
    return result
  }
  @discardableResult public func refresh() async -> Bool {
    await withCheckedContinuation { continuation in
      refreshWaiters.append(continuation)
      if !busy {
        busy = true
        Task { await finishRefreshing() }
      }
    }
  }
  private func finishRefreshing() async {
    while !refreshWaiters.isEmpty {
      let batch = refreshWaiters
      refreshWaiters.removeAll()
      let success: Bool
      do {
        book = try await exchange.read()
        success = true
      } catch {
        problem = error.localizedDescription
        success = false
      }
      for waiter in batch { waiter.resume(returning: success) }
    }
    busy = false
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
