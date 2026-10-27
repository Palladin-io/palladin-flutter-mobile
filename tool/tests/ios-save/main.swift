import Foundation

func expect(_ value: Bool, _ message: String) {
    guard value else { fatalError(message) }
}
expect(PendingPasswordSave.exactOrigin("https://login.example.test/path") == "https://login.example.test", "accept exact HTTPS origin")
for input in ["example.test", "http://example.test", "https://a@example.test", "https://example.test:443", "https://*.example.test", "https://éxample.test", "https://example..test", " https://example.test", "https://example.test\\evil", "https://example.test."] {
    expect(PendingPasswordSave.exactOrigin(input) == nil, "reject unsafe origin")
}
print("iOS explicit save origin tests passed")

func rejected(_ message: String, _ body: () throws -> Void) {
    do { try body(); fatalError(message) } catch { }
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
var authority: PasswordSaveAuthority?
var clock: TimeInterval = 1000
var authentication: (() -> Void)?
let key = Data(repeating: 7, count: 32)
let store = PendingPasswordSave(container: directory, readAuthority: { authority },
    writeAuthority: { authority = $0 }, readKey: { _ in authentication?(); return key }, now: { clock })
let session = try store.activate(principal: "synthetic-account")
func stage(_ operation: PasswordSaveOperation = PasswordSaveOperation()) throws {
    _ = try store.stage(expectedSession: authority!.session, origin: "https://login.example.test", formSession: "synthetic-form",
        username: "synthetic-user", password: "synthetic-password", prompt: "Test", operation: operation)
}
try stage()
let id = try store.pending()!
let payload = try store.take(id: id, session: session, prompt: "Test")!
expect(payload.username == "synthetic-user" && payload.password == "synthetic-password", "roundtrip")
expect(try store.take(id: id, session: session, prompt: "Test") == nil, "one-time consume")
expect(try store.validate(payload.authority, session: session, domain: "login.example.test"), "valid consumed lease")
expect(!(try store.validate(payload.authority, session: session, domain: "other.example.test")), "origin mismatch")
try stage()
expect(!(try store.validate(payload.authority, session: session, domain: "login.example.test")), "replacement invalidates old consumed lease")
let wrongSession = try store.take(id: store.pending()!, session: "wrong", prompt: "Test")
expect(wrongSession == nil, "wrong session denied")
let ciphertextURL = directory.appendingPathComponent("pending-password-save-v1")
let saved = try Data(contentsOf: ciphertextURL)
var tampered = saved; tampered[0] ^= 1
try tampered.write(to: ciphertextURL)
rejected("tamper denied") { _ = try store.take(id: store.pending()!, session: session, prompt: "Test") }
try saved.write(to: ciphertextURL)
clock += 120
expect(try store.pending() == nil, "expiry removes pending")
clock = 2000
try stage()
clock = 1999
expect(try store.pending() == nil, "clock rollback denied")
clock = 3000
let cancelled = PasswordSaveOperation(); cancelled.cancel()
rejected("cancelled operation denied") { try stage(cancelled) }
authentication = { try! store.revoke() }
rejected("revoke during biometric denied") { try stage() }
authentication = nil
_ = try store.activate(principal: "synthetic-account")
let background = PasswordSaveOperation()
authentication = { background.cancel() }
rejected("background during biometric denied") { try stage(background) }
authentication = nil
try stage()
let original = authority!
authentication = { try! store.revoke(); _ = try! store.activate(principal: "different-account") }
rejected("account switch during biometric denied") { _ = try store.take(id: original.pending!.id, session: original.session, prompt: "Test") }
authentication = nil
expect(!(try store.validate(payload.authority, session: session, domain: "login.example.test")), "old consumed lease denied")
try store.revoke()
_ = try store.activate(principal: "synthetic-account")
expect(authority!.session != session, "restart rotates authority")
print("iOS explicit save ciphertext/lifecycle tests passed")

try stage()
let bound = authority!
let encrypted = try Data(contentsOf: ciphertextURL)
for changed in [
    PasswordSaveAuthority(principal: "substituted", session: bound.session, captureID: bound.captureID, pending: bound.pending),
    PasswordSaveAuthority(principal: bound.principal, session: "substituted", captureID: bound.captureID, pending: bound.pending),
    PasswordSaveAuthority(principal: bound.principal, session: bound.session, captureID: bound.captureID,
        pending: PasswordSaveBinding(id: bound.pending!.id, origin: "https://other.example.test",
            formSession: bound.pending!.formSession, created: 3000, expires: 3120)),
    PasswordSaveAuthority(principal: bound.principal, session: bound.session, captureID: bound.captureID,
        pending: PasswordSaveBinding(id: bound.pending!.id, origin: bound.pending!.origin,
            formSession: "different-form", created: 3000, expires: 3120))
] {
    authority = changed
    rejected("independent binding substitution denied") {
        _ = try store.take(id: changed.pending!.id, session: changed.session, prompt: "Test")
    }
}
authority = bound
try store.cancel()
try encrypted.write(to: ciphertextURL)
expect(try store.take(id: bound.pending!.id, session: bound.session, prompt: "Test") == nil, "replayed ciphertext denied after cancel")
try stage()
let previous = authority!
try stage()
let replacementID = try store.pending()
try store.discard(id: previous.pending!.id)
expect(try store.pending() == replacementID, "late old completion cannot delete replacement")
let cancelledConsume = PasswordSaveOperation()
authentication = { cancelledConsume.cancel() }
rejected("background during take denied") {
    _ = try store.take(id: replacementID!, session: authority!.session, prompt: "Test", operation: cancelledConsume)
}
authentication = nil
let unchanged = authority!
rejected("oversized password rejected") {
    _ = try store.stage(expectedSession: authority!.session, origin: "https://login.example.test", formSession: "form", username: "user",
        password: String(repeating: "x", count: 16385), prompt: "Test", operation: PasswordSaveOperation())
}
expect(authority == unchanged, "invalid capture cannot replace pending")
let originalID = authority!.pending!.id
let originalSession = authority!.session
let group = DispatchGroup()
let resultsLock = NSLock()
var consumedCount = 0
for _ in 0..<2 {
    group.enter()
    DispatchQueue.global().async {
        if let value = try? store.take(id: originalID, session: originalSession, prompt: "Test") {
            resultsLock.lock(); consumedCount += value.password == "synthetic-password" ? 1 : 0; resultsLock.unlock()
        }
        group.leave()
    }
}
group.wait()
expect(consumedCount == 1, "concurrent consume releases plaintext only once")
expect(!FileManager.default.fileExists(atPath: ciphertextURL.path), "ciphertext deleted before handoff")
print("iOS explicit save binding/replay/concurrency tests passed")

try stage()
let staged = authority!
var extensionCompleted = false
try store.completeStaging(id: staged.pending!.id, session: staged.session,
                         operation: PasswordSaveOperation()) { extensionCompleted = true }
expect(extensionCompleted, "extension completes only after durable encrypted staging")
expect(try store.pending() == staged.pending!.id, "extension completion leaves pending review, not consumed Entry")
try store.revoke()
_ = try store.activate(principal: "synthetic-account")
rejected("cold Runner restart cannot adopt previously staged capture") {
    try store.completeStaging(id: staged.pending!.id, session: staged.session,
                             operation: PasswordSaveOperation()) { fatalError("old request completed") }
}
expect(try store.take(id: staged.pending!.id, session: authority!.session, prompt: "Test") == nil,
       "cold restart discards pending password")
rejected("consent from previous login cannot bind to current login") {
    _ = try store.stage(expectedSession: staged.session, origin: "https://login.example.test",
        formSession: "synthetic-form", username: "synthetic-user", password: "synthetic-password",
        prompt: "Test", operation: PasswordSaveOperation())
}
print("iOS explicit save staged completion/restart tests passed")

try stage()
let cancelledID = authority!.pending!.id
try stage()
let surviving = authority!
// Models a cancelled Dart take finishing after the OS has staged another request.
try store.cancel(id: cancelledID)
expect(authority == surviving, "late id-scoped cancellation must preserve replacement authority")
expect(try store.pending() == surviving.pending!.id, "late id-scoped cancellation must preserve replacement ciphertext")
let replacement = try store.take(id: surviving.pending!.id, session: surviving.session, prompt: "Test")!
try store.cancel(id: cancelledID)
expect(try store.validate(replacement.authority, session: surviving.session, domain: "login.example.test"),
       "late cancellation must preserve newer consumed lease")
try store.cancel(id: surviving.pending!.id)
expect(!(try store.validate(replacement.authority, session: surviving.session, domain: "login.example.test")),
       "matching cancellation must revoke consumed lease")
try stage()
let pendingCancelID = authority!.pending!.id
try store.cancel(id: pendingCancelID)
expect(try store.pending() == nil, "matching cancellation must remove pending ciphertext")
expect(!FileManager.default.fileExists(atPath: ciphertextURL.path), "cancel removes matching ciphertext")
print("iOS explicit save scoped cancellation tests passed")
