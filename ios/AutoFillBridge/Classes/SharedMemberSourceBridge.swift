import Foundation

/// One app-owned fence instance is shared with the biometric plugin. Extension
/// readers construct an independent fence and never restore app RAM capability.
final class SharedMemberSourceBridge {
    let source: SharedMemberSourceFence
    let containerURL: URL
    let accessGroup: String

    init(bundle: Bundle = .main) throws {
        guard let group = bundle.object(forInfoDictionaryKey: "PalladinAutoFillAppGroupIdentifier") as? String,
              !group.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw SharedMemberSourceError.unavailable
        }
        containerURL = container
        accessGroup = group
        source = try SharedMemberSourceFence(containerURL: container, accessGroup: group)
    }

    init(source: SharedMemberSourceFence, containerURL: URL, accessGroup: String) {
        self.source = source; self.containerURL = containerURL; self.accessGroup = accessGroup
    }

    static let methods: Set<String> = ["beginSourceSession", "activateSource", "invalidateSource",
                                       "invalidateSession", "sourceSnapshot", "sourceConfiguration", "revokeSource", "revokeSourceSession", "getMemberSourceDirectory", "commitMemberSourceMigration"]

    func handle(_ method: String, arguments: [String: Any]) throws -> Any? {
        switch method {
        case "getMemberSourceDirectory":
            return containerURL.appendingPathComponent("member-source", isDirectory: true).path
        case "sourceConfiguration":
            guard let expectedProfile = arguments["profileBinding"] as? String else { throw SharedMemberSourceError.invalid }
            let expectedClaims = try SharedMemberSourceClaims(arguments: arguments)
            let captured = try source.current()
            return try source.withCurrentSource(captured, requireActive: true) {
                guard captured.profileBinding == expectedProfile, captured.claims == expectedClaims else {
                    throw SharedMemberSourceError.stale
                }
                var configuration = captured.claims.arguments
                configuration["profileBinding"] = captured.profileBinding
                configuration["accountUnlock"] = try JSONSerialization.jsonObject(with: captured.accountUnlock)
                return configuration
            }
        case "commitMemberSourceMigration":
            guard let session = arguments["sessionId"] as? String,
                  let epoch = arguments["sourceEpoch"] as? Int,
                  let profile = arguments["profileBinding"] as? String else { throw SharedMemberSourceError.invalid }
            try source.requireAppSession(session)
            let captured = try source.current()
            guard captured.sessionID == session, captured.epoch == epoch, captured.profileBinding == profile else {
                throw SharedMemberSourceError.stale
            }
            try source.withCurrentSource(captured, requireActive: false, requireQuarantined: true) {
                try commitMemberSourceMigration(in: containerURL)
            }
            return nil
        case "sourceSnapshot":
            guard let snapshot = try source.sourceSnapshot() else { return nil }
            return ["sourceEpoch": snapshot.sourceEpoch, "profileDigest": snapshot.profileDigest]
        case "revokeSource":
            guard let epoch = arguments["sourceEpoch"] as? Int,
                  let digest = arguments["profileDigest"] as? String else { throw SharedMemberSourceError.invalid }
            return try source.revokeSource(sourceEpoch: epoch, profileDigest: digest)
        case "beginSourceSession":
            guard let session = arguments["sessionId"] as? String,
                  let profile = arguments["profileBinding"] as? String,
                  let account = arguments["accountUnlock"] as? [String: Any] else { throw SharedMemberSourceError.invalid }
            return try source.beginSession(sessionID: session, profileBinding: profile,
                claims: SharedMemberSourceClaims(arguments: arguments), accountUnlock: account).epoch
        case "invalidateSession":
            guard let session = arguments["sessionId"] as? String else { throw SharedMemberSourceError.invalid }
            source.invalidateSession(session)
            return nil
        case "activateSource", "invalidateSource", "revokeSourceSession":
            guard let session = arguments["sessionId"] as? String,
                  let epoch = arguments["sourceEpoch"] as? Int else { throw SharedMemberSourceError.invalid }
            try source.requireAppSession(session)
            let captured = try source.current()
            guard captured.sessionID == session, captured.epoch == epoch else { throw SharedMemberSourceError.stale }
            if method == "activateSource" {
                try source.activate(captured)
                return captured.epoch
            }
            // iOS requests intentionally retain their original source epoch.
            // Both routine mutation and explicit hard revoke cancel old request
            // auth/selection; no decrypted runtime can adopt a later generation.
            return try source.invalidate(captured).epoch
        default:
            throw SharedMemberSourceError.invalid
        }
    }
}
