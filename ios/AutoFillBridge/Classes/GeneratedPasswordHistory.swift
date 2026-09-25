import AuthenticationServices
import CryptoKit
import Darwin
import Foundation
import LocalAuthentication
import Security

struct GeneratedPasswordRecord {
    let id: String
    let domain: String
    let createdAtMillis: Int64
    let password: String
}

enum GeneratedPasswordHistoryError: Error {
    case unavailable
    case invalidState
    case full
    case keychain(OSStatus)
}

enum StrongPasswordGenerator {
    private static let lower = Array("abcdefghijklmnopqrstuvwxyz")
    private static let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let digits = Array("0123456789")
    private static let symbols = Array("!@#$%^&*()-_=+[]{};:,.?/")
    private static let classes: [String: [Character]] = [
        "lower": lower, "upper": upper, "digit": digits, "special": symbols,
    ]

    struct Rules {
        let minimum: Int
        let maximum: Int
        let allowed: Set<String>
        let required: Set<String>
        let maxConsecutive: Int?

        static func parse(_ sources: [String?]) throws -> Rules {
            var minimum = 8
            var maximum = 64
            var allowed = Set(StrongPasswordGenerator.classes.keys)
            var required = Set<String>()
            var maxConsecutive: Int?
            for source in sources.compactMap({ $0 }) where !source.isEmpty {
                for rawClause in source.split(separator: ";") {
                    let parts = rawClause.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { throw GeneratedPasswordHistoryError.invalidState }
                    let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                    let values = parts[1].split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespaces).lowercased()
                    }
                    guard !values.isEmpty else { throw GeneratedPasswordHistoryError.invalidState }
                    switch name {
                    case "allowed", "required":
                        let categories = Set(values)
                        guard categories.isSubset(of: Set(StrongPasswordGenerator.classes.keys)
                                .union(["ascii-printable"])) else {
                            throw GeneratedPasswordHistoryError.invalidState
                        }
                        let expanded = categories.contains("ascii-printable")
                            ? Set(StrongPasswordGenerator.classes.keys) : categories
                        if name == "allowed" { allowed.formIntersection(expanded) }
                        else { required.formUnion(expanded) }
                    case "minlength":
                        guard values.count == 1, let value = Int(values[0]) else {
                            throw GeneratedPasswordHistoryError.invalidState
                        }
                        minimum = max(minimum, value)
                    case "maxlength":
                        guard values.count == 1, let value = Int(values[0]) else {
                            throw GeneratedPasswordHistoryError.invalidState
                        }
                        maximum = min(maximum, value)
                    case "max-consecutive":
                        guard values.count == 1, let value = Int(values[0]), value > 0 else {
                            throw GeneratedPasswordHistoryError.invalidState
                        }
                        maxConsecutive = min(maxConsecutive ?? value, value)
                    default:
                        throw GeneratedPasswordHistoryError.invalidState
                    }
                }
            }
            guard minimum <= maximum, maximum >= 8,
                  !allowed.isEmpty, required.isSubset(of: allowed) else {
                throw GeneratedPasswordHistoryError.invalidState
            }
            return Rules(minimum: minimum, maximum: maximum,
                         allowed: allowed, required: required,
                         maxConsecutive: maxConsecutive)
        }
    }

    static func generate(rules requestedRules: Rules? = nil) throws -> String {
        let rules = try requestedRules ?? Rules.parse([])
        let length = max(rules.minimum, min(20, rules.maximum))
        let ordered = ["lower", "upper", "digit", "special"]
            .filter { rules.allowed.contains($0) }
        let alphabet = ordered.flatMap { classes[$0]! }
        guard !alphabet.isEmpty, length >= ordered.count else {
            throw GeneratedPasswordHistoryError.invalidState
        }
        for _ in 0..<256 {
            var characters: [Character] = []
            for name in ordered {
                let category = classes[name]!
                characters.append(category[try secureIndex(category.count)])
            }
            while characters.count < length {
                characters.append(alphabet[try secureIndex(alphabet.count)])
            }
            for index in stride(from: characters.count - 1, through: 1, by: -1) {
                characters.swapAt(index, try secureIndex(index + 1))
            }
            if let limit = rules.maxConsecutive {
                var run = 1
                var valid = true
                for index in 1..<characters.count {
                    run = characters[index] == characters[index - 1] ? run + 1 : 1
                    if run > limit { valid = false; break }
                }
                if !valid { continue }
            }
            return String(characters)
        }
        throw GeneratedPasswordHistoryError.invalidState
    }

    private static func secureIndex(_ count: Int) throws -> Int {
        let ceiling = 256 - (256 % count)
        var byte: UInt8 = 0
        repeat {
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else {
                throw GeneratedPasswordHistoryError.unavailable
            }
        } while Int(byte) >= ceiling
        return Int(byte) % count
    }
}

/// History uses a stable biometric Keychain key. It is independent of the disposable
/// Vault credential cache, and only the authenticated app writes the session marker.
final class GeneratedPasswordHistory {
    private static let service = "io.palladin.mobile.generated-password-history.v1"
    private static let keyAccount = "history-key"
    private static let sessionAccount = "active-principal"
    private static let maxRecords = 100
    private let accessGroup: String
    private let container: URL

    init(bundle: Bundle = .main) throws {
        guard let group = bundle.object(
            forInfoDictionaryKey: "PalladinAutoFillAppGroupIdentifier"
        ) as? String, !group.isEmpty,
              let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: group
              ) else { throw GeneratedPasswordHistoryError.unavailable }
        accessGroup = group
        container = url
    }

    func activate(principalId: String) throws -> String {
        guard !principalId.isEmpty, principalId.count <= 128 else {
            throw GeneratedPasswordHistoryError.invalidState
        }
        return try withLock {
            try ensureKeyExists()
            let token = UUID().uuidString
            let marker = try JSONSerialization.data(withJSONObject: [
                "principalId": principalId, "token": token,
            ])
            try setItem(marker, account: Self.sessionAccount,
                        biometric: false)
            return token
        }
    }

    func revoke(token: String) throws {
        try withLock {
            guard let marker = try? readMarkerLocked() else { return }
            if marker.token == token { try deleteItem(account: Self.sessionAccount) }
        }
    }

    func revokeAll() throws {
        try withLock { try deleteItem(account: Self.sessionAccount) }
    }

    func hasActiveSession() -> Bool {
        (try? withLock { try activePrincipalLocked() }) != nil
    }

    func list(expectedPrincipal: String, prompt: String) throws -> [GeneratedPasswordRecord] {
        try withAuthorizedHistory(expectedPrincipal: expectedPrincipal, prompt: prompt) {
            principal, key in
            try readLocked(principal: principal, key: key)
        }
    }

    func delete(expectedPrincipal: String, id: String, prompt: String) throws {
        try withAuthorizedHistory(expectedPrincipal: expectedPrincipal, prompt: prompt) {
            principal, key in
            var records = try readLocked(principal: principal, key: key)
            guard let index = records.firstIndex(where: { $0.id == id }) else {
                throw GeneratedPasswordHistoryError.invalidState
            }
            records.remove(at: index)
            try writeLocked(records, principal: principal, key: key)
        }
    }

    func clear(expectedPrincipal: String, prompt: String) throws {
        try withAuthorizedHistory(expectedPrincipal: expectedPrincipal, prompt: prompt) {
            principal, key in
            _ = try readLocked(principal: principal, key: key)
            try writeLocked([], principal: principal, key: key)
        }
    }

    func appendAndHandoff(
        domain: String,
        password: String,
        prompt: String,
        expectedPrincipal: String? = nil,
        handoff: () throws -> Void
    ) throws {
        guard AutoFillCredentialRecord.normalizeDomain(domain) == domain,
              (8...64).contains(password.count) else {
            throw GeneratedPasswordHistoryError.invalidState
        }
        try withAuthorizedHistory(expectedPrincipal: expectedPrincipal, prompt: prompt) {
            principal, key in
            var records = try readLocked(principal: principal, key: key)
            guard records.count < Self.maxRecords else {
                throw GeneratedPasswordHistoryError.full
            }
            records.append(GeneratedPasswordRecord(
                id: UUID().uuidString,
                domain: domain,
                createdAtMillis: Int64(Date().timeIntervalSince1970 * 1000),
                password: password
            ))
            try writeLocked(records, principal: principal, key: key)
            try handoff()
        }
    }

    private func withAuthorizedHistory<T>(
        expectedPrincipal: String?, prompt: String,
        _ body: (String, Data) throws -> T
    ) throws -> T {
        let requestedSession = try withLock { try readMarkerLocked() }
        if let expectedPrincipal, requestedSession.principalId != expectedPrincipal {
            throw GeneratedPasswordHistoryError.invalidState
        }
        // Authentication can wait for the user. Revocation must not wait on it.
        return try withHistoryKey(prompt: prompt) { key in
            try withLock {
                let currentSession = try readMarkerLocked()
                guard currentSession.principalId == requestedSession.principalId,
                      currentSession.token == requestedSession.token else {
                    throw GeneratedPasswordHistoryError.invalidState
                }
                return try body(currentSession.principalId, key)
            }
        }
    }

    private func activePrincipalLocked() throws -> String {
        try readMarkerLocked().principalId
    }

    private func readMarkerLocked() throws -> (principalId: String, token: String) {
        let data = try readItem(account: Self.sessionAccount, prompt: nil)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(raw.keys) == Set(["principalId", "token"]),
              let principal = raw["principalId"] as? String,
              !principal.isEmpty, principal.count <= 128,
              let token = raw["token"] as? String,
              !token.isEmpty else {
            throw GeneratedPasswordHistoryError.invalidState
        }
        return (principal, token)
    }

    private func withHistoryKey<T>(prompt: String, _ body: (Data) throws -> T) throws -> T {
        var key = try readItem(account: Self.keyAccount, prompt: prompt)
        defer { key.resetBytes(in: 0..<key.count) }
        guard key.count == 32 else { throw GeneratedPasswordHistoryError.invalidState }
        return try body(key)
    }

    private func readLocked(principal: String, key: Data) throws -> [GeneratedPasswordRecord] {
        let url = historyURL(principal: principal)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 64 * 1024,
              let envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(envelope.keys) == Set(["version", "ciphertext"]),
              envelope["version"] as? Int == 1,
              let base64 = envelope["ciphertext"] as? String,
              let sealed = Data(base64Encoded: base64) else {
            throw GeneratedPasswordHistoryError.invalidState
        }
        let box = try AES.GCM.SealedBox(combined: sealed)
        var plaintext = try AES.GCM.open(
            box, using: SymmetricKey(data: key), authenticating: Data(aad(principal).utf8)
        )
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        guard let payload = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
              Set(payload.keys) == Set(["version", "principalId", "records"]),
              payload["version"] as? Int == 1,
              payload["principalId"] as? String == principal,
              let rawRecords = payload["records"] as? [[String: Any]],
              rawRecords.count <= Self.maxRecords else {
            throw GeneratedPasswordHistoryError.invalidState
        }
        var ids = Set<String>()
        return try rawRecords.map { raw in
            guard Set(raw.keys) == Set(["id", "domain", "createdAtMillis", "password"]),
                  let id = raw["id"] as? String, ids.insert(id).inserted,
                  let domain = raw["domain"] as? String,
                  AutoFillCredentialRecord.normalizeDomain(domain) == domain,
                  let timestamp = raw["createdAtMillis"] as? Int64,
                  let password = raw["password"] as? String,
                  (8...64).contains(password.count) else {
                throw GeneratedPasswordHistoryError.invalidState
            }
            return GeneratedPasswordRecord(
                id: id, domain: domain, createdAtMillis: timestamp, password: password
            )
        }
    }

    private func writeLocked(
        _ records: [GeneratedPasswordRecord], principal: String, key: Data
    ) throws {
        let payload: [String: Any] = [
            "version": 1,
            "principalId": principal,
            "records": records.map { record in
                ["id": record.id, "domain": record.domain,
                 "createdAtMillis": record.createdAtMillis, "password": record.password]
            },
        ]
        var plaintext = try JSONSerialization.data(withJSONObject: payload)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        let sealed = try AES.GCM.seal(
            plaintext, using: SymmetricKey(data: key), authenticating: Data(aad(principal).utf8)
        )
        guard let combined = sealed.combined else {
            throw GeneratedPasswordHistoryError.invalidState
        }
        let bytes = try JSONSerialization.data(withJSONObject: [
            "version": 1, "ciphertext": combined.base64EncodedString(),
        ])
        try bytes.write(to: historyURL(principal: principal),
                        options: [.atomic, .completeFileProtection])
    }

    private func historyURL(principal: String) -> URL {
        let digest = SHA256.hash(data: Data(principal.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return container.appendingPathComponent("generated-password-history-v1-\(digest)")
    }

    private func aad(_ principal: String) -> String {
        "palladin-generated-passwords-v1:\(principal)"
    }

    private func ensureKeyExists() throws {
        do {
            var key = try readItem(account: Self.keyAccount, prompt: nil, skipAuthentication: true)
            key.resetBytes(in: 0..<key.count)
            return
        } catch GeneratedPasswordHistoryError.keychain(let status)
            where status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return
        } catch GeneratedPasswordHistoryError.keychain(let status)
            where status == errSecItemNotFound {
            let existingHistory = try FileManager.default.contentsOfDirectory(
                at: container, includingPropertiesForKeys: nil
            ).contains { $0.lastPathComponent.hasPrefix("generated-password-history-v1-") }
            guard !existingHistory else { throw GeneratedPasswordHistoryError.invalidState }
            var key = Data(count: 32)
            let result = key.withUnsafeMutableBytes { bytes in
                SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
            }
            guard result == errSecSuccess else { throw GeneratedPasswordHistoryError.unavailable }
            defer { key.resetBytes(in: 0..<key.count) }
            try setItem(key, account: Self.keyAccount, biometric: true)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: accessGroup,
         kSecAttrSynchronizable as String: false]
    }

    private func setItem(_ data: Data, account: String, biometric: Bool) throws {
        try deleteItem(account: account)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        if biometric {
            var error: Unmanaged<CFError>?
            guard let control = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &error
            ) else { throw error?.takeRetainedValue() ?? GeneratedPasswordHistoryError.unavailable }
            query[kSecAttrAccessControl as String] = control
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw GeneratedPasswordHistoryError.keychain(status) }
    }

    private func readItem(
        account: String, prompt: String?, skipAuthentication: Bool = false
    ) throws -> Data {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if skipAuthentication {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        } else if let prompt {
            let context = LAContext()
            context.localizedReason = prompt
            query[kSecUseAuthenticationContext as String] = context
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw GeneratedPasswordHistoryError.keychain(status)
        }
        return data
    }

    private func deleteItem(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GeneratedPasswordHistoryError.keychain(status)
        }
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        let url = container.appendingPathComponent("generated-password-history-v1.lock")
        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw GeneratedPasswordHistoryError.unavailable }
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw GeneratedPasswordHistoryError.unavailable
        }
        return try body()
    }
}
