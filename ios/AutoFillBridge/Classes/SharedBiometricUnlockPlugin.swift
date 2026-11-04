import Foundation
import LocalAuthentication
import CryptoKit
import Security

struct SharedBiometricTicket {
    let profileBinding: String
    let identityBinding: String
    let epoch: Int
    let validate: () throws -> Void
}

enum SharedBiometricFlowError: Error { case canceledWithoutChanges }

#if canImport(Flutter)
import Flutter
import UIKit

/// Runner owns registration and passes the same source-fence instance used by
/// its source bridge. The extension must never enable the legacy accessor.
final class SharedBiometricUnlockPlugin: NSObject, FlutterPlugin {
    private let store: SharedBiometricUnlock
    private let source: SharedMemberSourceFence
    private let flow: SharedBiometricUnlockFlow
    private let allowLegacy: Bool
    private let mutations = DispatchQueue(label: "io.palladin.mobile.shared-biometric-mutations", qos: .userInitiated)
    private var backgroundObserver: NSObjectProtocol?

    static func register(with registrar: FlutterPluginRegistrar) {
        // Explicit configuration is mandatory; never infer a broad keychain group.
        let channel = FlutterMethodChannel(name: "io.palladin.mobile/shared-biometric-unlock",
                                           binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { _, result in
            result(FlutterError(code: "unavailable", message: "Biometric source is not configured", details: nil))
        }
    }

    static func register(with registrar: FlutterPluginRegistrar, source: SharedMemberSourceFence,
                         containerURL: URL, accessGroup: String, allowLegacyMigration: Bool) {
        let instance = SharedBiometricUnlockPlugin(source: source, containerURL: containerURL,
            accessGroup: accessGroup, allowLegacyMigration: allowLegacyMigration)
        registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(
            name: "io.palladin.mobile/shared-biometric-unlock", binaryMessenger: registrar.messenger()))
    }

    init(source: SharedMemberSourceFence, containerURL: URL, accessGroup: String, allowLegacyMigration: Bool) {
        self.source = source
        store = SharedBiometricUnlock(containerURL: containerURL, accessGroup: accessGroup)
        allowLegacy = allowLegacyMigration
        flow = SharedBiometricUnlockFlow(store: store,
            legacyRead: { context in
                guard allowLegacyMigration else { throw SharedBiometricUnlockError.unavailable }
                return try Self.readLegacy(context)
            }, legacyDelete: {
                if allowLegacyMigration { try Self.deleteLegacy() }
            })
        super.init()
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.flow.cancel() }
    }

    deinit {
        flow.cancel()
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "canStore" {
            var error: NSError?
            result(LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error))
            return
        }
        let arguments = call.arguments as? [String: Any] ?? [:]
        if call.method == "cancelMigration" {
            guard let id = arguments["migrationId"] as? String, !id.isEmpty else {
                result(FlutterError(code: "unavailable", message: "Invalid migration", details: nil)); return
            }
            flow.cancel(id); result(nil); return
        }
        let mutation = ["enroll", "clear", "commitMigration"].contains(call.method)
        guard mutation || ["isEnrolled", "unlockKey"].contains(call.method) else {
            result(FlutterMethodNotImplemented); return
        }
        if call.method == "clear" { flow.cancel() }
        let execute = {
            do {
                let ticket = try self.ticket(arguments, mutation: mutation)
                let output: Any?
                switch call.method {
                case "isEnrolled":
                    try ticket.validate()
                    output = try self.store.isEnrolled(profileBinding: ticket.profileBinding) ||
                        (self.allowLegacy && self.store.canMigrateLegacy() && Self.legacyExists())
                    try ticket.validate()
                case "unlockKey":
                    let context = LAContext()
                    context.localizedReason = try Self.copy(arguments, "reason")
                    context.localizedCancelTitle = try Self.copy(arguments, "cancelLabel")
                    var opened = try self.flow.unlock(ticket, context: context)
                    defer { opened.masterKey.resetBytes(in: 0..<opened.masterKey.count) }
                    var response: [String: Any] = ["masterKey": FlutterStandardTypedData(bytes: opened.masterKey)]
                    if let id = opened.migrationID { response["migrationId"] = id }
                    output = response
                case "enroll":
                    var key = try Self.key(arguments)
                    defer { key.resetBytes(in: 0..<key.count) }
                    let context = LAContext()
                    context.localizedReason = try Self.copy(arguments, "reason")
                    context.localizedCancelTitle = try Self.copy(arguments, "cancelLabel")
                    try self.flow.enroll(key, ticket: ticket, context: context,
                        authenticateBeforeWrite: Self.authenticateEnrollment); output = nil
                case "commitMigration":
                    guard let id = arguments["migrationId"] as? String, !id.isEmpty else {
                        throw SharedBiometricUnlockError.invalid
                    }
                    var key = try Self.key(arguments)
                    defer { key.resetBytes(in: 0..<key.count) }
                    try self.flow.commit(id, verifiedKey: key, ticket: ticket); output = nil
                case "clear":
                    try self.flow.clear(ticket); output = nil
                default: throw SharedBiometricUnlockError.invalid
                }
                DispatchQueue.main.async { result(output) }
            } catch {
                let code = Self.errorCode(error, clearing: call.method == "clear")
                DispatchQueue.main.async { result(FlutterError(code: code, message: "Biometric operation did not complete", details: nil)) }
            }
        }
        if mutation { mutations.async(execute: execute) }
        else { DispatchQueue.global(qos: .userInitiated).async(execute: execute) }
    }

    private func ticket(_ arguments: [String: Any], mutation: Bool) throws -> SharedBiometricTicket {
        let captured = try source.current()
        guard arguments["sessionId"] as? String == captured.sessionID,
              arguments["sourceEpoch"] as? Int == captured.epoch,
              arguments["profileBinding"] as? String == captured.profileBinding,
              !mutation || captured.state == .quarantined else { throw SharedBiometricUnlockError.stale }
        let identity = try JSONSerialization.data(withJSONObject: [
            "sessionId": captured.sessionID, "profileBinding": captured.profileBinding,
            "claims": captured.claims.arguments, "accountUnlock": captured.accountUnlock.base64EncodedString()
        ], options: [.sortedKeys])
        let guardOperation = {
            try self.source.requireAppSession(captured.sessionID)
            try self.source.withCurrentSource(captured, requireActive: false, requireQuarantined: mutation) {}
        }
        try guardOperation()
        return SharedBiometricTicket(profileBinding: captured.profileBinding,
            identityBinding: Data(SHA256.hash(data: identity)).base64EncodedString(),
            epoch: captured.epoch, validate: guardOperation)
    }

    private static func copy(_ arguments: [String: Any], _ name: String) throws -> String {
        guard let text = arguments[name] as? String, !text.isEmpty, text.utf8.count <= 512 else {
            throw SharedBiometricUnlockError.invalid
        }
        return text
    }
    private static func key(_ arguments: [String: Any]) throws -> Data {
        guard let typed = arguments["masterKey"] as? FlutterStandardTypedData, typed.data.count == 32 else {
            throw SharedBiometricUnlockError.invalid
        }
        return typed.data
    }
    private static func legacyQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "flutter_biometric_storage",
         kSecAttrAccount as String: "palladin_vault_mk_v2",
         kSecUseDataProtectionKeychain as String: true]
    }
    private static func legacyExists() throws -> Bool {
        var query = legacyQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess || status == errSecInteractionNotAllowed else { throw SharedBiometricUnlockError.keychain(status) }
        return true
    }
    private static func readLegacy(_ context: LAContext) throws -> Data {
        var query = legacyQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        guard status == errSecSuccess, var encoded = value as? Data else { throw SharedBiometricUnlockError.keychain(status) }
        defer { encoded.resetBytes(in: 0..<encoded.count) }
        guard let key = Data(base64Encoded: encoded), key.count == 32 else { throw SharedBiometricUnlockError.invalid }
        return key
    }
    private static func deleteLegacy() throws {
        var query = legacyQuery()
        let context = LAContext(); context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SharedBiometricUnlockError.keychain(status) }
    }
    private static func errorCode(_ error: Error, clearing: Bool) -> String {
        if clearing { return "cleanup_failed" }
        if case SharedBiometricFlowError.canceledWithoutChanges = error { return "canceled_no_changes" }
        if let auth = error as? LAError {
            if [.userCancel, .appCancel, .systemCancel].contains(auth.code) { return "canceled" }
            if auth.code == .authenticationFailed { return "failed" }
        }
        if case SharedBiometricUnlockError.keychain(errSecUserCanceled) = error { return "canceled" }
        return "unavailable"
    }
    private static func authenticateEnrollment(_ context: LAContext) throws {
        let finished = DispatchSemaphore(value: 0)
        var success = false
        var failure: Error?
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
            localizedReason: context.localizedReason) { allowed, error in
            success = allowed; failure = error; finished.signal()
        }
        finished.wait()
        if success { return }
        if let auth = failure as? LAError, [.userCancel, .appCancel, .systemCancel].contains(auth.code) {
            throw SharedBiometricFlowError.canceledWithoutChanges
        }
        throw failure ?? SharedBiometricUnlockError.unavailable
    }
}
#endif

struct SharedBiometricRead {
    var masterKey: Data
    let migrationID: String?
}

final class SharedBiometricUnlockFlow {
    private struct Pending {
        let id: String
        let ticket: SharedBiometricTicket
        let context: LAContext
        let keyDigest: Data
        let generation: UInt64
        let deadline: TimeInterval
    }
    private let store: SharedBiometricUnlock
    private let legacyRead: (LAContext) throws -> Data
    private let legacyDelete: () throws -> Void
    private let lock = NSRecursiveLock()
    private let mutations = NSLock()
    private var generation: UInt64 = 0
    private var pending: Pending?
    private var activeMigrationID: String?
    private var activeContext: LAContext?
    init(store: SharedBiometricUnlock, legacyRead: @escaping (LAContext) throws -> Data,
         legacyDelete: @escaping () throws -> Void) {
        self.store = store; self.legacyRead = legacyRead; self.legacyDelete = legacyDelete
    }
    func unlock(_ ticket: SharedBiometricTicket, context: LAContext) throws -> SharedBiometricRead {
        let captured = start(context)
        var retained = false
        defer { if !retained { finish(captured) } }
        let guardOperation = { try self.validate(captured, ticket) }
        try guardOperation()
        if try store.isEnrolled(profileBinding: ticket.profileBinding) {
            return SharedBiometricRead(masterKey: try store.read(profileBinding: ticket.profileBinding,
                context: context, validateOperation: guardOperation), migrationID: nil)
        }
        guard try store.canMigrateLegacy() else { throw SharedBiometricUnlockError.unavailable }
        var key = try legacyRead(context)
        do {
            guard key.count == 32 else { throw SharedBiometricUnlockError.invalid }
            try guardOperation()
            guard try store.canMigrateLegacy() else { throw SharedBiometricUnlockError.stale }
            lock.lock(); defer { lock.unlock() }
            try guardOperation()
            let id = UUID().uuidString.lowercased()
            pending = Pending(id: id, ticket: ticket, context: context,
                keyDigest: Data(SHA256.hash(data: key)), generation: captured,
                deadline: ProcessInfo.processInfo.systemUptime + 120)
            activeMigrationID = id
            retained = true
            return SharedBiometricRead(masterKey: key, migrationID: id)
        } catch { key.resetBytes(in: 0..<key.count); throw error }
    }
    func commit(_ id: String, verifiedKey: Data, ticket: SharedBiometricTicket) throws {
        mutations.lock(); defer { mutations.unlock() }
        lock.lock()
        guard let item = pending, item.id == id else {
            lock.unlock(); throw SharedBiometricUnlockError.stale
        }
        pending = nil
        lock.unlock()
        defer { finish(item.generation) }
        let guardOperation = { try self.validate(item.generation, ticket) }
        guard item.deadline > ProcessInfo.processInfo.systemUptime,
              ticket.identityBinding == item.ticket.identityBinding,
              ticket.profileBinding == item.ticket.profileBinding,
              ticket.epoch >= item.ticket.epoch, verifiedKey.count == 32,
              Data(SHA256.hash(data: verifiedKey)) == item.keyDigest else {
            throw SharedBiometricUnlockError.stale
        }
        try guardOperation()
        try store.migrateLegacyKey(masterKey: verifiedKey, profileBinding: ticket.profileBinding, validateOperation: guardOperation)
        do {
            var checked = try store.read(profileBinding: ticket.profileBinding, context: item.context,
                validateOperation: guardOperation)
            defer { checked.resetBytes(in: 0..<checked.count) }
            guard checked == verifiedKey else { throw SharedBiometricUnlockError.invalid }
            try guardOperation()
            try legacyDelete()
        } catch {
            // Serialized mutation ownership plus this guard prevents an old
            // migration failure from revoking a newer session's enrollment.
            try? store.revoke(validateOperation: ticket.validate)
            throw error
        }
    }
    func enroll(_ key: Data, ticket: SharedBiometricTicket, context: LAContext = LAContext(),
                authenticateBeforeWrite: (LAContext) throws -> Void) throws {
        mutations.lock(); defer { mutations.unlock() }
        let captured = start(context)
        defer { finish(captured) }
        let guardOperation = { try self.validate(captured, ticket) }
        try guardOperation()
        try authenticateBeforeWrite(context)
        try guardOperation()
        try store.enroll(masterKey: key, profileBinding: ticket.profileBinding, validateOperation: guardOperation)
        do {
            var checked = try store.read(profileBinding: ticket.profileBinding, context: context, validateOperation: guardOperation)
            defer { checked.resetBytes(in: 0..<checked.count) }
            guard checked == key else { throw SharedBiometricUnlockError.invalid }
            try guardOperation()
            try legacyDelete()
        } catch {
            try? store.revoke(validateOperation: ticket.validate)
            throw error
        }
    }
    func clear(_ ticket: SharedBiometricTicket) throws {
        cancel()
        mutations.lock(); defer { mutations.unlock() }
        var failure: Error?
        do { try store.revoke(validateOperation: ticket.validate) } catch { failure = error }
        do { try ticket.validate(); try legacyDelete() } catch { failure = error }
        if let failure { throw failure }
    }
    func cancel(_ id: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let id, pending?.id != id && activeMigrationID != id { return }
        generation &+= 1
        pending = nil
        activeMigrationID = nil
        activeContext?.invalidate(); activeContext = nil
    }
    private func start(_ context: LAContext) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        cancel()
        activeContext = context
        return generation
    }
    private func validate(_ captured: UInt64, _ ticket: SharedBiometricTicket) throws {
        lock.lock(); defer { lock.unlock() }
        guard generation == captured else { throw SharedBiometricUnlockError.stale }
        try ticket.validate()
    }
    private func finish(_ captured: UInt64) {
        lock.lock(); defer { lock.unlock() }
        if generation == captured {
            generation &+= 1; pending = nil; activeMigrationID = nil
            activeContext?.invalidate(); activeContext = nil
        }
    }
}
