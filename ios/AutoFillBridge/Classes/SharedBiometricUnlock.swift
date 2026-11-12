import Foundation
import CryptoKit
import LocalAuthentication
import Security
import Darwin

protocol SharedBiometricUnlockKeychain {
    func loadState() throws -> Data?
    func saveState(_ data: Data) throws
    func storeWrappingKey(_ data: Data, id: String) throws
    func readWrappingKey(id: String, context: LAContext) throws -> Data
    func deleteWrappingKey(id: String) throws
}

enum SharedBiometricUnlockError: Error {
    case invalid, unavailable, stale, keychain(OSStatus), lockUnavailable
}

/// The caller supplies authenticated account binding and a live request/session
/// guard. Returned MK bytes belong to the caller and must be cleared after use.
final class SharedBiometricUnlock {
    private struct Envelope: Codable, Equatable {
        let keyID: String
        let profileBinding: String
        let ciphertext: Data
    }
    private struct State: Codable, Equatable {
        let version: Int
        let epoch: String
        let envelope: Envelope?
    }
    private let lockURL: URL
    private let accessGroup: String
    private let keychain: SharedBiometricUnlockKeychain

    init(containerURL: URL, accessGroup: String, keychain: SharedBiometricUnlockKeychain? = nil) {
        lockURL = containerURL.appendingPathComponent(".palladin-biometric-unlock-v1.lock")
        self.accessGroup = accessGroup
        self.keychain = keychain ?? SystemSharedBiometricKeychain(accessGroup: accessGroup)
    }

    /// A tombstone is distinct from a never-migrated device. Falling back to
    /// legacy storage after revocation would resurrect previously denied keys.
    func canMigrateLegacy() throws -> Bool {
        guard !accessGroup.isEmpty else { throw SharedBiometricUnlockError.invalid }
        return try locked { try loadState() == nil }
    }

    func isEnrolled(profileBinding: String) throws -> Bool {
        guard validProfile(profileBinding), !accessGroup.isEmpty else { throw SharedBiometricUnlockError.invalid }
        return try locked { try loadState()?.envelope?.profileBinding == profileBinding }
    }

    func enroll(masterKey: Data, profileBinding: String, validateOperation: () throws -> Void) throws {
        try enrollKey(masterKey: masterKey, profileBinding: profileBinding, requireAbsentState: false, validateOperation: validateOperation)
    }

    func migrateLegacyKey(masterKey: Data, profileBinding: String, validateOperation: () throws -> Void) throws {
        try enrollKey(masterKey: masterKey, profileBinding: profileBinding, requireAbsentState: true, validateOperation: validateOperation)
    }

    private func enrollKey(masterKey: Data, profileBinding: String, requireAbsentState: Bool, validateOperation: () throws -> Void) throws {
        guard masterKey.count == 32, validProfile(profileBinding), !accessGroup.isEmpty else {
            throw SharedBiometricUnlockError.invalid
        }
        let previous = try locked {
            try validateOperation()
            let state = try loadState()
            guard !requireAbsentState || state == nil else { throw SharedBiometricUnlockError.stale }
            return state
        }
        let epoch = UUID().uuidString.lowercased()
        let keyID = UUID().uuidString.lowercased()
        var key = Data(count: 32)
        defer { key.resetBytes(in: 0..<key.count) }
        guard key.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }) == errSecSuccess else {
            throw SharedBiometricUnlockError.unavailable
        }
        let aad = try associatedData(epoch: epoch, keyID: keyID, profileBinding: profileBinding)
        let sealed = try AES.GCM.seal(masterKey, using: SymmetricKey(data: key), authenticating: aad)
        guard let ciphertext = sealed.combined else { throw SharedBiometricUnlockError.invalid }
        var verified = try AES.GCM.open(sealed, using: SymmetricKey(data: key), authenticating: aad)
        defer { verified.resetBytes(in: 0..<verified.count) }
        guard verified == masterKey else { throw SharedBiometricUnlockError.invalid }
        let candidate = State(version: 1, epoch: epoch, envelope: Envelope(keyID: keyID, profileBinding: profileBinding, ciphertext: ciphertext))
        var committed = false
        do {
            try keychain.storeWrappingKey(key, id: keyID)
            try locked {
                try validateOperation()
                guard try loadState() == previous else { throw SharedBiometricUnlockError.stale }
                try saveState(candidate)
                committed = true
            }
            if let oldID = previous?.envelope?.keyID {
                try keychain.deleteWrappingKey(id: oldID)
            }
        } catch {
            // A late cleanup must never tombstone a newer enrollment or revoke.
            var failure: Error = error
            do {
                if committed {
                    try locked {
                        if try loadState() == candidate { try saveState(tombstone()) }
                    }
                }
            } catch { failure = error }
            // Even unavailable state storage must not skip key destruction.
            // If both fail, the caller's independent source denial remains set.
            do { try keychain.deleteWrappingKey(id: keyID) }
            catch { failure = error }
            throw failure
        }
    }

    func read(profileBinding: String, context: LAContext, validateOperation: () throws -> Void) throws -> Data {
        guard validProfile(profileBinding), !accessGroup.isEmpty else { throw SharedBiometricUnlockError.invalid }
        let captured: State = try locked {
            try validateOperation()
            guard let state = try loadState(), state.envelope?.profileBinding == profileBinding else {
                throw SharedBiometricUnlockError.unavailable
            }
            return state
        }
        guard let envelope = captured.envelope else { throw SharedBiometricUnlockError.unavailable }
        // Never hold the cross-process lock during a biometric prompt: logout
        // and disable must be able to publish their revocation immediately.
        var key = try keychain.readWrappingKey(id: envelope.keyID, context: context)
        defer { key.resetBytes(in: 0..<key.count) }
        guard key.count == 32 else { throw SharedBiometricUnlockError.invalid }
        return try locked {
            try validateOperation()
            guard try loadState() == captured else { throw SharedBiometricUnlockError.stale }
            let aad = try associatedData(epoch: captured.epoch, keyID: envelope.keyID, profileBinding: profileBinding)
            var plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.ciphertext), using: SymmetricKey(data: key), authenticating: aad)
            do {
                guard plaintext.count == 32 else { throw SharedBiometricUnlockError.invalid }
                try validateOperation()
                return plaintext
            } catch {
                plaintext.resetBytes(in: 0..<plaintext.count)
                throw error
            }
        }
    }

    /// Callers deny their source/session first. A persistence failure is an
    /// error, never evidence of successful revocation.
    func revoke(validateOperation: () throws -> Void = {}) throws {
        let oldID: String? = try locked {
            try validateOperation()
            let state = try loadState()
            try saveState(tombstone())
            return state?.envelope?.keyID
        }
        if let oldID = oldID { try keychain.deleteWrappingKey(id: oldID) }
    }

    private func tombstone() -> State {
        State(version: 1, epoch: UUID().uuidString.lowercased(), envelope: nil)
    }
    private func validProfile(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private func loadState() throws -> State? {
        guard let data = try keychain.loadState() else { return nil }
        guard data.count <= 8192 else { throw SharedBiometricUnlockError.invalid }
        let state = try JSONDecoder().decode(State.self, from: data)
        guard state.version == 1, UUID(uuidString: state.epoch) != nil else { throw SharedBiometricUnlockError.invalid }
        if let envelope = state.envelope {
            guard UUID(uuidString: envelope.keyID) != nil, validProfile(envelope.profileBinding), envelope.ciphertext.count == 60 else {
                throw SharedBiometricUnlockError.invalid
            }
        }
        return state
    }
    private func saveState(_ state: State) throws {
        try keychain.saveState(JSONEncoder().encode(state))
    }
    private func associatedData(epoch: String, keyID: String, profileBinding: String) throws -> Data {
        try JSONEncoder().encode(["palladin-biometric-unlock-v1", accessGroup, epoch, keyID, profileBinding])
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        let fd = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw SharedBiometricUnlockError.lockUnavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw SharedBiometricUnlockError.lockUnavailable }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
}

private final class SystemSharedBiometricKeychain: SharedBiometricUnlockKeychain {
    private let accessGroup: String
    private let service = "io.palladin.mobile.biometric-unlock.v1"
    init(accessGroup: String) { self.accessGroup = accessGroup }

    private func query(_ account: String) throws -> [String: Any] {
        guard !accessGroup.isEmpty else { throw SharedBiometricUnlockError.invalid }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: accessGroup, kSecAttrSynchronizable as String: false]
    }
    func loadState() throws -> Data? {
        var request = try query("state")
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SharedBiometricUnlockError.keychain(status) }
        return data
    }
    func saveState(_ data: Data) throws {
        let base = try query("state")
        let values: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(base as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = base
            values.forEach { item[$0.key] = $0.value }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw SharedBiometricUnlockError.keychain(added) }
        } else if status != errSecSuccess { throw SharedBiometricUnlockError.keychain(status) }
    }
    func storeWrappingKey(_ data: Data, id: String) throws {
        var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &error) else {
            throw SharedBiometricUnlockError.unavailable
        }
        var item = try query(id)
        item[kSecAttrAccessControl as String] = control
        item[kSecValueData as String] = data
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw SharedBiometricUnlockError.keychain(status) }
    }
    func readWrappingKey(id: String, context: LAContext) throws -> Data {
        var request = try query(id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw SharedBiometricUnlockError.keychain(status) }
        return data
    }
    func deleteWrappingKey(id: String) throws {
        var request = try query(id)
        let context = LAContext()
        context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        let status = SecItemDelete(request as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SharedBiometricUnlockError.keychain(status) }
    }
}
