import CoreSpotlight
import Foundation

enum EntryShareActivityPrivacy {
  static func intercepts(_ activity: NSUserActivity) -> Bool {
    activity.activityType == NSUserActivityTypeBrowsingWeb ||
      activity.webpageURL.map(EntryShareLinkPolicy.intercepts) == true
  }

  static func scrub(_ activity: NSUserActivity) {
    activity.isEligibleForHandoff = false
    activity.isEligibleForSearch = false
    activity.isEligibleForPublicIndexing = false
    #if os(iOS)
    activity.isEligibleForPrediction = false
    #endif
    activity.webpageURL = nil
    activity.referrerURL = nil
    activity.userInfo = nil
    activity.requiredUserInfoKeys = []
    activity.title = nil
    activity.keywords = []
    activity.targetContentIdentifier = nil
    activity.persistentIdentifier = nil
    activity.contentAttributeSet = nil
    activity.invalidate()
  }
}
