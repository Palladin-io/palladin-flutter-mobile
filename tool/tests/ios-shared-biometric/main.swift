import Foundation
import LocalAuthentication

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure.failed(message) }
}
enum TestFailure: Error { case failed(String), injected }
func rejects(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw TestFailure.failed("Expected rejection")
}
final class MemoryKeychain: SharedBiometricUnlockKeychain {
    var state: Data?
    var keys: [String: Data] = [:]
    var onRead: (() throws -> Void)?
    var onStore: (() throws -> Void)?
    var onDelete: (() throws -> Void)?
    var failSave = false
    func loadState() throws -> Data? { state }
    func saveState(_ data: Data) throws {
        if failSave { throw TestFailure.injected }
        state = data
    }
    func storeWrappingKey(_ data: Data, id: String) throws {
        keys[id] = data
        try onStore?()
    }
    func readWrappingKey(id: String, context: LAContext) throws -> Data {
        guard let value = keys[id] else { throw TestFailure.injected }
        let callback = onRead; onRead = nil
        try callback?()
        return value
    }
    func deleteWrappingKey(id: String) throws {
        let callback = onDelete; onDelete = nil
        try callback?()
        keys.removeValue(forKey: id)
    }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let profile = String(repeating: "a", count: 64)
let other = String(repeating: "b", count: 64)
let mk = Data((0..<32).map(UInt8.init))
let nextMK = Data(repeating: 91, count: 32)
var count = 0
func test(_ name: String, _ body: (SharedBiometricUnlock, MemoryKeychain) throws -> Void) throws {
    let directory = root.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let keychain = MemoryKeychain()
    let store = SharedBiometricUnlock(containerURL: directory, accessGroup: "test.shared", keychain: keychain)
    try body(store, keychain)
    count += 1
    print("PASS \(name)")
}
try test("encrypted round trip") { store, keychain in
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    try expect(keychain.state!.range(of: mk) == nil && keychain.state!.range(of: Data(mk.base64EncodedString().utf8)) == nil, "MK persisted in state")
    try expect(!keychain.keys.values.contains(mk), "MK used as wrapping key")
    try expect(store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) == mk, "Roundtrip failed")
}
try test("enrollment status never requests biometric key") { store, keychain in
    try expect(!store.isEnrolled(profileBinding: profile), "Missing enrollment reported")
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    keychain.onRead = { throw TestFailure.injected }
    try expect(store.isEnrolled(profileBinding: profile), "Current enrollment missing")
    try expect(!store.isEnrolled(profileBinding: other), "Other account exposed")
    try store.revoke()
    try expect(!store.isEnrolled(profileBinding: profile), "Revoked enrollment reported")
}
try test("account mismatch and bad profile input denied") { store, _ in
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    try rejects { _ = try store.read(profileBinding: other, context: LAContext(), validateOperation: {}) }
    try rejects { try store.enroll(masterKey: mk, profileBinding: "", validateOperation: {}) }
    try rejects { try store.enroll(masterKey: Data(), profileBinding: profile, validateOperation: {}) }
}
try test("revoke during biometric authorization denies late plaintext") { store, keychain in
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    keychain.onRead = { try store.revoke() }
    try rejects { _ = try store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) }
    try rejects { _ = try store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) }
}
try test("reenrollment during authorization denies old result") { store, keychain in
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    keychain.onRead = { try store.enroll(masterKey: nextMK, profileBinding: profile, validateOperation: {}) }
    try rejects { _ = try store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) }
    try expect(store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) == nextMK, "New enrollment lost")
}
try test("revocation before enrollment commit rejects late enrollment") { store, keychain in
    keychain.onStore = { keychain.onStore = nil; try store.revoke() }
    try rejects { try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {}) }
    try rejects { _ = try store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) }
    try expect(keychain.keys.isEmpty, "Candidate key leaked")
}
try test("failed state commit preserves previous unlock") { store, keychain in
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    keychain.failSave = true
    try rejects { try store.enroll(masterKey: nextMK, profileBinding: profile, validateOperation: {}) }
    keychain.failSave = false
    try expect(store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) == mk, "Previous enrollment lost")
    try expect(keychain.keys.count == 1, "Unpublished candidate retained")
}
try test("failed old key cleanup denies own newly committed enrollment") { store, keychain in
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    keychain.onDelete = { throw TestFailure.injected }
    try rejects { try store.enroll(masterKey: nextMK, profileBinding: profile, validateOperation: {}) }
    try rejects { _ = try store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) }
}
try test("failed cleanup and tombstone still delete candidate key") { store, keychain in
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    keychain.onDelete = { keychain.failSave = true; throw TestFailure.injected }
    try rejects { try store.enroll(masterKey: nextMK, profileBinding: profile, validateOperation: {}) }
    keychain.failSave = false
    try rejects { _ = try store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) }
}
try test("cleanup failure cannot overwrite a newer enrollment") { store, keychain in
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    keychain.onDelete = {
        try store.enroll(masterKey: nextMK, profileBinding: profile, validateOperation: {})
        throw TestFailure.injected
    }
    try rejects { try store.enroll(masterKey: Data(repeating: 31, count: 32), profileBinding: profile, validateOperation: {}) }
    try expect(store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) == nextMK, "Newer enrollment overwritten")
}
try test("tampered envelope and corrupt state fail closed") { store, keychain in
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    var object = try JSONSerialization.jsonObject(with: keychain.state!) as! [String: Any]
    var envelope = object["envelope"] as! [String: Any]
    envelope["profileBinding"] = other
    object["envelope"] = envelope
    keychain.state = try JSONSerialization.data(withJSONObject: object)
    try rejects { _ = try store.read(profileBinding: other, context: LAContext(), validateOperation: {}) }
    keychain.state = Data("broken".utf8)
    try rejects { try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {}) }
}
try test("cancel and operation invalidation release no key") { store, keychain in
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    keychain.onRead = { throw TestFailure.injected }
    try rejects { _ = try store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) }
    var valid = true
    keychain.onRead = { valid = false }
    try rejects { _ = try store.read(profileBinding: profile, context: LAContext(), validateOperation: { if !valid { throw TestFailure.injected } }) }
}
try test("persisted enrollment is bound to signed access group") { store, keychain in
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    let sameGroup = SharedBiometricUnlock(containerURL: root, accessGroup: "test.shared", keychain: keychain)
    try expect(sameGroup.read(profileBinding: profile, context: LAContext(), validateOperation: {}) == mk, "Persisted state cannot reopen")
    let wrongGroup = SharedBiometricUnlock(containerURL: root, accessGroup: "other.flavor", keychain: keychain)
    try rejects { _ = try wrongGroup.read(profileBinding: profile, context: LAContext(), validateOperation: {}) }
}
try test("stale revocation cannot destroy newer enrollment") { store, _ in
    try store.enroll(masterKey: nextMK, profileBinding: profile, validateOperation: {})
    try rejects { try store.revoke(validateOperation: { throw TestFailure.injected }) }
    try expect(store.read(profileBinding: profile, context: LAContext(), validateOperation: {}) == nextMK, "Stale revoke destroyed current key")
}
try test("revocation persistence failure is surfaced") { store, keychain in
    try store.enroll(masterKey: mk, profileBinding: profile, validateOperation: {})
    keychain.failSave = true
    try rejects { try store.revoke() }
}
print("Shared biometric tests passed: \(count)")
