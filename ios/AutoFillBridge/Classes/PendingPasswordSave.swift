import CryptoKit
import Darwin
import Foundation
import LocalAuthentication
import Security

enum PasswordSaveError: Error { case unavailable, invalid, keychain(OSStatus) }

/// Independent authority: ordinary AutoFill cache invalidation cannot revoke its own save.
struct PasswordSaveAuthority: Codable, Equatable {
    let principal: String
    let session: String
    var captureID: String?
    var pending: PasswordSaveBinding?
}

struct PasswordSaveBinding: Codable, Equatable {
    let id: String
    let origin: String
    let formSession: String
    let created: TimeInterval
    let expires: TimeInterval
}

struct PasswordSavePayload: Codable {
    let authority: PasswordSaveAuthority
    let username: String
    let password: String
}

/// A cancelled provider operation cannot complete after a delayed biometric callback.
final class PasswordSaveOperation {
    private let lock = NSLock()
    private var active = true
    func cancel() { lock.lock(); defer { lock.unlock() }; active = false }
    func perform<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard active else { throw PasswordSaveError.invalid }
        return try body()
    }
}

final class PendingPasswordSave {
    private let container: URL
    private let readAuthority: () throws -> PasswordSaveAuthority?
    private let writeAuthority: (PasswordSaveAuthority?) throws -> Void
    private let readKey: (String) throws -> Data
    private let now: () -> TimeInterval
    private var ciphertextURL: URL { container.appendingPathComponent("pending-password-save-v1") }

    init(container: URL,
         readAuthority: @escaping () throws -> PasswordSaveAuthority?,
         writeAuthority: @escaping (PasswordSaveAuthority?) throws -> Void,
         readKey: @escaping (String) throws -> Data,
         now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.container = container
        self.readAuthority = readAuthority
        self.writeAuthority = writeAuthority
        self.readKey = readKey
        self.now = now
    }

    convenience init(bundle: Bundle = .main) throws {
        let storage = try PasswordSaveKeychain(bundle: bundle)
        self.init(container: storage.container, readAuthority: storage.authority,
                  writeAuthority: storage.setAuthority, readKey: storage.key)
    }

    static func exactOrigin(_ value: String) -> String? {
        guard value.utf8.count <= 4096, value.unicodeScalars.allSatisfy({ $0.isASCII }),
              !value.contains("\\"), !value.contains("%"),
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URLComponents(string: value), url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased(), host.utf8.count <= 253,
              host.contains("."), !host.hasSuffix("."),
              host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  !label.isEmpty && label.count <= 63 &&
                  label.first != "-" && label.last != "-" &&
                  label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
              }) else { return nil }
        // URLComponents accepts an empty explicit port, which must also fail closed.
        let authority = value.dropFirst("https://".count).split(separator: "/", maxSplits: 1)[0]
            .split(separator: "?", maxSplits: 1)[0].split(separator: "#", maxSplits: 1)[0]
        guard !authority.contains(":") else { return nil }
        return "https://\(host)"
    }

    func activate(principal: String) throws -> String {
        guard !principal.isEmpty, principal.utf8.count <= 128 else { throw PasswordSaveError.invalid }
        return try locked {
            if let current = try readAuthority(), current.principal == principal { return current.session }
            let authority = PasswordSaveAuthority(principal: principal, session: UUID().uuidString)
            try writeAuthority(authority)
            try removeCiphertext()
            return authority.session
        }
    }

    func revoke() throws {
        try locked { try writeAuthority(nil); try removeCiphertext() }
    }

    func cancel() throws {
        try locked {
            if var authority = try readAuthority() {
                authority.pending = nil
                authority.captureID = nil
                try writeAuthority(authority)
            }
            try removeCiphertext()
        }
    }

    func discard(id: String) throws {
        try locked {
            guard var authority = try readAuthority(), authority.pending?.id == id else { return }
            authority.pending = nil
            authority.captureID = nil
            try writeAuthority(authority)
            try removeCiphertext()
        }
    }

    func pending() throws -> String? {
        try locked {
            guard let authority = try readAuthority(), let binding = authority.pending else { return nil }
            guard validTime(binding) else {
                var expired = authority; expired.pending = nil
                try writeAuthority(expired); try removeCiphertext()
                return nil
            }
            return binding.id
        }
    }

    func activeSession() throws -> String? {
        try locked { try readAuthority()?.session }
    }

    func stage(expectedSession: String, origin: String, formSession: String, username: String, password: String,
               prompt: String, operation: PasswordSaveOperation) throws -> String {
        guard Self.exactOrigin(origin) == origin, !formSession.isEmpty,
              formSession.utf8.count <= 256, username.utf8.count <= 4096,
              !password.isEmpty, password.utf8.count <= 16384, !prompt.isEmpty else {
            throw PasswordSaveError.invalid
        }
        let requested = try locked { () throws -> PasswordSaveAuthority in
            guard let authority = try readAuthority(), authority.session == expectedSession else { throw PasswordSaveError.invalid }
            return authority
        }
        var key = try readKey(prompt)
        defer { key.resetBytes(in: 0..<key.count) }
        guard key.count == 32 else { throw PasswordSaveError.invalid }
        return try locked {
              try operation.perform {
                    guard try readAuthority() == requested else { throw PasswordSaveError.invalid }
                    let timestamp = now()
                    let binding = PasswordSaveBinding(id: UUID().uuidString, origin: origin,
                        formSession: formSession, created: timestamp, expires: timestamp + 120)
                    var updated = requested; updated.pending = binding; updated.captureID = binding.id
                    var plaintext = try JSONEncoder().encode(PasswordSavePayload(
                        authority: updated, username: username, password: password))
                    defer { plaintext.resetBytes(in: 0..<plaintext.count) }
                    let aad = try authenticatedBinding(updated)
                    let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), authenticating: aad)
                    guard let combined = sealed.combined else { throw PasswordSaveError.invalid }
                    #if os(iOS)
                    try combined.write(to: ciphertextURL, options: [.atomic, .completeFileProtection])
                    #else
                    try combined.write(to: ciphertextURL, options: [.atomic])
                    #endif
                    do { try writeAuthority(updated) }
                    catch { try? removeCiphertext(); throw error }
                    return binding.id
            }
        }
    }

    func completeStaging(id: String, session: String, operation: PasswordSaveOperation,
                         handoff: () throws -> Void) throws {
        try locked {
            try operation.perform {
                guard let authority = try readAuthority(), authority.session == session,
                      let binding = authority.pending, binding.id == id, validTime(binding) else {
                    throw PasswordSaveError.invalid
                }
                try handoff()
            }
        }
    }

    func take(id: String, session: String, prompt: String,
              operation: PasswordSaveOperation = PasswordSaveOperation()) throws -> PasswordSavePayload? {
        guard !prompt.isEmpty else { throw PasswordSaveError.invalid }
        let requested = try locked { () throws -> PasswordSaveAuthority? in
            guard let authority = try readAuthority(), authority.session == session,
                  let binding = authority.pending, binding.id == id, validTime(binding) else { return nil }
            return authority
        }
        guard let requested else { return nil }
        var key = try readKey(prompt)
        defer { key.resetBytes(in: 0..<key.count) }
        guard key.count == 32 else { throw PasswordSaveError.invalid }
        return try locked {
          try operation.perform {
            guard try readAuthority() == requested, let binding = requested.pending,
                  validTime(binding) else { throw PasswordSaveError.invalid }
            let size = try ciphertextURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 32768 else { throw PasswordSaveError.invalid }
            let ciphertext = try Data(contentsOf: ciphertextURL)
            var plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext),
                using: SymmetricKey(data: key), authenticating: authenticatedBinding(requested))
            defer { plaintext.resetBytes(in: 0..<plaintext.count) }
            let payload = try JSONDecoder().decode(PasswordSavePayload.self, from: plaintext)
            guard payload.authority == requested, Self.exactOrigin(binding.origin) == binding.origin else {
                throw PasswordSaveError.invalid
            }
            var consumed = requested; consumed.pending = nil
            try writeAuthority(consumed)
            // Deny replay and delete ciphertext before releasing any plaintext to Flutter.
            try removeCiphertext()
            return payload
          }
        }
    }

    func validate(_ authority: PasswordSaveAuthority, session: String, domain: String) throws -> Bool {
        try locked {
            guard let current = try readAuthority(), let binding = authority.pending else { return false }
            return current.principal == authority.principal && current.session == session &&
                current.captureID == binding.id &&
                current.session == authority.session && validTime(binding) &&
                binding.origin == "https://\(domain)"
        }
    }

    func remainingMillis(_ binding: PasswordSaveBinding) -> Int {
        max(0, min(120000, Int((binding.expires - now()) * 1000)))
    }

    private func authenticatedBinding(_ authority: PasswordSaveAuthority) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(authority)
    }

    private func validTime(_ binding: PasswordSaveBinding) -> Bool {
        let time = now()
        return time >= binding.created && time < binding.expires &&
            binding.expires - binding.created == 120
    }

    private func removeCiphertext() throws {
        if FileManager.default.fileExists(atPath: ciphertextURL.path) {
            try FileManager.default.removeItem(at: ciphertextURL)
        }
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        let descriptor = open(container.appendingPathComponent("pending-password-save-v1.lock").path,
                              O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw PasswordSaveError.unavailable }
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw PasswordSaveError.unavailable }
        return try body()
    }
}

private final class PasswordSaveKeychain {
    let container: URL
    private let group: String
    init(bundle: Bundle) throws {
        guard let group = bundle.object(forInfoDictionaryKey: "PalladinAutoFillAppGroupIdentifier") as? String,
              !group.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { throw PasswordSaveError.unavailable }
        self.group = group; self.container = container
    }
    func authority() throws -> PasswordSaveAuthority? {
        do { return try JSONDecoder().decode(PasswordSaveAuthority.self, from: read("authority")) }
        catch PasswordSaveError.keychain(errSecItemNotFound) { return nil }
    }
    func setAuthority(_ authority: PasswordSaveAuthority?) throws {
        if let authority {
            try ensureKey()
            try write(JSONEncoder().encode(authority), account: "authority", biometric: false)
        } else { try delete("authority") }
    }
    func key(prompt: String) throws -> Data { try read("key", prompt: prompt) }
    private func ensureKey() throws {
        do { var value = try read("key"); value.resetBytes(in: 0..<value.count) }
        catch PasswordSaveError.keychain(let status) where status == errSecInteractionNotAllowed || status == errSecAuthFailed { return }
        catch PasswordSaveError.keychain(errSecItemNotFound) {
            var key = Data(count: 32)
            defer { key.resetBytes(in: 0..<key.count) }
            guard key.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }) == errSecSuccess
            else { throw PasswordSaveError.unavailable }
            try write(key, account: "key", biometric: true)
        }
    }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "io.palladin.mobile.pending-password-save.v1",
         kSecAttrAccount as String: account, kSecAttrAccessGroup as String: group,
         kSecAttrSynchronizable as String: false]
    }
    private func read(_ account: String, prompt: String? = nil) throws -> Data {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        if let prompt { context.localizedReason = prompt }
        else { context.interactionNotAllowed = true }
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw PasswordSaveError.keychain(status) }
        return data
    }
    private func write(_ data: Data, account: String, biometric: Bool) throws {
        // SecItemUpdate preserves the old authority if a write fails.
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw PasswordSaveError.keychain(status) }
        var query = query(account); query[kSecValueData as String] = data
        if biometric {
            var error: Unmanaged<CFError>?
            guard let control = SecAccessControlCreateWithFlags(nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &error)
            else { throw PasswordSaveError.unavailable }
            query[kSecAttrAccessControl as String] = control
        } else { query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly }
        let added = SecItemAdd(query as CFDictionary, nil)
        guard added == errSecSuccess else { throw PasswordSaveError.keychain(added) }
    }
    private func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PasswordSaveError.keychain(status) }
    }
}

#if os(iOS)
import AuthenticationServices

extension PendingPasswordSave {
    @available(iOS 26.2, *)
    static func origin(for request: ASSavePasswordRequest) -> String? {
        guard request.event == .userInitiated, request.serviceIdentifier.type == .URL else { return nil }
        return exactOrigin(request.serviceIdentifier.identifier)
    }
}
#endif
