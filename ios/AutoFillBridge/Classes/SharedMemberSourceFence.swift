import Foundation
import CryptoKit
import Security
import Darwin

struct SharedMemberSourceClaims: Codable, Equatable {
    let principalId: String
    let organizationId: String
    let organizationMembershipGeneration: String
    let offlinePolicy: String
    let offlinePolicyVersion: Int

    init(arguments: [String: Any]) throws {
        guard let principal = arguments["principalId"] as? String, !principal.isEmpty, principal.utf8.count <= 128,
              let organization = arguments["organizationId"] as? String, !organization.isEmpty, organization.utf8.count <= 128,
              let membership = arguments["organizationMembershipGeneration"] as? String,
              membership.range(of: #"\A[0-9]{1,20}\z"#, options: .regularExpression) != nil,
              let policy = arguments["offlinePolicy"] as? String, ["disabled", "1h", "4h", "24h"].contains(policy),
              let policyVersion = arguments["offlinePolicyVersion"] as? Int else {
            throw SharedMemberSourceError.invalid
        }
        principalId = principal; organizationId = organization
        organizationMembershipGeneration = membership
        offlinePolicy = policy; offlinePolicyVersion = policyVersion
    }
    var arguments: [String: Any] {
        ["principalId": principalId, "organizationId": organizationId,
         "organizationMembershipGeneration": organizationMembershipGeneration,
         "offlinePolicy": offlinePolicy, "offlinePolicyVersion": offlinePolicyVersion]
    }
}

struct SharedMemberSourceControlSnapshot {
    let sourceEpoch: Int
    let profileDigest: String
}

enum SharedMemberSourceState: String, Codable { case active, quarantined, revoked }
enum SharedMemberSourceError: Error { case invalid, unavailable, stale, keychain(OSStatus), lockFailed }

struct SharedMemberSourceSnapshot: Codable, Equatable {
    let version: Int
    let sessionID: String
    let epoch: Int
    let profileBinding: String
    let claims: SharedMemberSourceClaims
    let accountUnlock: Data
    let state: SharedMemberSourceState

    fileprivate func replacing(epoch: Int? = nil, state: SharedMemberSourceState) -> Self {
        Self(version: version, sessionID: sessionID, epoch: epoch ?? self.epoch,
             profileBinding: profileBinding, claims: claims, accountUnlock: accountUnlock, state: state)
    }
    fileprivate func sameAuthority(_ other: Self) -> Bool {
        version == other.version && sessionID == other.sessionID && epoch == other.epoch &&
        profileBinding == other.profileBinding && claims == other.claims && accountUnlock == other.accountUnlock
    }
}

/// The app durably quarantines before a shared SQLite write. Only its aggregate
/// mutation owner may activate after every commit and authoritative repair.
/// Extensions never activate; their final OS handoff holds this same flock.
final class SharedMemberSourceFence {
    private let directory: URL
    private let readState: () throws -> Data?
    private let writeState: (Data) throws -> Void
    private let localLock = NSRecursiveLock()
    private var registeredSessions = Set<String>()
    private static let maximumStateBytes = 65536

    init(containerURL: URL, readState: @escaping () throws -> Data?, writeState: @escaping (Data) throws -> Void) {
        directory = containerURL; self.readState = readState; self.writeState = writeState
    }

    convenience init(containerURL: URL, accessGroup: String) throws {
        guard !accessGroup.isEmpty else { throw SharedMemberSourceError.invalid }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.palladin.mobile.member-source.v1",
            kSecAttrAccount as String: "authority",
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: false,
        ]
        self.init(containerURL: containerURL, readState: {
            var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(read as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = result as? Data else { throw SharedMemberSourceError.keychain(status) }
            return data
        }, writeState: { data in
            let attributes: [String: Any] = [kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var item = query; attributes.forEach { item[$0.key] = $0.value }
                let added = SecItemAdd(item as CFDictionary, nil)
                guard added == errSecSuccess else { throw SharedMemberSourceError.keychain(added) }
            } else if status != errSecSuccess { throw SharedMemberSourceError.keychain(status) }
        })
    }

    func beginSession(sessionID: String, profileBinding: String, claims: SharedMemberSourceClaims,
                      accountUnlock: [String: Any]) throws -> SharedMemberSourceSnapshot {
        try validateIdentity(sessionID: sessionID, profileBinding: profileBinding)
        let account = try canonicalAccount(accountUnlock, claims: claims)
        return try locked {
            let epoch = try nextEpoch(readLocked()?.epoch ?? 0)
            let value = SharedMemberSourceSnapshot(version: 1, sessionID: sessionID, epoch: epoch,
                profileBinding: profileBinding, claims: claims, accountUnlock: account, state: .quarantined)
            try persist(value)
            registeredSessions = [sessionID]
            return value
        }
    }

    func current() throws -> SharedMemberSourceSnapshot {
        try locked { guard let value = try readLocked() else { throw SharedMemberSourceError.unavailable }; return value }
    }

    func sourceSnapshot() throws -> SharedMemberSourceControlSnapshot? {
        try locked {
            guard let source = try readLocked() else { return nil }
            return SharedMemberSourceControlSnapshot(sourceEpoch: source.epoch, profileDigest: try digest(source))
        }
    }

    @discardableResult
    func revokeSource(sourceEpoch: Int, profileDigest: String) throws -> Int {
        try locked {
            guard let current = try readLocked(), current.epoch == sourceEpoch,
                  try digest(current) == profileDigest else { throw SharedMemberSourceError.stale }
            let replacement = current.replacing(epoch: try nextEpoch(current.epoch), state: .quarantined)
            try persist(replacement)
            registeredSessions.remove(current.sessionID)
            return replacement.epoch
        }
    }

    private func digest(_ value: SharedMemberSourceSnapshot) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    func activate(_ expected: SharedMemberSourceSnapshot) throws {
        try locked {
            try requireAppSession(expected.sessionID)
            let current = try requireCurrent(expected)
            guard current.state == .quarantined else { throw SharedMemberSourceError.stale }
            try persist(current.replacing(state: .active))
        }
    }

    @discardableResult
    func invalidate(_ expected: SharedMemberSourceSnapshot) throws -> SharedMemberSourceSnapshot {
        try locked {
            let current = try requireCurrent(expected)
            guard current.state != .revoked else { throw SharedMemberSourceError.stale }
            let replacement = current.replacing(epoch: try nextEpoch(current.epoch), state: .quarantined)
            try persist(replacement)
            return replacement
        }
    }

    func revoke(_ expected: SharedMemberSourceSnapshot) throws {
        try locked {
            let current = try requireCurrent(expected)
            try persist(current.replacing(epoch: try nextEpoch(current.epoch), state: .revoked))
            registeredSessions.remove(current.sessionID)
        }
    }

    func invalidateSession(_ sessionID: String) {
        localLock.lock(); defer { localLock.unlock() }
        registeredSessions.remove(sessionID)
    }

    func requireAppSession(_ sessionID: String) throws {
        localLock.lock(); defer { localLock.unlock() }
        guard registeredSessions.contains(sessionID) else { throw SharedMemberSourceError.stale }
    }

    func withCurrentSource<T>(_ expected: SharedMemberSourceSnapshot, requireActive: Bool,
                              requireQuarantined: Bool = false, _ operation: () throws -> T) throws -> T {
        try locked {
            let current = try requireCurrent(expected)
            guard current.state != .revoked, !requireActive || current.state == .active,
                  !requireQuarantined || current.state == .quarantined else { throw SharedMemberSourceError.stale }
            return try operation()
        }
    }

    private func requireCurrent(_ expected: SharedMemberSourceSnapshot) throws -> SharedMemberSourceSnapshot {
        guard let current = try readLocked(), current.sameAuthority(expected) else { throw SharedMemberSourceError.stale }
        return current
    }
    private func nextEpoch(_ current: Int) throws -> Int {
        guard current >= 0, current < Int.max else { throw SharedMemberSourceError.invalid }
        return current + 1
    }
    private func readLocked() throws -> SharedMemberSourceSnapshot? {
        guard let data = try readState() else { return nil }
        guard data.count <= Self.maximumStateBytes else { throw SharedMemberSourceError.invalid }
        let value = try JSONDecoder().decode(SharedMemberSourceSnapshot.self, from: data)
        guard value.version == 1, value.epoch > 0 else { throw SharedMemberSourceError.invalid }
        try validateIdentity(sessionID: value.sessionID, profileBinding: value.profileBinding)
        _ = try SharedMemberSourceClaims(arguments: value.claims.arguments)
        guard let account = try JSONSerialization.jsonObject(with: value.accountUnlock) as? [String: Any],
              try canonicalAccount(account, claims: value.claims) == value.accountUnlock else {
            throw SharedMemberSourceError.invalid
        }
        return value
    }
    private func validateIdentity(sessionID: String, profileBinding: String) throws {
        guard !sessionID.isEmpty, sessionID.utf8.count <= 256,
              profileBinding.range(of: #"\A[a-f0-9]{64}\z"#, options: .regularExpression) != nil else {
            throw SharedMemberSourceError.invalid
        }
    }
    private func canonicalAccount(_ account: [String: Any], claims: SharedMemberSourceClaims) throws -> Data {
        let required: Set<String> = ["securityVersion", "minimumSecurityVersion", "profileId", "kdfSalt", "credentialRevision", "privateKeyWrapRevision"]
        guard let accountID = account["accountId"] as? String, accountID == claims.principalId,
              let encrypted = account["encryptedPrivateKey"] as? String, !encrypted.isEmpty,
              let kdf = account["kdf"] as? [String: Any],
              Set(account.keys) == ["accountId", "encryptedPrivateKey", "kdf"],
              required.isSubset(of: Set(kdf.keys)),
              Set(kdf.keys).isSubset(of: required.union(["deviceWrapperMetadata"])),
              kdf["securityVersion"] is Int, kdf["minimumSecurityVersion"] is Int,
              kdf["profileId"] is String, kdf["kdfSalt"] is String,
              kdf["credentialRevision"] is Int, kdf["privateKeyWrapRevision"] is Int,
              kdf["deviceWrapperMetadata"] == nil || kdf["deviceWrapperMetadata"] is String || kdf["deviceWrapperMetadata"] is NSNull
        else { throw SharedMemberSourceError.invalid }
        let encoded = try JSONSerialization.data(withJSONObject: account, options: [.sortedKeys])
        guard encoded.count <= Self.maximumStateBytes / 2 else { throw SharedMemberSourceError.invalid }
        return encoded
    }
    private func persist(_ value: SharedMemberSourceSnapshot) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= Self.maximumStateBytes else { throw SharedMemberSourceError.invalid }
        try writeState(data)
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        localLock.lock(); defer { localLock.unlock() }
        let descriptor = open(directory.appendingPathComponent(".palladin-member-source-v1.lock").path,
                              O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw SharedMemberSourceError.lockFailed }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw SharedMemberSourceError.lockFailed }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
