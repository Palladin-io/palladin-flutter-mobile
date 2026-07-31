import AuthenticationServices
import CryptoKit
import Foundation
import Security

struct AutoFillCredentialRecord: Codable {
    let id: String
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

private struct AutoFillCacheEnvelope: Codable {
    let version: Int
    let sealedRecords: Data
}

enum AutoFillCacheError: Error {
    case invalidAppGroup
    case invalidRecords
    case keychain(OSStatus)
    case cacheUnavailable
    case unsupportedVersion
    case staleSession
}

final class AutoFillCacheStore {
    private static let cacheVersion = 1
    private static let maximumRecords = 2_000
    private static let maximumDomainsPerRecord = 16
    private static let maximumCacheBytes = 16 * 1024 * 1024
    private static let cacheFileName = "palladin_autofill_cache_v1"
    private static let keychainService = "io.palladin.mobile.autofill.cache"
    private static let keychainAccount = "cache-key-v1"
    private static let mutationLock = NSLock()
    private static var accessRevoked = true
    private static var currentSessionToken = 0

    private let appGroupIdentifier: String
    private let cacheURL: URL

    init(bundle: Bundle = .main) throws {
        guard let configuredIdentifier = bundle.object(
            forInfoDictionaryKey: "PalladinAutoFillAppGroupIdentifier"
        ) as? String,
        !configuredIdentifier.isEmpty else {
            throw AutoFillCacheError.invalidAppGroup
        }
        appGroupIdentifier = configuredIdentifier
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw AutoFillCacheError.invalidAppGroup
        }
        cacheURL = container.appendingPathComponent(Self.cacheFileName, isDirectory: false)
    }

    func beginSession() -> Int {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        Self.currentSessionToken += 1
        Self.accessRevoked = false
        return Self.currentSessionToken
    }

    func replace(
        records rawRecords: [[String: Any]],
        sessionToken: Int
    ) throws -> [AutoFillCredentialRecord] {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        guard !Self.accessRevoked,
              sessionToken == Self.currentSessionToken else {
            throw AutoFillCacheError.staleSession
        }
        guard rawRecords.count <= Self.maximumRecords else {
            throw AutoFillCacheError.invalidRecords
        }
        var serialized = try JSONSerialization.data(withJSONObject: rawRecords)
        defer { serialized.resetBytes(in: 0..<serialized.count) }
        let records = try JSONDecoder().decode([AutoFillCredentialRecord].self, from: serialized)
            .compactMap(Self.validated)
        var plaintext = try JSONEncoder().encode(records)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        var keyBytes = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        defer { keyBytes.resetBytes(in: 0..<keyBytes.count) }

        let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: keyBytes))
        guard let combined = sealed.combined else { throw AutoFillCacheError.invalidRecords }
        try replaceKey(keyBytes)
        let envelope = AutoFillCacheEnvelope(
            version: Self.cacheVersion,
            sealedRecords: combined
        )
        try JSONEncoder().encode(envelope).write(
            to: cacheURL,
            options: [.atomic, .completeFileProtection]
        )
        return records
    }

    func read(authenticationPrompt: String) throws -> [AutoFillCredentialRecord] {
        let attributes = try FileManager.default.attributesOfItem(atPath: cacheURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.intValue > 0,
              size.intValue <= Self.maximumCacheBytes else {
            throw AutoFillCacheError.invalidRecords
        }
        let envelope = try JSONDecoder().decode(
            AutoFillCacheEnvelope.self,
            from: Data(contentsOf: cacheURL)
        )
        guard envelope.version == Self.cacheVersion else {
            throw AutoFillCacheError.unsupportedVersion
        }
        var keyBytes = try readKey(authenticationPrompt: authenticationPrompt)
        defer { keyBytes.resetBytes(in: 0..<keyBytes.count) }
        let sealed = try AES.GCM.SealedBox(combined: envelope.sealedRecords)
        var plaintext = try AES.GCM.open(sealed, using: SymmetricKey(data: keyBytes))
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        return try JSONDecoder().decode([AutoFillCredentialRecord].self, from: plaintext)
    }

    func clear() throws {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        try clearLocked()
    }

    func clear(sessionToken: Int) throws {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        guard sessionToken == Self.currentSessionToken else { return }
        try clearLocked()
    }

    func revokeAccess() throws -> Int {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        Self.currentSessionToken += 1
        Self.accessRevoked = true
        try clearLocked()
        return Self.currentSessionToken
    }

    private func clearLocked() throws {
        var fileError: Error?
        do {
            try FileManager.default.removeItem(at: cacheURL)
        } catch CocoaError.fileNoSuchFile {
            // Idempotent clear: an absent cache is already safe.
        } catch {
            fileError = error
        }
        let status = SecItemDelete(keychainBaseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AutoFillCacheError.keychain(status)
        }
        if let fileError { throw fileError }
    }

    static func replaceIdentities(
        for records: [AutoFillCredentialRecord],
        completion: @escaping (Error?) -> Void
    ) {
        let identities = records.flatMap { record in
            record.domains.map { domain in
                ASPasswordCredentialIdentity(
                    serviceIdentifier: ASCredentialServiceIdentifier(identifier: domain, type: .domain),
                    user: record.username,
                    recordIdentifier: record.id
                )
            }
        }
        ASCredentialIdentityStore.shared.replaceCredentialIdentities(with: identities) {
            success, error in
            completion(success ? nil : (error ?? AutoFillCacheError.cacheUnavailable))
        }
    }

    static func clearIdentities(completion: @escaping (Error?) -> Void) {
        ASCredentialIdentityStore.shared.removeAllCredentialIdentities { success, error in
            completion(success ? nil : (error ?? AutoFillCacheError.cacheUnavailable))
        }
    }

    private static func validated(_ record: AutoFillCredentialRecord) -> AutoFillCredentialRecord? {
        guard record.domains.count <= maximumDomainsPerRecord else { return nil }
        let domains = Array(Set(record.domains.compactMap(AutoFillCredentialRecord.normalizeDomain))).sorted()
        guard !record.id.isEmpty,
              !record.label.isEmpty,
              !record.password.isEmpty,
              !domains.isEmpty else { return nil }
        return AutoFillCredentialRecord(
            id: record.id,
            label: record.label,
            username: record.username,
            password: record.password,
            domains: domains
        )
    }

    private func replaceKey(_ key: Data) throws {
        SecItemDelete(keychainBaseQuery() as CFDictionary)
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw error?.takeRetainedValue() ?? AutoFillCacheError.cacheUnavailable
        }
        var query = keychainBaseQuery()
        query[kSecValueData as String] = key
        query[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AutoFillCacheError.keychain(status) }
    }

    private func readKey(authenticationPrompt: String) throws -> Data {
        var query = keychainBaseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseOperationPrompt as String] = authenticationPrompt
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let key = result as? Data else {
            throw AutoFillCacheError.keychain(status)
        }
        return key
    }

    private func keychainBaseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecAttrAccessGroup as String: appGroupIdentifier,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
