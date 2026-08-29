import AuthenticationServices
import CryptoKit
import Darwin
import Foundation
import LocalAuthentication
import Security

struct AutoFillCredentialRecord: Equatable {
    let id: String
    let organizationId: String
    let vaultId: String
    let revision: String
    let keyVersion: Int
    let label: String
    let username: String
    let password: String
    let domains: [String]

    func matches(serviceIdentifiers: [ASCredentialServiceIdentifier]) -> Bool {
        let requested = Set(serviceIdentifiers.compactMap { Self.normalizeDomain($0.identifier) })
        return domains.contains { requested.contains($0) }
    }

    static func normalizeDomain(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else { return nil }
        if !value.contains("://") { value = "https://\(value)" }
        guard let components = URLComponents(string: value),
              components.scheme == "https" || components.scheme == "http",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              var host = components.host?.lowercased(),
              host.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
        while host.hasSuffix(".") { host.removeLast() }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.contains("."), !host.contains(".."), labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 &&
            label.first != "-" && label.last != "-" &&
            label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }) else { return nil }
        return host
    }
}

struct AutoFillCredentialLease {
    let record: AutoFillCredentialRecord
    let notAfter: Date
    let generation: Int
    let cacheId: String
    let maximumObservedWallTime: Date
}

struct AutoFillCacheReadResult {
    let credentials: [AutoFillCredentialLease]
    let generation: Int
    let cacheId: String
}

struct AutoFillCacheReplacement {
    let records: [AutoFillCredentialRecord]
    let generation: Int
    let cacheId: String
}

struct AutoFillUnwrapOperation {
    let generation: Int
    let cacheId: String
    fileprivate let envelope: AutoFillCacheEnvelope
}

private struct AutoFillEntryAuthority {
    let revision: String
    let keyVersion: Int
}

private struct AutoFillVaultAuthority {
    let notAfter: Date
    let entries: [String: AutoFillEntryAuthority]
}

struct AutoFillCacheManifest {
    let principalId: String
    let organizationId: String
    fileprivate let vaults: [String: AutoFillVaultAuthority]
}

struct AutoFillCachePayload {
    let manifest: AutoFillCacheManifest
    let records: [AutoFillCredentialRecord]
    fileprivate let canonicalObject: [String: Any]
}

private struct AutoFillCacheEnvelope {
    let version: Int
    let generation: Int
    let cacheId: String
    let sealedPayload: Data
}

enum AutoFillFenceState: String {
    case active
    case revoked
    case quarantined
}

struct AutoFillFence: Equatable {
    let generation: Int
    let state: AutoFillFenceState
    let cacheId: String?
}

enum AutoFillCacheError: Error {
    case invalidAppGroup
    case invalidRecords
    case keychain(OSStatus)
    case cacheUnavailable
    case unsupportedVersion
    case staleSession
    case expiredLease
    case clockRollback
}

final class AutoFillFileLockLease {
    private let lock = NSLock()
    private var descriptor: Int32?

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        guard let descriptor else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        self.descriptor = nil
    }

    deinit {
        release()
    }
}

enum AutoFillAsyncCallbackAction: Equatable {
    case finish
    case compensate
}

enum AutoFillAsyncTimeoutAction: Equatable {
    case returnTimeout
    case awaitCompletion
}

final class AutoFillAsyncMutationState {
    private enum State {
        case pending
        case timedOut
        case compensating
        case completed
    }

    private let lock = NSLock()
    private var error: Error?
    private var state = State.pending

    func callbackAction(
        succeeded: Bool,
        error: Error?,
        expectedArtifactIsActive: Bool
    ) -> AutoFillAsyncCallbackAction {
        lock.lock()
        defer { lock.unlock() }
        if succeeded && (state == .timedOut || !expectedArtifactIsActive) {
            state = .compensating
            return .compensate
        }
        self.error = succeeded ? nil : (error ?? AutoFillCacheError.cacheUnavailable)
        state = .completed
        return .finish
    }

    func timeoutAction() -> AutoFillAsyncTimeoutAction {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .pending:
            state = .timedOut
            return .returnTimeout
        case .timedOut, .compensating:
            return .returnTimeout
        case .completed:
            return .awaitCompletion
        }
    }

    func timeoutAction(
        releasingSerializationResources release: () -> Void
    ) -> AutoFillAsyncTimeoutAction {
        let action = timeoutAction()
        if action == .returnTimeout {
            release()
        }
        return action
    }

    func clearCallbackCompleted(succeeded: Bool, error: Error?) {
        lock.lock()
        self.error = succeeded ? nil : (error ?? AutoFillCacheError.cacheUnavailable)
        state = .completed
        lock.unlock()
    }

    func completeCompensation() {
        lock.lock()
        error = AutoFillCacheError.staleSession
        state = .completed
        lock.unlock()
    }

    func recordedError() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}

enum AutoFillFenceRules {
    static func isActive(
        counter: Int?,
        fence: AutoFillFence?,
        generation: Int,
        cacheId: String
    ) -> Bool {
        counter == generation &&
        fence == AutoFillFence(generation: generation, state: .active, cacheId: cacheId)
    }

    static func mayDeleteArtifacts(
        artifactGeneration: Int,
        cleanupGeneration: Int,
        currentCounter: Int?
    ) -> Bool {
        artifactGeneration < cleanupGeneration &&
        (currentCounter.map { artifactGeneration < $0 } ?? true)
    }

    static func mayClearSession(
        counter: Int?,
        fence: AutoFillFence?,
        sessionToken: Int
    ) -> Bool {
        counter == sessionToken &&
        fence?.generation == sessionToken &&
        fence?.state == .active
    }

    static func quarantineAfterAuthorityFailure(
        counter: Int?,
        fence: AutoFillFence?
    ) -> AutoFillFence? {
        guard let counter,
              let fence,
              counter == fence.generation,
              fence.state == .active else { return nil }
        return AutoFillFence(
            generation: counter,
            state: .quarantined,
            cacheId: nil
        )
    }
}

enum AutoFillIdentityPublicationGuard {
    static func shouldPublish(
        expectedGeneration: Int,
        expectedCacheId: String,
        currentCounter: Int?,
        currentFence: AutoFillFence?
    ) -> Bool {
        AutoFillFenceRules.isActive(
            counter: currentCounter,
            fence: currentFence,
            generation: expectedGeneration,
            cacheId: expectedCacheId
        )
    }
}

enum AutoFillIdentityCompensationGuard {
    static func shouldClearLateReplacement(
        expectedGeneration: Int,
        expectedCacheId: String,
        currentCounter: Int?,
        currentFence: AutoFillFence?
    ) -> Bool {
        AutoFillIdentityPublicationGuard.shouldPublish(
            expectedGeneration: expectedGeneration,
            expectedCacheId: expectedCacheId,
            currentCounter: currentCounter,
            currentFence: currentFence
        )
    }
}

enum AutoFillWallTimeGuard {
    static let rollbackTolerance: TimeInterval = 5 * 60

    static func maximumObservedWallTime(now: Date, previous: Date) throws -> Date {
        guard now.timeIntervalSince(previous) >= -rollbackTolerance else {
            throw AutoFillCacheError.clockRollback
        }
        return max(now, previous)
    }
}

final class AutoFillMonotonicWallTimeGuard {
    private let lock = NSLock()
    private var baseline: (wallTime: Date, uptime: TimeInterval)?

    func validate(wallTime: Date, uptime: TimeInterval) throws {
        lock.lock()
        defer { lock.unlock() }
        guard uptime.isFinite, uptime >= 0 else {
            throw AutoFillCacheError.clockRollback
        }
        guard let baseline else {
            self.baseline = (wallTime, uptime)
            return
        }
        let elapsed = uptime - baseline.uptime
        guard elapsed >= 0 else { throw AutoFillCacheError.clockRollback }
        let minimumWallTime = baseline.wallTime.addingTimeInterval(
            elapsed - AutoFillWallTimeGuard.rollbackTolerance
        )
        guard wallTime >= minimumWallTime else {
            throw AutoFillCacheError.clockRollback
        }
    }
}

enum AutoFillWallTimeCoordinator {
    static func maximumObservedWallTime(
        now: Date,
        globalPrevious: Date,
        generationPrevious: Date?
    ) throws -> Date {
        let previous = max(globalPrevious, generationPrevious ?? globalPrevious)
        return try AutoFillWallTimeGuard.maximumObservedWallTime(
            now: now,
            previous: previous
        )
    }
}

enum AutoFillWallTimeAuthorityRules {
    static func validatePresence(
        integrityKeyExists: Bool,
        globalStateExists: Bool,
        allowInitialization: Bool
    ) throws {
        guard integrityKeyExists == globalStateExists,
              integrityKeyExists || allowInitialization else {
            throw AutoFillCacheError.cacheUnavailable
        }
    }
}

enum AutoFillWallTimeStateCodec {
    static func seal(
        maximumObserved: Date,
        generation: Int,
        cacheId: String,
        keyBytes: Data
    ) throws -> Data {
        let milliseconds = Int64(maximumObserved.timeIntervalSince1970 * 1_000)
        var plaintext = Data("\(generation):\(cacheId):\(milliseconds)".utf8)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: keyBytes),
            authenticating: aad(generation: generation, cacheId: cacheId)
        )
        guard let combined = sealed.combined else {
            throw AutoFillCacheError.cacheUnavailable
        }
        return combined
    }

    static func open(
        _ combined: Data,
        generation: Int,
        cacheId: String,
        keyBytes: Data
    ) throws -> Date {
        let sealed = try AES.GCM.SealedBox(combined: combined)
        var plaintext = try AES.GCM.open(
            sealed,
            using: SymmetricKey(data: keyBytes),
            authenticating: aad(generation: generation, cacheId: cacheId)
        )
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        guard let value = String(data: plaintext, encoding: .utf8) else {
            throw AutoFillCacheError.cacheUnavailable
        }
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == Substring(String(generation)),
              components[1] == Substring(cacheId),
              let milliseconds = Int64(components[2]) else {
            throw AutoFillCacheError.cacheUnavailable
        }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    private static func aad(generation: Int, cacheId: String) -> Data {
        Data("palladin-autofill-wall-time-v2:\(generation):\(cacheId)".utf8)
    }
}

enum AutoFillCredentialUseGuard {
    static func validate(
        _ credential: AutoFillCredentialLease,
        serviceIdentifiers: [ASCredentialServiceIdentifier],
        now: Date,
        currentCounter: Int?,
        currentFence: AutoFillFence?
    ) throws {
        _ = try AutoFillWallTimeGuard.maximumObservedWallTime(
            now: now,
            previous: credential.maximumObservedWallTime
        )
        guard credential.notAfter > now,
              credential.record.matches(serviceIdentifiers: serviceIdentifiers),
              AutoFillFenceRules.isActive(
                counter: currentCounter,
                fence: currentFence,
                generation: credential.generation,
                cacheId: credential.cacheId
              ) else {
            throw AutoFillCacheError.expiredLease
        }
    }
}

enum AutoFillPayloadValidator {
    static let cacheVersion = 2
    static let maximumRecords = 2_000
    static let maximumDomainsPerRecord = 16
    private static let futureClockTolerance: TimeInterval = 5 * 60
    private static let decimal = try! NSRegularExpression(pattern: "^(?:0|[1-9][0-9]*)$")

    static func validate(_ rawPayload: [String: Any], now: Date = Date()) throws -> AutoFillCachePayload {
        guard hasExactKeys(rawPayload, ["version", "manifest", "records"]),
              integer(rawPayload["version"]) == cacheVersion,
              let rawManifest = rawPayload["manifest"] as? [String: Any],
              let rawRecords = rawPayload["records"] as? [Any],
              !rawRecords.isEmpty,
              rawRecords.count <= maximumRecords else {
            if integer(rawPayload["version"]) != nil {
                throw AutoFillCacheError.unsupportedVersion
            }
            throw AutoFillCacheError.invalidRecords
        }

        let manifestResult = try validateManifest(rawManifest, now: now)
        var records: [AutoFillCredentialRecord] = []
        var canonicalRecords: [[String: Any]] = []
        var seen = Set<String>()

        for rawRecordValue in rawRecords {
            guard let rawRecord = rawRecordValue as? [String: Any],
                  hasExactKeys(rawRecord, [
                    "id", "organizationId", "vaultId", "revision", "keyVersion",
                    "label", "username", "password", "domains",
                  ]),
                  let id = requiredString(rawRecord["id"]),
                  let organizationId = requiredString(rawRecord["organizationId"]),
                  let vaultId = requiredString(rawRecord["vaultId"]),
                  let revision = requiredString(rawRecord["revision"]),
                  isDecimal(revision),
                  let keyVersion = positiveInteger(rawRecord["keyVersion"]),
                  let label = requiredString(rawRecord["label"]),
                  let username = rawRecord["username"] as? String,
                  let password = requiredString(rawRecord["password"]),
                  let rawDomains = rawRecord["domains"] as? [Any],
                  !rawDomains.isEmpty,
                  rawDomains.count <= maximumDomainsPerRecord,
                  organizationId == manifestResult.manifest.organizationId,
                  let vaultAuthority = manifestResult.manifest.vaults[vaultId],
                  let entryAuthority = vaultAuthority.entries[id],
                  entryAuthority.revision == revision,
                  entryAuthority.keyVersion == keyVersion,
                  seen.insert("\(vaultId):\(id)").inserted else {
                throw AutoFillCacheError.invalidRecords
            }
            let domains = Array(Set(try rawDomains.map { value -> String in
                guard let rawDomain = value as? String,
                      let domain = AutoFillCredentialRecord.normalizeDomain(rawDomain) else {
                    throw AutoFillCacheError.invalidRecords
                }
                return domain
            })).sorted()
            guard !domains.isEmpty else { throw AutoFillCacheError.invalidRecords }

            let record = AutoFillCredentialRecord(
                id: id,
                organizationId: organizationId,
                vaultId: vaultId,
                revision: revision,
                keyVersion: keyVersion,
                label: label,
                username: username,
                password: password,
                domains: domains
            )
            records.append(record)
            canonicalRecords.append([
                "id": id,
                "organizationId": organizationId,
                "vaultId": vaultId,
                "revision": revision,
                "keyVersion": keyVersion,
                "label": label,
                "username": username,
                "password": password,
                "domains": domains,
            ])
        }

        let expected = Set(manifestResult.manifest.vaults.flatMap { vaultId, vault in
            vault.entries.keys.map { "\(vaultId):\($0)" }
        })
        guard seen == expected else { throw AutoFillCacheError.invalidRecords }

        return AutoFillCachePayload(
            manifest: manifestResult.manifest,
            records: records,
            canonicalObject: [
                "version": cacheVersion,
                "manifest": manifestResult.canonicalObject,
                "records": canonicalRecords,
            ]
        )
    }

    private static func validateManifest(
        _ raw: [String: Any],
        now: Date
    ) throws -> (manifest: AutoFillCacheManifest, canonicalObject: [String: Any]) {
        guard hasExactKeys(raw, [
            "principalId", "organizationId", "organizationMembershipGeneration",
            "offlinePolicy", "offlinePolicyVersion", "vaults",
        ]),
        let principalId = requiredString(raw["principalId"]),
        let organizationId = requiredString(raw["organizationId"]),
        let membershipGeneration = requiredString(raw["organizationMembershipGeneration"]),
        isDecimal(membershipGeneration),
        let offlinePolicy = raw["offlinePolicy"] as? String,
        let policyDuration = ["1h": 3_600.0, "4h": 14_400.0, "24h": 86_400.0][offlinePolicy],
        let offlinePolicyVersion = positiveInteger(raw["offlinePolicyVersion"]),
        let rawVaults = raw["vaults"] as? [Any],
        !rawVaults.isEmpty else {
            throw AutoFillCacheError.invalidRecords
        }

        var vaults: [String: AutoFillVaultAuthority] = [:]
        var canonicalVaults: [[String: Any]] = []
        for rawVaultValue in rawVaults {
            guard let rawVault = rawVaultValue as? [String: Any],
                  hasExactKeys(rawVault, [
                    "vaultId", "contextVersion", "memberId", "memberKeyGeneration",
                    "vaultKeyVersion", "memberRecipientKeyVersion",
                    "memberRecipientKeyFingerprint", "issuedAt", "notAfter", "entries",
                  ]),
                  let vaultId = requiredString(rawVault["vaultId"]),
                  integer(rawVault["contextVersion"]) == 1,
                  let memberId = requiredString(rawVault["memberId"]),
                  memberId == principalId,
                  let memberKeyGeneration = positiveInteger(rawVault["memberKeyGeneration"]),
                  let vaultKeyVersion = positiveInteger(rawVault["vaultKeyVersion"]),
                  let memberRecipientKeyVersion = positiveInteger(rawVault["memberRecipientKeyVersion"]),
                  let memberRecipientKeyFingerprint = requiredString(rawVault["memberRecipientKeyFingerprint"]),
                  let issuedAtString = rawVault["issuedAt"] as? String,
                  let issuedAt = instant(issuedAtString),
                  let notAfterString = rawVault["notAfter"] as? String,
                  let notAfter = instant(notAfterString),
                  issuedAt <= now.addingTimeInterval(futureClockTolerance),
                  abs(notAfter.timeIntervalSince(issuedAt) - policyDuration) < 0.001,
                  notAfter > now,
                  let rawEntries = rawVault["entries"] as? [Any],
                  !rawEntries.isEmpty,
                  vaults[vaultId] == nil else {
                throw AutoFillCacheError.invalidRecords
            }

            var entries: [String: AutoFillEntryAuthority] = [:]
            var canonicalEntries: [[String: Any]] = []
            for rawEntryValue in rawEntries {
                guard let rawEntry = rawEntryValue as? [String: Any],
                      hasExactKeys(rawEntry, ["entryId", "revision", "keyVersion"]),
                      let entryId = requiredString(rawEntry["entryId"]),
                      let revision = requiredString(rawEntry["revision"]),
                      isDecimal(revision),
                      let keyVersion = positiveInteger(rawEntry["keyVersion"]),
                      entries[entryId] == nil else {
                    throw AutoFillCacheError.invalidRecords
                }
                entries[entryId] = AutoFillEntryAuthority(revision: revision, keyVersion: keyVersion)
                canonicalEntries.append([
                    "entryId": entryId,
                    "revision": revision,
                    "keyVersion": keyVersion,
                ])
            }
            vaults[vaultId] = AutoFillVaultAuthority(notAfter: notAfter, entries: entries)
            canonicalVaults.append([
                "vaultId": vaultId,
                "contextVersion": 1,
                "memberId": memberId,
                "memberKeyGeneration": memberKeyGeneration,
                "vaultKeyVersion": vaultKeyVersion,
                "memberRecipientKeyVersion": memberRecipientKeyVersion,
                "memberRecipientKeyFingerprint": memberRecipientKeyFingerprint,
                "issuedAt": issuedAtString,
                "notAfter": notAfterString,
                "entries": canonicalEntries,
            ])
        }

        return (
            AutoFillCacheManifest(
                principalId: principalId,
                organizationId: organizationId,
                vaults: vaults
            ),
            [
                "principalId": principalId,
                "organizationId": organizationId,
                "organizationMembershipGeneration": membershipGeneration,
                "offlinePolicy": offlinePolicy,
                "offlinePolicyVersion": offlinePolicyVersion,
                "vaults": canonicalVaults,
            ]
        )
    }

    private static func requiredString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func positiveInteger(_ value: Any?) -> Int? {
        guard let result = integer(value), result > 0 else { return nil }
        return result
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= Double(Int.min),
              number.doubleValue <= Double(Int.max) else { return nil }
        return number.intValue
    }

    private static func hasExactKeys(_ value: [String: Any], _ expected: Set<String>) -> Bool {
        Set(value.keys) == expected
    }

    private static func isDecimal(_ value: String) -> Bool {
        decimal.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) != nil
    }

    private static func instant(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

final class AutoFillCacheStore {
    private static let maximumCacheBytes = 16 * 1024 * 1024
    private static let cacheFilePrefix = "palladin_autofill_cache_v2_"
    private static let legacyCacheFileName = "palladin_autofill_cache_v1"
    private static let keychainService = "io.palladin.mobile.autofill.cache"
    private static let fenceAccount = "fence-v2"
    private static let generationCounterAccount = "generation-counter-v2"
    private static let cacheKeyPrefix = "cache-key-v2-"
    private static let wallTimePrefix = "wall-time-v2-"
    private static let wallIntegrityKeyAccount = "wall-integrity-key-v2"
    private static let globalWallTimeAccount = "wall-time-high-water-v2"
    private static let globalWallTimeGeneration = 0
    private static let globalWallTimeCacheId = "global"
    private static let legacyKeyAccount = "cache-key-v1"
    private static let stateLockFileName = "palladin_autofill_state_v2.lock"
    private static let identityLockFileName = "palladin_autofill_identities_v2.lock"
    private static let mutationLock = NSLock()
    private static let identityQueue = DispatchQueue(label: "io.palladin.mobile.autofill.identities")
    private static let monotonicWallTimeGuard = AutoFillMonotonicWallTimeGuard()

    private let keychainAccessGroupIdentifier: String
    private let containerURL: URL

    init(bundle: Bundle = .main) throws {
        guard let configuredIdentifier = bundle.object(
            forInfoDictionaryKey: "PalladinAutoFillAppGroupIdentifier"
        ) as? String,
        !configuredIdentifier.isEmpty else {
            throw AutoFillCacheError.invalidAppGroup
        }
        keychainAccessGroupIdentifier = configuredIdentifier
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: configuredIdentifier
        ) else {
            throw AutoFillCacheError.invalidAppGroup
        }
        containerURL = container
    }

    func beginSession(
        now: Date = Date(),
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) throws -> Int {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        return try withStateProcessLock {
            do {
                try validateProcessWallTimeLocked(now: now, systemUptime: systemUptime)
                _ = try readOrInitializeGlobalWallTimeLocked(
                    now: now,
                    allowInitialization: try !hasExistingV2AuthorityLocked()
                )
            } catch {
                try? quarantineCurrentFenceLocked()
                throw error
            }
            let generation = try nextGenerationLocked(now: now)
            try writeCounterLocked(generation)
            try writeFenceLocked(AutoFillFence(generation: generation, state: .active, cacheId: nil))
            try? purgeLegacyLocked()
            try? cleanupArtifactsLocked(olderThan: generation)
            return generation
        }
    }

    func replace(
        payload rawPayload: [String: Any],
        sessionToken: Int,
        now: Date = Date(),
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) throws -> AutoFillCacheReplacement {
        let payload = try AutoFillPayloadValidator.validate(rawPayload, now: now)
        var plaintext = try JSONSerialization.data(
            withJSONObject: payload.canonicalObject,
            options: [.sortedKeys]
        )
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        var keyBytes = try secureRandomBytes(count: 32)
        defer { keyBytes.resetBytes(in: 0..<keyBytes.count) }
        let cacheId = UUID().uuidString.lowercased()

        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        return try withStateProcessLock {
            try requireActiveLocked(generation: sessionToken, cacheId: nil)
            try validateProcessWallTimeLocked(now: now, systemUptime: systemUptime)
            let wallAuthority: (integrityKey: Data, maximumObserved: Date)
            do {
                wallAuthority = try readOrInitializeGlobalWallTimeLocked(
                    now: now,
                    allowInitialization: false
                )
            } catch {
                try? quarantineCurrentFenceLocked()
                throw error
            }
            try writeFenceLocked(AutoFillFence(
                generation: sessionToken,
                state: .quarantined,
                cacheId: nil
            ))

            do {
                let sealed = try AES.GCM.seal(
                    plaintext,
                    using: SymmetricKey(data: keyBytes),
                    authenticating: cacheAAD(generation: sessionToken, cacheId: cacheId)
                )
                guard let combined = sealed.combined else { throw AutoFillCacheError.invalidRecords }
                try replaceOpeningKey(keyBytes, generation: sessionToken)
                try writeWallTimeState(
                    maximumObserved: wallAuthority.maximumObserved,
                    generation: sessionToken,
                    cacheId: cacheId,
                    integrityKeyBytes: wallAuthority.integrityKey
                )
                try writeEnvelope(AutoFillCacheEnvelope(
                    version: AutoFillPayloadValidator.cacheVersion,
                    generation: sessionToken,
                    cacheId: cacheId,
                    sealedPayload: combined
                ))
                try writeFenceLocked(AutoFillFence(
                    generation: sessionToken,
                    state: .active,
                    cacheId: cacheId
                ))
            } catch {
                try? deleteArtifactsLocked(generation: sessionToken)
                throw error
            }

            return AutoFillCacheReplacement(
                records: payload.records,
                generation: sessionToken,
                cacheId: cacheId
            )
        }
    }

    func createUnwrapOperation() throws -> AutoFillUnwrapOperation {
        return try withStateProcessLock {
            let authority = try readActiveAuthorityLocked()
            guard let cacheId = authority.fence.cacheId else {
                throw AutoFillCacheError.cacheUnavailable
            }
            let envelope = try readEnvelope(generation: authority.fence.generation)
            guard envelope.version == AutoFillPayloadValidator.cacheVersion,
                  envelope.generation == authority.fence.generation,
                  envelope.cacheId == cacheId else {
                throw AutoFillCacheError.unsupportedVersion
            }
            return AutoFillUnwrapOperation(
                generation: envelope.generation,
                cacheId: envelope.cacheId,
                envelope: envelope
            )
        }
    }

    func read(
        operation: AutoFillUnwrapOperation,
        authenticationPrompt: String,
        now suppliedNow: Date? = nil,
        systemUptime suppliedSystemUptime: TimeInterval? = nil
    ) throws -> AutoFillCacheReadResult {
        let preAuthenticationNow = suppliedNow ?? Date()
        let preAuthenticationUptime = suppliedSystemUptime ?? ProcessInfo.processInfo.systemUptime
        try withStateProcessLock {
            try requireActiveLocked(
                generation: operation.generation,
                cacheId: operation.cacheId
            )
            try validateProcessWallTimeLocked(
                now: preAuthenticationNow,
                systemUptime: preAuthenticationUptime
            )
        }
        var keyBytes = try readOpeningKey(
            authenticationPrompt: authenticationPrompt,
            generation: operation.generation
        )
        defer { keyBytes.resetBytes(in: 0..<keyBytes.count) }

        let verifiedNow = suppliedNow ?? Date()
        let verifiedSystemUptime = suppliedSystemUptime ?? ProcessInfo.processInfo.systemUptime

        let maximumObservedWallTime = try withStateProcessLock {
            try requireActiveLocked(
                generation: operation.generation,
                cacheId: operation.cacheId
            )
            try validateProcessWallTimeLocked(
                now: verifiedNow,
                systemUptime: verifiedSystemUptime
            )
            do {
                let integrityKey = try readWallIntegrityKeyLocked()
                let globalPrevious = try readGlobalWallTimeState(
                    integrityKeyBytes: integrityKey
                )
                let generationPrevious = try readWallTimeState(
                    generation: operation.generation,
                    cacheId: operation.cacheId,
                    integrityKeyBytes: integrityKey
                )
                let maximum = try AutoFillWallTimeCoordinator.maximumObservedWallTime(
                    now: verifiedNow,
                    globalPrevious: globalPrevious,
                    generationPrevious: generationPrevious
                )
                if maximum > globalPrevious {
                    try writeGlobalWallTimeState(
                        maximumObserved: maximum,
                        integrityKeyBytes: integrityKey
                    )
                }
                if maximum > generationPrevious {
                    try writeWallTimeState(
                        maximumObserved: maximum,
                        generation: operation.generation,
                        cacheId: operation.cacheId,
                        integrityKeyBytes: integrityKey
                    )
                }
                return maximum
            } catch {
                try? quarantineCurrentFenceLocked()
                throw error
            }
        }

        let sealed = try AES.GCM.SealedBox(combined: operation.envelope.sealedPayload)
        var plaintext = try AES.GCM.open(
            sealed,
            using: SymmetricKey(data: keyBytes),
            authenticating: cacheAAD(
                generation: operation.generation,
                cacheId: operation.cacheId
            )
        )
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        guard plaintext.count <= Self.maximumCacheBytes,
              let rawPayload = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
            throw AutoFillCacheError.invalidRecords
        }
        let payload = try AutoFillPayloadValidator.validate(rawPayload, now: verifiedNow)
        try requireActive(generation: operation.generation, cacheId: operation.cacheId)

        return AutoFillCacheReadResult(
            credentials: payload.records.compactMap { record in
                guard let notAfter = payload.manifest.vaults[record.vaultId]?.notAfter else {
                    return nil
                }
                return AutoFillCredentialLease(
                    record: record,
                    notAfter: notAfter,
                    generation: operation.generation,
                    cacheId: operation.cacheId,
                    maximumObservedWallTime: maximumObservedWallTime
                )
            },
            generation: operation.generation,
            cacheId: operation.cacheId
        )
    }

    func revalidate(
        _ credential: AutoFillCredentialLease,
        serviceIdentifiers: [ASCredentialServiceIdentifier],
        now: Date = Date(),
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) throws {
        try withStateProcessLock {
            try revalidateCredentialLocked(
                credential,
                serviceIdentifiers: serviceIdentifiers,
                now: now,
                systemUptime: systemUptime
            )
        }
    }

    func withRevalidatedCredential<T>(
        _ credential: AutoFillCredentialLease,
        serviceIdentifiers: [ASCredentialServiceIdentifier],
        now: Date = Date(),
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        use: () throws -> T
    ) throws -> T {
        try withStateProcessLock {
            try revalidateCredentialLocked(
                credential,
                serviceIdentifiers: serviceIdentifiers,
                now: now,
                systemUptime: systemUptime
            )
            return try use()
        }
    }

    func clear(sessionToken: Int) throws {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        try withStateProcessLock {
            let counter = try readCounterLocked()
            let fence = try readFenceLocked()
            guard AutoFillFenceRules.mayClearSession(
                counter: counter,
                fence: fence,
                sessionToken: sessionToken
            ) else {
                throw AutoFillCacheError.staleSession
            }
            try writeFenceLocked(AutoFillFence(
                generation: sessionToken,
                state: .quarantined,
                cacheId: nil
            ))
            do {
                try deleteArtifactsLocked(generation: sessionToken)
                guard try readCounterLocked() == sessionToken else { return }
                try writeFenceLocked(AutoFillFence(
                    generation: sessionToken,
                    state: .active,
                    cacheId: nil
                ))
            } catch {
                throw error
            }
        }
    }

    func revokeAccess(now: Date = Date()) throws -> Int {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        return try withStateProcessLock {
            let generation = try nextGenerationLocked(now: now)
            try writeCounterLocked(generation)
            try writeFenceLocked(AutoFillFence(
                generation: generation,
                state: .revoked,
                cacheId: nil
            ))
            return generation
        }
    }

    func cleanupRevoked(generation: Int) throws {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        try withStateProcessLock {
            let counter = try readCounterLocked()
            let fence = try readFenceLocked()
            guard counter == generation,
                  fence == AutoFillFence(generation: generation, state: .revoked, cacheId: nil) else {
                return
            }
            try cleanupArtifactsLocked(olderThan: generation)
            try purgeLegacyLocked()
        }
    }

    func quarantine(generation: Int, cacheId: String) throws {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        try withStateProcessLock {
            guard AutoFillFenceRules.isActive(
                counter: try? readCounterLocked(),
                fence: try? readFenceLocked(),
                generation: generation,
                cacheId: cacheId
            ) else { return }
            try writeFenceLocked(AutoFillFence(
                generation: generation,
                state: .quarantined,
                cacheId: nil
            ))
        }
    }

    func isActive(generation: Int, cacheId: String) -> Bool {
        (try? withStateProcessLock {
            AutoFillIdentityPublicationGuard.shouldPublish(
                expectedGeneration: generation,
                expectedCacheId: cacheId,
                currentCounter: try? readCounterLocked(),
                currentFence: try? readFenceLocked()
            )
        }) ?? false
    }

    private func shouldClearLateIdentityReplacement(
        generation: Int,
        cacheId: String
    ) -> Bool {
        (try? withStateProcessLock {
            AutoFillIdentityCompensationGuard.shouldClearLateReplacement(
                expectedGeneration: generation,
                expectedCacheId: cacheId,
                currentCounter: try? readCounterLocked(),
                currentFence: try? readFenceLocked()
            )
        }) ?? false
    }

    func hasActiveCache() -> Bool {
        (try? withStateProcessLock {
            guard let counter = try? readCounterLocked(),
                  let fence = try? readFenceLocked(),
                  fence.generation == counter,
                  fence.state == .active else { return false }
            return fence.cacheId != nil
        }) ?? false
    }

    static func replaceIdentities(
        for replacement: AutoFillCacheReplacement,
        store: AutoFillCacheStore,
        completion: @escaping (Error?) -> Void
    ) {
        identityQueue.async {
            do {
                let lease = try store.acquireProcessLock(fileName: Self.identityLockFileName)
                guard store.isActive(
                    generation: replacement.generation,
                    cacheId: replacement.cacheId
                ) else {
                    lease.release()
                    completion(AutoFillCacheError.staleSession)
                    return
                }
                let identities = replacement.records.flatMap { record in
                    record.domains.map { domain in
                        ASPasswordCredentialIdentity(
                            serviceIdentifier: ASCredentialServiceIdentifier(
                                identifier: domain,
                                type: .domain
                            ),
                            user: record.username,
                            recordIdentifier: record.id
                        )
                    }
                }
                let semaphore = DispatchSemaphore(value: 0)
                let mutationState = AutoFillAsyncMutationState()
                ASCredentialIdentityStore.shared.replaceCredentialIdentities(with: identities) {
                    success, error in
                    let action = mutationState.callbackAction(
                        succeeded: success,
                        error: error,
                        expectedArtifactIsActive: store.isActive(
                            generation: replacement.generation,
                            cacheId: replacement.cacheId
                        )
                    )
                    guard action == .compensate else {
                        lease.release()
                        semaphore.signal()
                        return
                    }
                    lease.release()
                    let compensationLease: AutoFillFileLockLease
                    do {
                        compensationLease = try store.acquireProcessLock(
                            fileName: Self.identityLockFileName
                        )
                    } catch {
                        mutationState.completeCompensation()
                        semaphore.signal()
                        return
                    }
                    guard store.shouldClearLateIdentityReplacement(
                        generation: replacement.generation,
                        cacheId: replacement.cacheId
                    ) else {
                        mutationState.completeCompensation()
                        compensationLease.release()
                        semaphore.signal()
                        return
                    }
                    ASCredentialIdentityStore.shared.removeAllCredentialIdentities {
                        _, _ in
                        mutationState.completeCompensation()
                        compensationLease.release()
                        semaphore.signal()
                    }
                }
                if semaphore.wait(timeout: .now() + 10) != .success {
                    switch mutationState.timeoutAction(
                        releasingSerializationResources: { lease.release() }
                    ) {
                    case .returnTimeout:
                        completion(AutoFillCacheError.cacheUnavailable)
                        return
                    case .awaitCompletion:
                        semaphore.wait()
                    }
                }
                completion(mutationState.recordedError())
            } catch {
                completion(error)
            }
        }
    }

    static func clearIdentities(
        store: AutoFillCacheStore,
        onlyIf predicate: @escaping () -> Bool = { true },
        completion: @escaping (Error?) -> Void
    ) {
        identityQueue.async {
            do {
                let lease = try store.acquireProcessLock(fileName: Self.identityLockFileName)
                guard predicate() else {
                    lease.release()
                    completion(nil)
                    return
                }
                let semaphore = DispatchSemaphore(value: 0)
                let mutationState = AutoFillAsyncMutationState()
                ASCredentialIdentityStore.shared.removeAllCredentialIdentities { success, error in
                    mutationState.clearCallbackCompleted(succeeded: success, error: error)
                    lease.release()
                    semaphore.signal()
                }
                if semaphore.wait(timeout: .now() + 10) != .success {
                    switch mutationState.timeoutAction(
                        releasingSerializationResources: { lease.release() }
                    ) {
                    case .returnTimeout:
                        completion(AutoFillCacheError.cacheUnavailable)
                        return
                    case .awaitCompletion:
                        semaphore.wait()
                    }
                }
                completion(mutationState.recordedError())
            } catch {
                completion(error)
            }
        }
    }

    private func readActiveAuthorityLocked() throws -> (counter: Int, fence: AutoFillFence) {
        let counter = try readCounterLocked()
        let fence = try readFenceLocked()
        guard counter == fence.generation,
              fence.state == .active else {
            throw AutoFillCacheError.cacheUnavailable
        }
        return (counter, fence)
    }

    private func requireActive(generation: Int, cacheId: String) throws {
        try withStateProcessLock {
            try requireActiveLocked(generation: generation, cacheId: cacheId)
        }
    }

    private func requireActiveLocked(generation: Int, cacheId: String?) throws {
        let counter = try readCounterLocked()
        let fence = try readFenceLocked()
        guard counter == generation,
              fence.generation == generation,
              fence.state == .active,
              fence.cacheId == cacheId else {
            throw AutoFillCacheError.staleSession
        }
    }

    private func quarantineCurrentFenceLocked() throws {
        let counter = try readCounterLocked()
        let fence = try readFenceLocked()
        guard let quarantined = AutoFillFenceRules.quarantineAfterAuthorityFailure(
            counter: counter,
            fence: fence
        ) else { return }
        try writeFenceLocked(quarantined)
    }

    private func nextGenerationLocked(now: Date) throws -> Int {
        let wallGeneration = Int(now.timeIntervalSince1970 * 1_000)
        let counter = (try? readCounterLocked()) ?? 0
        let fenceGeneration = (try? readFenceLocked().generation) ?? 0
        let base = max(wallGeneration, max(counter, fenceGeneration))
        guard base < Int.max else { throw AutoFillCacheError.cacheUnavailable }
        return base + 1
    }

    private func writeEnvelope(_ envelope: AutoFillCacheEnvelope) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "version": envelope.version,
            "generation": envelope.generation,
            "cacheId": envelope.cacheId,
            "sealedPayload": envelope.sealedPayload.base64EncodedString(),
        ], options: [.sortedKeys])
        try data.write(
            to: cacheURL(generation: envelope.generation),
            options: [.atomic, .completeFileProtection]
        )
    }

    private func readEnvelope(generation: Int) throws -> AutoFillCacheEnvelope {
        let url = cacheURL(generation: generation)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber,
              size.intValue > 0,
              size.intValue <= Self.maximumCacheBytes,
              let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              Set(raw.keys) == Set(["version", "generation", "cacheId", "sealedPayload"]),
              let version = raw["version"] as? Int,
              let envelopeGeneration = raw["generation"] as? Int,
              let cacheId = raw["cacheId"] as? String,
              !cacheId.isEmpty,
              let sealedValue = raw["sealedPayload"] as? String,
              let sealedPayload = Data(base64Encoded: sealedValue) else {
            throw AutoFillCacheError.invalidRecords
        }
        guard version == AutoFillPayloadValidator.cacheVersion else {
            throw AutoFillCacheError.unsupportedVersion
        }
        return AutoFillCacheEnvelope(
            version: version,
            generation: envelopeGeneration,
            cacheId: cacheId,
            sealedPayload: sealedPayload
        )
    }

    private func cacheURL(generation: Int) -> URL {
        containerURL.appendingPathComponent(
            "\(Self.cacheFilePrefix)\(generation)",
            isDirectory: false
        )
    }

    private func cacheAAD(generation: Int, cacheId: String) -> Data {
        Data("palladin-autofill-cache-v2:\(generation):\(cacheId)".utf8)
    }

    private func secureRandomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let address = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, address)
        }
        guard status == errSecSuccess else { throw AutoFillCacheError.keychain(status) }
        return data
    }

    private func writeWallTimeState(
        maximumObserved: Date,
        generation: Int,
        cacheId: String,
        integrityKeyBytes: Data
    ) throws {
        let combined = try AutoFillWallTimeStateCodec.seal(
            maximumObserved: maximumObserved,
            generation: generation,
            cacheId: cacheId,
            keyBytes: integrityKeyBytes
        )
        try setKeychainData(
            combined,
            account: "\(Self.wallTimePrefix)\(generation)",
            accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
    }

    private func readWallTimeState(
        generation: Int,
        cacheId: String,
        integrityKeyBytes: Data
    ) throws -> Date {
        let combined = try readKeychainData(account: "\(Self.wallTimePrefix)\(generation)")
        return try AutoFillWallTimeStateCodec.open(
            combined,
            generation: generation,
            cacheId: cacheId,
            keyBytes: integrityKeyBytes
        )
    }

    private func writeGlobalWallTimeState(
        maximumObserved: Date,
        integrityKeyBytes: Data
    ) throws {
        let combined = try AutoFillWallTimeStateCodec.seal(
            maximumObserved: maximumObserved,
            generation: Self.globalWallTimeGeneration,
            cacheId: Self.globalWallTimeCacheId,
            keyBytes: integrityKeyBytes
        )
        try setKeychainData(
            combined,
            account: Self.globalWallTimeAccount,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
    }

    private func readGlobalWallTimeState(integrityKeyBytes: Data) throws -> Date {
        let combined = try readKeychainData(account: Self.globalWallTimeAccount)
        return try AutoFillWallTimeStateCodec.open(
            combined,
            generation: Self.globalWallTimeGeneration,
            cacheId: Self.globalWallTimeCacheId,
            keyBytes: integrityKeyBytes
        )
    }

    private func readOrInitializeGlobalWallTimeLocked(
        now: Date,
        allowInitialization: Bool
    ) throws -> (integrityKey: Data, maximumObserved: Date) {
        let existingKey = try readKeychainDataIfPresent(
            account: Self.wallIntegrityKeyAccount
        )
        let existingState = try readKeychainDataIfPresent(
            account: Self.globalWallTimeAccount
        )
        try AutoFillWallTimeAuthorityRules.validatePresence(
            integrityKeyExists: existingKey != nil,
            globalStateExists: existingState != nil,
            allowInitialization: allowInitialization
        )
        guard let integrityKey = existingKey, let existingState else {
            let key = try secureRandomBytes(count: 32)
            try setKeychainData(
                key,
                account: Self.wallIntegrityKeyAccount,
                accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            )
            try writeGlobalWallTimeState(maximumObserved: now, integrityKeyBytes: key)
            return (key, now)
        }
        guard integrityKey.count == 32 else { throw AutoFillCacheError.cacheUnavailable }
        let previous = try AutoFillWallTimeStateCodec.open(
            existingState,
            generation: Self.globalWallTimeGeneration,
            cacheId: Self.globalWallTimeCacheId,
            keyBytes: integrityKey
        )
        let maximum = try AutoFillWallTimeCoordinator.maximumObservedWallTime(
            now: now,
            globalPrevious: previous,
            generationPrevious: nil
        )
        if maximum > previous {
            try writeGlobalWallTimeState(
                maximumObserved: maximum,
                integrityKeyBytes: integrityKey
            )
        }
        return (integrityKey, maximum)
    }

    private func hasExistingV2AuthorityLocked() throws -> Bool {
        if try readKeychainDataIfPresent(account: Self.generationCounterAccount) != nil ||
            readKeychainDataIfPresent(account: Self.fenceAccount) != nil {
            return true
        }
        if try !keychainAccounts(withPrefix: Self.cacheKeyPrefix).isEmpty ||
            !keychainAccounts(withPrefix: Self.wallTimePrefix).isEmpty {
            return true
        }
        return try FileManager.default.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: nil
        ).contains { $0.lastPathComponent.hasPrefix(Self.cacheFilePrefix) }
    }

    private func readWallIntegrityKeyLocked() throws -> Data {
        let key = try readKeychainData(account: Self.wallIntegrityKeyAccount)
        guard key.count == 32 else { throw AutoFillCacheError.cacheUnavailable }
        return key
    }

    private func revalidateCredentialLocked(
        _ credential: AutoFillCredentialLease,
        serviceIdentifiers: [ASCredentialServiceIdentifier],
        now: Date,
        systemUptime: TimeInterval
    ) throws {
        try requireActiveLocked(
            generation: credential.generation,
            cacheId: credential.cacheId
        )
        try validateProcessWallTimeLocked(now: now, systemUptime: systemUptime)
        do {
            let integrityKey = try readWallIntegrityKeyLocked()
            let globalPrevious = try readGlobalWallTimeState(integrityKeyBytes: integrityKey)
            let generationPrevious = try readWallTimeState(
                generation: credential.generation,
                cacheId: credential.cacheId,
                integrityKeyBytes: integrityKey
            )
            let maximum = try AutoFillWallTimeCoordinator.maximumObservedWallTime(
                now: now,
                globalPrevious: globalPrevious,
                generationPrevious: generationPrevious
            )
            if maximum > globalPrevious {
                try writeGlobalWallTimeState(
                    maximumObserved: maximum,
                    integrityKeyBytes: integrityKey
                )
            }
            if maximum > generationPrevious {
                try writeWallTimeState(
                    maximumObserved: maximum,
                    generation: credential.generation,
                    cacheId: credential.cacheId,
                    integrityKeyBytes: integrityKey
                )
            }
        } catch {
            try? quarantineCurrentFenceLocked()
            throw error
        }
        try AutoFillCredentialUseGuard.validate(
            credential,
            serviceIdentifiers: serviceIdentifiers,
            now: now,
            currentCounter: try? readCounterLocked(),
            currentFence: try? readFenceLocked()
        )
    }

    private func validateProcessWallTimeLocked(
        now: Date,
        systemUptime: TimeInterval
    ) throws {
        do {
            try Self.monotonicWallTimeGuard.validate(
                wallTime: now,
                uptime: systemUptime
            )
        } catch {
            try? quarantineCurrentFenceLocked()
            throw error
        }
    }

    private func writeFenceLocked(_ fence: AutoFillFence) throws {
        let serializedCacheId: Any = fence.cacheId.map { $0 as Any } ?? NSNull()
        let data = try JSONSerialization.data(withJSONObject: [
            "generation": fence.generation,
            "state": fence.state.rawValue,
            "cacheId": serializedCacheId,
        ], options: [.sortedKeys])
        try setKeychainData(
            data,
            account: Self.fenceAccount,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
    }

    private func readFenceLocked() throws -> AutoFillFence {
        let data = try readKeychainData(account: Self.fenceAccount)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(raw.keys) == Set(["generation", "state", "cacheId"]),
              let generation = raw["generation"] as? Int,
              generation > 0,
              let rawState = raw["state"] as? String,
              let state = AutoFillFenceState(rawValue: rawState),
              raw["cacheId"] is NSNull || raw["cacheId"] is String else {
            throw AutoFillCacheError.cacheUnavailable
        }
        let cacheId = raw["cacheId"] as? String
        guard (state == .active || cacheId == nil),
              cacheId?.isEmpty != true else {
            throw AutoFillCacheError.cacheUnavailable
        }
        return AutoFillFence(generation: generation, state: state, cacheId: cacheId)
    }

    private func writeCounterLocked(_ generation: Int) throws {
        try setKeychainData(
            Data(String(generation).utf8),
            account: Self.generationCounterAccount,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
    }

    private func readCounterLocked() throws -> Int {
        let data = try readKeychainData(account: Self.generationCounterAccount)
        guard let value = String(data: data, encoding: .utf8),
              let generation = Int(value),
              generation > 0,
              value == String(generation) else {
            throw AutoFillCacheError.cacheUnavailable
        }
        return generation
    }

    private func replaceOpeningKey(_ key: Data, generation: Int) throws {
        let account = "\(Self.cacheKeyPrefix)\(generation)"
        try deleteKeychainItem(account: account)
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw error?.takeRetainedValue() ?? AutoFillCacheError.cacheUnavailable
        }
        var query = keychainBaseQuery(account: account)
        query[kSecValueData as String] = key
        query[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AutoFillCacheError.keychain(status) }
    }

    private func readOpeningKey(authenticationPrompt: String, generation: Int) throws -> Data {
        var query = keychainBaseQuery(account: "\(Self.cacheKeyPrefix)\(generation)")
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.localizedReason = authenticationPrompt
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let key = result as? Data else {
            throw AutoFillCacheError.keychain(status)
        }
        return key
    }

    private func setKeychainData(
        _ data: Data,
        account: String,
        accessible: CFString
    ) throws {
        let base = keychainBaseQuery(account: account)
        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AutoFillCacheError.keychain(updateStatus)
        }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = accessible
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw AutoFillCacheError.keychain(addStatus) }
    }

    private func readKeychainData(account: String) throws -> Data {
        var query = keychainBaseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw AutoFillCacheError.keychain(status)
        }
        return data
    }

    private func readKeychainDataIfPresent(account: String) throws -> Data? {
        do {
            return try readKeychainData(account: account)
        } catch AutoFillCacheError.keychain(let status) where status == errSecItemNotFound {
            return nil
        }
    }

    private func keychainBaseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: keychainAccessGroupIdentifier,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private func deleteArtifactsLocked(generation: Int) throws {
        var firstError: Error?
        do {
            try FileManager.default.removeItem(at: cacheURL(generation: generation))
        } catch CocoaError.fileNoSuchFile {
            // An absent artifact is already denied by the generation fence.
        } catch {
            firstError = error
        }
        for account in [
            "\(Self.cacheKeyPrefix)\(generation)",
            "\(Self.wallTimePrefix)\(generation)",
        ] {
            do {
                try deleteKeychainItem(account: account)
            } catch where firstError == nil {
                firstError = error
            } catch {
                // Preserve the first cleanup error.
            }
        }
        if let firstError { throw firstError }
    }

    private func cleanupArtifactsLocked(olderThan generation: Int) throws {
        let counter = try? readCounterLocked()
        let urls = try FileManager.default.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: nil
        )
        for url in urls where url.lastPathComponent.hasPrefix(Self.cacheFilePrefix) {
            let suffix = url.lastPathComponent.dropFirst(Self.cacheFilePrefix.count)
            guard let artifactGeneration = Int(suffix),
                  AutoFillFenceRules.mayDeleteArtifacts(
                    artifactGeneration: artifactGeneration,
                    cleanupGeneration: generation,
                    currentCounter: counter
                  ) else { continue }
            try? FileManager.default.removeItem(at: url)
            try? deleteKeychainItem(account: "\(Self.cacheKeyPrefix)\(artifactGeneration)")
            try? deleteKeychainItem(account: "\(Self.wallTimePrefix)\(artifactGeneration)")
        }
        for prefix in [Self.cacheKeyPrefix, Self.wallTimePrefix] {
            for account in try keychainAccounts(withPrefix: prefix) {
                let suffix = account.dropFirst(prefix.count)
                guard let artifactGeneration = Int(suffix),
                      AutoFillFenceRules.mayDeleteArtifacts(
                        artifactGeneration: artifactGeneration,
                        cleanupGeneration: generation,
                        currentCounter: counter
                      ) else { continue }
                try? deleteKeychainItem(account: account)
            }
        }
    }

    private func purgeLegacyLocked() throws {
        var firstError: Error?
        do {
            try FileManager.default.removeItem(
                at: containerURL.appendingPathComponent(Self.legacyCacheFileName)
            )
        } catch CocoaError.fileNoSuchFile {
            // No legacy cache remains.
        } catch {
            firstError = error
        }
        do {
            try deleteKeychainItem(account: Self.legacyKeyAccount)
        } catch where firstError == nil {
            firstError = error
        } catch {
            // Preserve the first cleanup error.
        }
        if let firstError { throw firstError }
    }

    private func deleteKeychainItem(account: String) throws {
        let status = SecItemDelete(keychainBaseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AutoFillCacheError.keychain(status)
        }
    }

    private func keychainAccounts(withPrefix prefix: String) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccessGroup as String: keychainAccessGroupIdentifier,
            kSecAttrSynchronizable as String: false,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw AutoFillCacheError.keychain(status) }
        let attributes: [[String: Any]]
        if let many = result as? [[String: Any]] {
            attributes = many
        } else if let one = result as? [String: Any] {
            attributes = [one]
        } else {
            throw AutoFillCacheError.cacheUnavailable
        }
        return attributes.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(prefix) else { return nil }
            return account
        }
    }

    private func withStateProcessLock<T>(_ body: () throws -> T) throws -> T {
        try withProcessLock(fileName: Self.stateLockFileName, body)
    }

    private func withProcessLock<T>(
        fileName: String,
        _ body: () throws -> T
    ) throws -> T {
        let lease = try acquireProcessLock(fileName: fileName)
        defer { lease.release() }
        return try body()
    }

    private func acquireProcessLock(fileName: String) throws -> AutoFillFileLockLease {
        let url = containerURL.appendingPathComponent(fileName, isDirectory: false)
        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw AutoFillCacheError.cacheUnavailable }
        guard flock(descriptor, LOCK_EX) == 0 else {
            close(descriptor)
            throw AutoFillCacheError.cacheUnavailable
        }
        return AutoFillFileLockLease(descriptor: descriptor)
    }
}
