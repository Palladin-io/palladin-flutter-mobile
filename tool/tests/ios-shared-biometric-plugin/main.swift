import Foundation
import LocalAuthentication

enum Failure: Error { case assertion(String), injected }
func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw Failure.assertion(message) }
}
func rejects(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw Failure.assertion("Expected rejection")
}
final class Keychain: SharedBiometricUnlockKeychain {
    var state: Data?
    var keys: [String: Data] = [:]
    var onRead: (() throws -> Void)?
    var failSave = false
    func loadState() throws -> Data? { state }
    func saveState(_ data: Data) throws { if failSave { throw Failure.injected }; state = data }
    func storeWrappingKey(_ data: Data, id: String) throws { keys[id] = data }
    func readWrappingKey(id: String, context: LAContext) throws -> Data {
        let callback = onRead; onRead = nil; try callback?()
        guard let key = keys[id] else { throw Failure.injected }; return key
    }
    func deleteWrappingKey(id: String) throws { keys.removeValue(forKey: id) }
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let keychain = Keychain()
let store = SharedBiometricUnlock(containerURL: directory, accessGroup: "test.shared", keychain: keychain)
let mk = Data(repeating: 37, count: 32)
var deleted = false
let flow = SharedBiometricUnlockFlow(store: store, legacyRead: { _ in mk }, legacyDelete: { deleted = true })
let profile = String(repeating: "a", count: 64)
let readTicket = SharedBiometricTicket(profileBinding: profile, identityBinding: "session/account/v1", epoch: 1, validate: {})
let commitTicket = SharedBiometricTicket(profileBinding: profile, identityBinding: "session/account/v1", epoch: 2, validate: {})
do {
    let opened = try flow.unlock(readTicket, context: LAContext())
    try expect(opened.masterKey == mk && opened.migrationID != nil, "Legacy unlock must return pending migration capability")
    try expect(!deleted && keychain.state == nil, "Legacy read must not migrate before independent account verification")
    try flow.commit(opened.migrationID!, verifiedKey: mk, ticket: commitTicket)
    try expect(deleted, "Verified migration must delete legacy only after new readback")
    try expect(store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) == mk, "Migrated key must remain usable")
    try rejects { try flow.commit(opened.migrationID!, verifiedKey: mk, ticket: commitTicket) }
    print("PASS verified one-use migration")
} catch {
    print("FAIL verified one-use migration: \(error)")
    exit(1)
}
func fixture(_ name: String, _ body: (SharedBiometricUnlockFlow, SharedBiometricUnlock, Keychain, () -> Bool) throws -> Void) throws {
    let path = directory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    let storage = Keychain()
    let primitive = SharedBiometricUnlock(containerURL: path, accessGroup: "test.shared", keychain: storage)
    var deleted = false
    let migration = SharedBiometricUnlockFlow(store: primitive, legacyRead: { _ in mk }, legacyDelete: { deleted = true })
    try body(migration, primitive, storage, { deleted })
    print("PASS \(name)")
}
try fixture("wrong verified key never enrolls or deletes legacy") { flow, _, storage, deleted in
    let opened = try flow.unlock(readTicket, context: LAContext())
    try rejects { try flow.commit(opened.migrationID!, verifiedKey: Data(repeating: 4, count: 32), ticket: commitTicket) }
    try expect(storage.state == nil && !deleted(), "Unverified account key was migrated")
}
try fixture("cancellation consumes pending migration") { flow, _, storage, deleted in
    let opened = try flow.unlock(readTicket, context: LAContext())
    flow.cancel(opened.migrationID)
    try rejects { try flow.commit(opened.migrationID!, verifiedKey: mk, ticket: commitTicket) }
    try expect(storage.state == nil && !deleted(), "Cancelled migration wrote material")
}
try fixture("account or session replacement rejects verified old key") { flow, _, storage, deleted in
    let opened = try flow.unlock(readTicket, context: LAContext())
    let replacement = SharedBiometricTicket(profileBinding: profile, identityBinding: "new-session/account/v1", epoch: 3, validate: {})
    try rejects { try flow.commit(opened.migrationID!, verifiedKey: mk, ticket: replacement) }
    try expect(storage.state == nil && !deleted(), "Old migration crossed session boundary")
}
try fixture("readback failure retains legacy and denies new enrollment") { flow, primitive, storage, deleted in
    let opened = try flow.unlock(readTicket, context: LAContext())
    storage.onRead = { throw Failure.injected }
    try rejects { try flow.commit(opened.migrationID!, verifiedKey: mk, ticket: commitTicket) }
    try expect(!deleted(), "Legacy deleted without readback")
    try rejects { _ = try primitive.read(profileBinding: profile, context: LAContext(), validateOperation: {}) }
}
try fixture("source invalidation after authentication never deletes legacy") { flow, _, storage, deleted in
    var valid = true
    let opened = try flow.unlock(readTicket, context: LAContext())
    let guarded = SharedBiometricTicket(profileBinding: profile, identityBinding: readTicket.identityBinding, epoch: 2,
        validate: { if !valid { throw Failure.injected } })
    storage.onRead = { valid = false }
    try rejects { try flow.commit(opened.migrationID!, verifiedKey: mk, ticket: guarded) }
    try expect(!deleted(), "Stale session deleted legacy")
}
try fixture("shared enrollment never falls back to legacy on canceled auth") { flow, primitive, storage, _ in
    try primitive.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    storage.onRead = { throw Failure.injected }
    try rejects { _ = try flow.unlock(readTicket, context: LAContext()) }
}
try fixture("clear cancels pending capability and removes both stores") { flow, primitive, _, deleted in
    let opened = try flow.unlock(readTicket, context: LAContext())
    try flow.clear(commitTicket)
    try rejects { try flow.commit(opened.migrationID!, verifiedKey: mk, ticket: commitTicket) }
    try expect(deleted(), "Legacy survived successful clear")
    try expect(!primitive.isEnrolled(profileBinding: profile), "Shared envelope survived clear")
}
try fixture("explicit enrollment authenticates and verifies before legacy cleanup") { flow, primitive, storage, deleted in
    storage.onRead = { throw Failure.injected }
    try rejects { try flow.enroll(mk, ticket: commitTicket, authenticateBeforeWrite: { _ in }) }
    try expect(!deleted(), "Legacy deleted despite canceled enrollment authentication")
    try expect(!primitive.isEnrolled(profileBinding: profile), "Canceled enrollment remained active")
}
try fixture("clear attempts legacy deletion even if shared tombstone fails") { flow, _, storage, deleted in
    storage.failSave = true
    try rejects { try flow.clear(commitTicket) }
    try expect(deleted(), "Secondary cleanup skipped after shared storage failure")
}
try fixture("cancellation during commit readback removes own enrollment and retains legacy") { flow, primitive, storage, deleted in
    let opened = try flow.unlock(readTicket, context: LAContext())
    storage.onRead = { flow.cancel(opened.migrationID) }
    try rejects { try flow.commit(opened.migrationID!, verifiedKey: mk, ticket: commitTicket) }
    try expect(!deleted(), "Canceled in-flight commit deleted legacy")
    try expect(!primitive.isEnrolled(profileBinding: profile), "Canceled commit left its enrollment active")
}
try fixture("revoked shared state never downgrades to surviving legacy") { flow, primitive, _, _ in
    try primitive.revoke()
    try rejects { _ = try flow.unlock(readTicket, context: LAContext()) }
}
try fixture("another profile shared state never downgrades to legacy") { flow, primitive, _, _ in
    try primitive.enroll(masterKey: mk, profileBinding: String(repeating: "b", count: 64), validateOperation: {})
    try rejects { _ = try flow.unlock(readTicket, context: LAContext()) }
}
try fixture("prewrite authentication cancellation leaves both stores untouched") { flow, _, storage, deleted in
    do {
        try flow.enroll(mk, ticket: commitTicket, authenticateBeforeWrite: { _ in
            throw SharedBiometricFlowError.canceledWithoutChanges
        })
        throw Failure.assertion("Canceled enrollment succeeded")
    } catch SharedBiometricFlowError.canceledWithoutChanges {}
    try expect(storage.state == nil && storage.keys.isEmpty && !deleted(), "Prewrite cancellation changed persistent state")
}
try fixture("pending legacy capability cannot overwrite later tombstone") { flow, primitive, _, deleted in
    let opened = try flow.unlock(readTicket, context: LAContext())
    try primitive.revoke()
    try rejects { try flow.commit(opened.migrationID!, verifiedKey: mk, ticket: commitTicket) }
    try expect(!deleted(), "Revoked migration deleted surviving legacy")
    try expect(!primitive.isEnrolled(profileBinding: profile), "Migration resurrected tombstone")
}
try fixture("overlapping unlock invalidates the earlier authentication") { _, primitive, _, _ in
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let stateLock = NSLock()
    var reads = 0
    var firstRejected = false
    let concurrent = SharedBiometricUnlockFlow(store: primitive, legacyRead: { _ in
        stateLock.lock(); reads += 1; let first = reads == 1; stateLock.unlock()
        if first { entered.signal(); release.wait() }
        return mk
    }, legacyDelete: {})
    DispatchQueue.global().async {
        do { _ = try concurrent.unlock(readTicket, context: LAContext()) }
        catch { stateLock.lock(); firstRejected = true; stateLock.unlock() }
        finished.signal()
    }
    guard entered.wait(timeout: .now() + 5) == .success else { throw Failure.assertion("First prompt not entered") }
    let newest = try concurrent.unlock(readTicket, context: LAContext())
    release.signal()
    guard finished.wait(timeout: .now() + 5) == .success else { throw Failure.assertion("Old prompt did not finish") }
    stateLock.lock(); let rejected = firstRejected; stateLock.unlock()
    try expect(rejected, "Old authentication returned MK after replacement")
    try expect(newest.migrationID != nil, "Latest request lost migration capability")
    concurrent.cancel()
}
try fixture("background cancellation removes explicit enrollment after write") { flow, primitive, storage, deleted in
    storage.onRead = { flow.cancel() }
    try rejects { try flow.enroll(mk, ticket: commitTicket, authenticateBeforeWrite: { _ in }) }
    try expect(!primitive.isEnrolled(profileBinding: profile) && !deleted(), "Canceled explicit enrollment survived")
}
try fixture("old migration cleanup cannot revoke replacement source enrollment") { flow, primitive, storage, deleted in
    let opened = try flow.unlock(readTicket, context: LAContext())
    var valid = true
    let replacement = Data(repeating: 92, count: 32)
    let guarded = SharedBiometricTicket(profileBinding: profile, identityBinding: readTicket.identityBinding, epoch: 2,
        validate: { if !valid { throw Failure.injected } })
    storage.onRead = {
        valid = false
        try primitive.enroll(masterKey: replacement, profileBinding: profile, validateOperation: {})
    }
    try rejects { try flow.commit(opened.migrationID!, verifiedKey: mk, ticket: guarded) }
    try expect(primitive.read(profileBinding: profile, context: LAContext(), validateOperation: {}) == replacement,
        "Old cleanup revoked new source enrollment")
    try expect(!deleted(), "Old source deleted legacy")
}
