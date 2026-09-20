import Darwin
import Foundation

final class EntryShareMailbox {
  static let maximumAgeMilliseconds: Int64 = 15 * 60 * 1000
  private let lock = NSLock()
  private let wallClock: () -> Int64
  private let continuousClock: () -> Int64
  private var pending: String?
  private var receivedAt: Int64 = 0
  private var receivedElapsed: Int64 = 0
  private var generation: Int64 = 0

  init(
    wallClock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
    continuousClock: @escaping () -> Int64 = {
      Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1_000_000)
    }
  ) {
    self.wallClock = wallClock
    self.continuousClock = continuousClock
  }

  func offer(_ candidate: String?, expectedOrigin: String) -> Int64 {
    lock.lock()
    defer { lock.unlock() }
    clearLocked()
    guard let candidate, EntryShareLinkPolicy.accepts(candidate, origin: expectedOrigin) else {
      return generation
    }
    pending = candidate
    receivedAt = wallClock()
    receivedElapsed = continuousClock()
    return generation
  }

  func take() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    var result: [String: Any] = ["generation": generation]
    let age = continuousClock() - receivedElapsed
    if let pending, age >= 0, age < Self.maximumAgeMilliseconds,
       wallClock() - receivedAt < Self.maximumAgeMilliseconds {
      result["url"] = pending
      result["receivedAtUnixMs"] = receivedAt
      result["ageMilliseconds"] = age
    }
    pending = nil
    receivedAt = 0
    receivedElapsed = 0
    return result
  }

  @discardableResult
  func clear() -> Int64 {
    lock.lock()
    defer { lock.unlock() }
    clearLocked()
    return generation
  }

  func clear(expectedGeneration: Int64) -> Int64? {
    lock.lock()
    defer { lock.unlock() }
    guard generation == expectedGeneration else { return nil }
    clearLocked()
    return generation
  }

  private func clearLocked() {
    pending = nil
    receivedAt = 0
    receivedElapsed = 0
    generation += 1
  }
}

enum EntryShareLinkPolicy {
  static func accepts(_ candidate: String, origin: String) -> Bool {
    guard candidate.utf8.count <= 2048,
          matches(origin, #"https://[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?"#) else {
      return false
    }
    let path = #"/share/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"#
    let fragment = #"#v=1&key=[A-Za-z0-9_-]{43}&access=[A-Za-z0-9_-]{43}"#
    return matches(candidate, NSRegularExpression.escapedPattern(for: origin) + path + fragment)
  }

  static func intercepts(_ url: URL) -> Bool {
    let scheme = url.scheme?.lowercased()
    return scheme == "https" || scheme == "http" || url.fragment != nil ||
      url.host?.lowercased() == "share" || url.path.lowercased().hasPrefix("/share")
  }

  private static func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: "\\A(?:" + pattern + ")\\z", options: .regularExpression) != nil
  }
}
