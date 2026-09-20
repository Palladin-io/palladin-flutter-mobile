import CoreSpotlight
import Foundation
import XCTest
@testable import EntrySharingCore

final class EntryShareMailboxTests: XCTestCase {
  private let origin = "https://sharing.example.test"
  private var link: String {
    origin + "/share/00112233-4455-4677-8899-aabbccddeeff#v=1&key=" +
      String(repeating: "A", count: 42) + "E&access=" + String(repeating: "A", count: 42) + "I"
  }

  func testTakeTransfersOnlyOnceWithOriginalArrival() {
    var wall: Int64 = 1_800_000_000_000
    var elapsed: Int64 = 70
    let mailbox = EntryShareMailbox(wallClock: { wall }, continuousClock: { elapsed })
    XCTAssertEqual(mailbox.offer(link, expectedOrigin: origin), 1)
    wall += 2000
    elapsed += 2000
    let reply = mailbox.take()
    XCTAssertEqual(reply["url"] as? String, link)
    XCTAssertEqual(reply["receivedAtUnixMs"] as? Int64, wall - 2000)
    XCTAssertEqual(reply["ageMilliseconds"] as? Int64, 2000)
    XCTAssertEqual(mailbox.take().count, 1)
  }

  func testReplacementAndInvalidCandidateInvalidateTheOldSlot() {
    let mailbox = EntryShareMailbox()
    XCTAssertEqual(mailbox.offer(link, expectedOrigin: origin), 1)
    XCTAssertEqual(mailbox.offer(nil, expectedOrigin: origin), 2)
    XCTAssertEqual(mailbox.take()["generation"] as? Int64, 2)
    XCTAssertNil(mailbox.take()["url"])
    let replacement = link.replacingOccurrences(of: "ddeeff", with: "ddeef0")
    _ = mailbox.offer(link, expectedOrigin: origin)
    _ = mailbox.offer(replacement, expectedOrigin: origin)
    XCTAssertEqual(mailbox.take()["url"] as? String, replacement)
  }

  func testClearAdvancesGenerationAndCannotBeReplayed() {
    let mailbox = EntryShareMailbox()
    _ = mailbox.offer(link, expectedOrigin: origin)
    XCTAssertEqual(mailbox.clear(), 2)
    XCTAssertNil(mailbox.take()["url"])
    XCTAssertEqual(mailbox.take()["generation"] as? Int64, 2)
  }

  func testContinuousCeilingSurvivesWallRollbackAndSleep() {
    var wall: Int64 = 1_800_000_000_000
    var elapsed: Int64 = 0
    let mailbox = EntryShareMailbox(wallClock: { wall }, continuousClock: { elapsed })
    _ = mailbox.offer(link, expectedOrigin: origin)
    wall -= 60_000
    elapsed = EntryShareMailbox.maximumAgeMilliseconds
    XCTAssertNil(mailbox.take()["url"])
  }

  func testWallExpiryAndInvalidMonotonicAgeFailClosed() {
    for rollback in [false, true] {
      var wall: Int64 = 1_800_000_000_000
      var elapsed: Int64 = 100
      let mailbox = EntryShareMailbox(wallClock: { wall }, continuousClock: { elapsed })
      _ = mailbox.offer(link, expectedOrigin: origin)
      if rollback { elapsed = 99 } else { wall += EntryShareMailbox.maximumAgeMilliseconds }
      XCTAssertNil(mailbox.take()["url"])
    }
  }

  func testCanonicalOriginPathAndFragmentOnly() {
    XCTAssertTrue(EntryShareLinkPolicy.accepts(link, origin: origin))
    let invalid = [
      link + "\n", link + "&other=x", link + "=", link.uppercased(),
      link.replacingOccurrences(of: "https:", with: "http:"),
      link.replacingOccurrences(of: "sharing.example.test", with: "sharing.example.test.evil"),
      link.replacingOccurrences(of: "/share/", with: "/ignored/../share/"),
      link.replacingOccurrences(of: "/share/", with: "/%73hare/"),
      link.replacingOccurrences(of: "#", with: "?query=x#"),
      link.replacingOccurrences(of: "https://", with: "https://user@"),
      link.replacingOccurrences(of: "/share/", with: ":443/share/"),
      String(repeating: "a", count: 2049),
    ]
    for candidate in invalid {
      XCTAssertFalse(EntryShareLinkPolicy.accepts(candidate, origin: origin))
    }
    for invalidOrigin in ["", "http://sharing.example.test", origin + "/", origin + "\n"] {
      XCTAssertFalse(EntryShareLinkPolicy.accepts(link, origin: invalidOrigin))
    }
  }

  func testSecretLikeDirectURLsAreNeverForwardedToLegacyPlugins() {
    for raw in [link, "http://example.test/plain", "palladin://share/id", "palladin://host/share/id", "custom://host/#key=x"] {
      XCTAssertTrue(EntryShareLinkPolicy.intercepts(URL(string: raw)!))
    }
    for raw in ["palladin://verify-email?token=fixture", "com.example.oauth:/callback?code=fixture"] {
      XCTAssertFalse(EntryShareLinkPolicy.intercepts(URL(string: raw)!))
    }
  }

  func testActivityScrubRemovesAppOwnedURLAndRestorationFields() {
    let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
    activity.webpageURL = URL(string: link)
    activity.referrerURL = URL(string: link)
    activity.userInfo = ["url": link]
    activity.requiredUserInfoKeys = ["url"]
    activity.title = link
    activity.keywords = [link]
    activity.persistentIdentifier = link
    activity.targetContentIdentifier = link
    let attributes = CSSearchableItemAttributeSet(contentType: .text)
    attributes.title = link
    activity.contentAttributeSet = attributes
    activity.isEligibleForHandoff = true
    activity.isEligibleForSearch = true
    #if os(iOS)
    activity.isEligibleForPrediction = true
    #endif
    XCTAssertTrue(EntryShareActivityPrivacy.intercepts(activity))
    EntryShareActivityPrivacy.scrub(activity)
    XCTAssertNil(activity.webpageURL)
    XCTAssertNil(activity.referrerURL)
    XCTAssertTrue(activity.userInfo?.isEmpty ?? true)
    XCTAssertTrue(activity.requiredUserInfoKeys?.isEmpty ?? true)
    XCTAssertNil(activity.title)
    XCTAssertTrue(activity.keywords.isEmpty)
    XCTAssertNil(activity.targetContentIdentifier)
    XCTAssertNil(activity.persistentIdentifier)
    XCTAssertNil(activity.contentAttributeSet)
    XCTAssertFalse(activity.isEligibleForHandoff)
    XCTAssertFalse(activity.isEligibleForSearch)
    XCTAssertFalse(activity.isEligibleForPublicIndexing)
    #if os(iOS)
    XCTAssertFalse(activity.isEligibleForPrediction)
    #endif
  }

  func testFiniteCeilingIsInclusiveAndARejectedReadDropsTheCopy() {
    var elapsed: Int64 = 0
    let mailbox = EntryShareMailbox(wallClock: { 1_800_000_000_000 }, continuousClock: { elapsed })
    _ = mailbox.offer(link, expectedOrigin: origin)
    elapsed = EntryShareMailbox.maximumAgeMilliseconds - 1
    XCTAssertNotNil(mailbox.take()["url"])
    _ = mailbox.offer(link, expectedOrigin: origin)
    elapsed += EntryShareMailbox.maximumAgeMilliseconds
    XCTAssertNil(mailbox.take()["url"])
    elapsed = 0
    XCTAssertNil(mailbox.take()["url"])
  }

  func testNonSharingActivityRemainsAvailableToExistingHandlers() {
    let activity = NSUserActivity(activityType: "io.palladin.example")
    activity.userInfo = ["state": "fixture"]
    activity.title = "Example"
    XCTAssertFalse(EntryShareActivityPrivacy.intercepts(activity))
    XCTAssertEqual(activity.userInfo?["state"] as? String, "fixture")
    XCTAssertEqual(activity.title, "Example")
  }

  func testMissingBrowsingURLIsStillInterceptedInsteadOfForwarded() {
    let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
    XCTAssertTrue(EntryShareActivityPrivacy.intercepts(activity))
  }

  func testOldSceneDisconnectCannotClearNewerLink() {
    let mailbox = EntryShareMailbox()
    let old = mailbox.offer(link, expectedOrigin: origin)
    let current = mailbox.offer(link, expectedOrigin: origin)
    XCTAssertNil(mailbox.clear(expectedGeneration: old))
    XCTAssertEqual(mailbox.take()["url"] as? String, link)
    XCTAssertEqual(mailbox.clear(expectedGeneration: current), current + 1)
    XCTAssertNil(mailbox.take()["url"])
  }
}
