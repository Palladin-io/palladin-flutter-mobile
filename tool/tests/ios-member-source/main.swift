import Foundation

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func rejects(_ operation: () throws -> Void) {
    do { try operation(); fatalError("expected rejection") } catch {}
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: directory) }
var durable: Data?
var failWrite = false
let fence = SharedMemberSourceFence(
    containerURL: directory,
    readState: { durable },
    writeState: { value in
        if failWrite { throw CocoaError(.fileWriteNoPermission) }
        durable = value
    }
)
let claims = try SharedMemberSourceClaims(arguments: [
    "principalId":"member", "organizationId":"org",
    "organizationMembershipGeneration":"1", "offlinePolicy":"24h", "offlinePolicyVersion":1
])
let unlock: [String:Any] = [
    "accountId":"member", "encryptedPrivateKey":"synthetic-ciphertext",
    "kdf":["securityVersion":1,"minimumSecurityVersion":1,
           "profileId":"identity-argon2id-password-v1", "kdfSalt":"synthetic-salt",
           "credentialRevision":1,"privateKeyWrapRevision":1]
]
let profile = String(repeating:"a",count:64)
let first = try fence.beginSession(sessionID:"one", profileBinding:profile, claims:claims, accountUnlock:unlock)
expect(first.state == .quarantined, "initial generation must deny")
rejects { _ = try fence.withCurrentSource(first, requireActive:true) {} }
try fence.activate(first)
rejects { try fence.withCurrentSource(first, requireActive:false, requireQuarantined:true) {} }
let active = try fence.current()
try fence.withCurrentSource(active, requireActive:true) {}
fence.invalidateSession("one")
// App process RAM cancellation cannot erase provider source after fresh auth.
try fence.withCurrentSource(active, requireActive:true) {}
rejects { try fence.requireAppSession("one") }
let invalidated = try fence.invalidate(active)
expect(invalidated.epoch > active.epoch, "invalidation must advance epoch")
rejects { try fence.withCurrentSource(active, requireActive:true) {} }
rejects { try fence.activate(first) }
// A new live app owner begins its own source session after ordinary lock.
let live = try fence.beginSession(sessionID:"live", profileBinding:profile, claims:claims, accountUnlock:unlock)
try fence.activate(live)
let replacement = try fence.current()
failWrite = true
rejects { _ = try fence.invalidate(replacement) }
try fence.withCurrentSource(replacement, requireActive:true) {}
failWrite = false
try fence.revoke(replacement)
rejects { try fence.withCurrentSource(replacement, requireActive:true) {} }
let other = try fence.beginSession(sessionID:"two", profileBinding:String(repeating:"b",count:64), claims:claims, accountUnlock:unlock)
rejects { try fence.activate(invalidated) }
rejects { try fence.revoke(replacement) }
try fence.activate(other)
// Corrupt protected state never becomes an empty, usable generation.
durable = Data("{}".utf8)
rejects { _ = try fence.current() }
rejects { _ = try fence.beginSession(sessionID:"three", profileBinding:profile, claims:claims, accountUnlock:unlock) }
print("PASS shared Member source lifecycle and persistence failures")

// Separate store instances must share handoff/invalidation ordering.
durable = nil
let secondFence = SharedMemberSourceFence(containerURL: directory, readState: { durable }, writeState: { durable = $0 })
let ordered = try fence.beginSession(sessionID:"ordered", profileBinding:profile, claims:claims, accountUnlock:unlock)
try fence.activate(ordered)
let handoffEntered = DispatchSemaphore(value:0)
let releaseHandoff = DispatchSemaphore(value:0)
let handoffEnded = DispatchSemaphore(value:0)
let invalidationEnded = DispatchSemaphore(value:0)
DispatchQueue.global().async {
    try! fence.withCurrentSource(ordered, requireActive:true) {
        handoffEntered.signal(); releaseHandoff.wait()
    }
    handoffEnded.signal()
}
expect(handoffEntered.wait(timeout:.now()+2) == .success,"handoff must enter")
DispatchQueue.global().async { _ = try! secondFence.invalidate(ordered); invalidationEnded.signal() }
expect(invalidationEnded.wait(timeout:.now()+0.05) == .timedOut,"invalidation cannot overtake admitted handoff")
releaseHandoff.signal()
expect(handoffEnded.wait(timeout:.now()+2) == .success,"handoff must finish")
expect(invalidationEnded.wait(timeout:.now()+2) == .success,"invalidation must finish")
rejects { try fence.withCurrentSource(ordered, requireActive:true) {} }
let currentDenied = try fence.current()
try fence.revoke(currentDenied)
rejects { try fence.activate(currentDenied) }
// A structurally valid JSON envelope with mismatched account binding is denied.
let newSource = try fence.beginSession(sessionID:"latest", profileBinding:profile, claims:claims, accountUnlock:unlock)
var decoded = try JSONSerialization.jsonObject(with: durable!) as! [String:Any]
var wrongClaims = decoded["claims"] as! [String:Any]; wrongClaims["principalId"] = "different"
decoded["claims"] = wrongClaims
durable = try JSONSerialization.data(withJSONObject:decoded)
rejects { try fence.withCurrentSource(newSource, requireActive:false) {} }
print("PASS cross-instance handoff linearization and protected-account binding")

// Cold logout has no process-local session capability and uses protected CAS.
durable = nil
let coldSource = try fence.beginSession(sessionID:"cold", profileBinding:profile, claims:claims, accountUnlock:unlock)
try fence.activate(coldSource)
rejects { try secondFence.requireAppSession("cold") }
try secondFence.withCurrentSource(coldSource, requireActive:true) {}
let coldSnapshot = try secondFence.sourceSnapshot()!
let nextAccount = try fence.beginSession(sessionID:"new-account", profileBinding:String(repeating:"c",count:64), claims:claims, accountUnlock:unlock)
rejects { _ = try secondFence.revokeSource(sourceEpoch:coldSnapshot.sourceEpoch, profileDigest:coldSnapshot.profileDigest) }
let currentSnapshot = try secondFence.sourceSnapshot()!
let deniedEpoch = try secondFence.revokeSource(sourceEpoch:currentSnapshot.sourceEpoch, profileDigest:currentSnapshot.profileDigest)
expect(deniedEpoch > nextAccount.epoch,"cold revoke must advance")
let coldDenied = try fence.current()
expect(coldDenied.state == .quarantined,"cold revoke must persist deny")
rejects { try fence.withCurrentSource(nextAccount,requireActive:true) {} }
durable = Data("{}".utf8)
rejects { _ = try secondFence.sourceSnapshot() }
print("PASS cold protected snapshot CAS without app-session restoration")
