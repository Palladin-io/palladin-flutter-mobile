import Foundation
import CryptoKit

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    guard (try! condition()) else { fatalError(message) }
}
func rejects(_ operation: () throws -> Void) {
    do { try operation(); fatalError("Expected rejection") } catch {}
}
let now = Date(timeIntervalSince1970: 1_800_000_000)
let formatter = ISO8601DateFormatter()
func manifest(_ revisions: [String: String], issued: Date = now) -> [String: Any] {
    ["principalId": "member", "organizationId": "org", "organizationMembershipGeneration": "1",
     "offlinePolicy": "1h", "offlinePolicyVersion": 1, "vaults": [[
        "vaultId": "vault", "contextVersion": 1, "memberId": "member", "memberKeyGeneration": 1,
        "vaultKeyVersion": 1, "memberRecipientKeyVersion": 1, "memberRecipientKeyFingerprint": "synthetic",
        "issuedAt": formatter.string(from: issued), "notAfter": formatter.string(from: issued.addingTimeInterval(3600)),
        "entries": revisions.keys.sorted().map { ["entryId": $0, "revision": revisions[$0]!, "keyVersion": 1] as [String: Any] }
     ]]]
}
func record(_ id: String, revision: String = "1") -> [String: Any] {
    ["id": id, "organizationId": "org", "vaultId": "vault", "revision": revision, "keyVersion": 1,
     "label": "Synthetic", "username": "synthetic", "password": "synthetic-only", "domains": ["example.invalid"]]
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let engine = AutoFillV3Engine(directory: directory)
var key = Data(repeating: 7, count: 32)
defer { key.resetBytes(in: 0..<key.count) }
let revisions = Dictionary(uniqueKeysWithValues: (0..<160).map { ("entry-\($0)", "1") })
let full = try engine.full(payload: ["version": 3, "manifest": manifest(revisions), "records": revisions.keys.sorted().map { record($0) }], generation: 1, keyID: UUID().uuidString.lowercased(), key: key, now: now)
expect(engine.recordEncryptions == 160, "Full record count")
let unchanged = full.entries.filter { $0.key != "vault:entry-0" }.mapValues { $0.bodyID }
var changed = revisions; changed["entry-0"] = "2"
let next = try engine.delta(catalog: full, manifest: manifest(changed), upserts: [record("entry-0", revision: "2")], removals: [], releasingDenies: [], key: key, now: now)
expect(engine.recordEncryptions == 161 && engine.recordDecryptions == 0, "Delta must not decrypt unchanged records")
expect(next.entries.filter { $0.key != "vault:entry-0" }.mapValues { $0.bodyID } == unchanged, "Unchanged ciphertext references preserved")
var removed = changed; removed.removeValue(forKey: "entry-0")
let deleted = try engine.delta(catalog: next, manifest: manifest(removed), upserts: [], removals: [["vaultId": "vault", "entryId": "entry-0"]], releasingDenies: [], key: key, now: now)
expect(deleted.entries.count == 159 && engine.recordEncryptions == 161 && engine.recordDecryptions == 0, "Delete opens no bodies")
rejects { _ = try engine.delta(catalog: next, manifest: manifest(changed), upserts: [], removals: [], releasingDenies: [], key: key, now: now.addingTimeInterval(3600)) }
print("iOS incremental core tests passed")

// A foreground repair may deny the whole snapshot before discovering one change.
let allCoordinates = revisions.keys.sorted().map { ["vaultId": "vault", "entryId": $0] }
let allDenied = try engine.deny(catalog: full, entries: allCoordinates, now: now)
let encryptionsBeforeRepair = engine.recordEncryptions
let repaired = try engine.delta(catalog: allDenied.catalog, manifest: manifest(changed), upserts: [record("entry-0", revision: "2")], removals: [], releasingDenies: [allDenied.token], key: key, now: now)
expect(repaired.denies.isEmpty && repaired.identities.count == 160, "Complete current authority reconciles an owned whole-snapshot deny")
expect(repaired.entries.filter { $0.key != "vault:entry-0" }.mapValues { $0.bodyID } == unchanged, "Repair preserves all 159 unchanged ciphertext bodies")
expect(engine.recordEncryptions == encryptionsBeforeRepair + 1 && engine.recordDecryptions == 0, "Repair encrypts one changed body and decrypts no unchanged bodies")
var missingRetained = changed; missingRetained.removeValue(forKey: "entry-1")
rejects { _ = try engine.delta(catalog: allDenied.catalog, manifest: manifest(missingRetained), upserts: [record("entry-0", revision: "2")], removals: [], releasingDenies: [allDenied.token], key: key, now: now) }
var changedRetained = changed; changedRetained["entry-1"] = "2"
rejects { _ = try engine.delta(catalog: allDenied.catalog, manifest: manifest(changedRetained), upserts: [record("entry-0", revision: "2")], removals: [], releasingDenies: [allDenied.token], key: key, now: now) }
rejects { _ = try engine.delta(catalog: allDenied.catalog, manifest: manifest(changed, issued: now.addingTimeInterval(3600)), upserts: [record("entry-0", revision: "2")], removals: [], releasingDenies: [allDenied.token], key: key, now: now.addingTimeInterval(3600)) }
rejects { _ = try engine.delta(catalog: allDenied.catalog, manifest: manifest(changed), upserts: [record("entry-0", revision: "2")], removals: [], releasingDenies: ["unknown"], key: key, now: now) }


// Persistent catalog authentication, scoped denials and immutable leases.
let pointer = try engine.persist(next, revision: 1, key: key)
let reopened = try engine.open(pointer, key: key, now: now)
expect(reopened.entries.count == 160, "Catalog round trip")
let firstDeny = try engine.deny(catalog: reopened, entries: [["vaultId": "vault", "entryId": "entry-0"]], now: now)
let secondDeny = try engine.deny(catalog: firstDeny.catalog, entries: [["vaultId": "vault", "entryId": "entry-0"]], now: now)
expect(secondDeny.catalog.identities.count == 159, "Denied identity hidden")
let releasedOne = try engine.delta(catalog: secondDeny.catalog, manifest: manifest(changed), upserts: [record("entry-0", revision: "2")], removals: [], releasingDenies: [firstDeny.token], key: key, now: now)
expect(releasedOne.identities.count == 159 && releasedOne.denies.count == 1, "Another owner remains denied")
let reconciledRetained = try engine.delta(catalog: firstDeny.catalog, manifest: manifest(changed), upserts: [], removals: [], releasingDenies: [firstDeny.token], key: key, now: now)
expect(reconciledRetained.denies.isEmpty, "Unchanged owned entry can reconcile against complete current authority")
let absentOwner = try engine.deny(catalog: reopened, entries: [["vaultId": "vault", "entryId": "absent"]], now: now)
rejects { _ = try engine.delta(catalog: absentOwner.catalog, manifest: manifest(changed), upserts: [], removals: [], releasingDenies: [absentOwner.token], key: key, now: now) }
rejects { _ = try engine.delta(catalog: reopened, manifest: manifest(changed), upserts: [], removals: [], releasingDenies: ["unknown"], key: key, now: now) }
let renewed = try engine.delta(catalog: reopened, manifest: manifest(changed, issued: now.addingTimeInterval(60)), upserts: [], removals: [], releasingDenies: [], key: key, now: now.addingTimeInterval(60))
expect(renewed.entries.values.allSatisfy { $0.notAfter == now.addingTimeInterval(3600) }, "Renewal cannot extend retained record expiry")
var wrongHead = changed; wrongHead["entry-1"] = "99"
rejects { _ = try engine.delta(catalog: reopened, manifest: manifest(wrongHead), upserts: [], removals: [], releasingDenies: [], key: key, now: now) }
let allRemoved = reopened.entries.keys.map { ["vaultId": "vault", "entryId": String($0.dropFirst("vault:".count))] }
let empty = try engine.delta(catalog: reopened, manifest: manifest([:]), upserts: [], removals: allRemoved, releasingDenies: [], key: key, now: now)
let emptyPointer = try engine.persist(empty, revision: 2, key: key)
expect(try engine.open(emptyPointer, key: key, now: now).entries.isEmpty, "Empty acknowledged catalog is valid")
rejects { _ = try engine.open(pointer, key: Data(repeating: 9, count: 32), now: now) }
rejects { _ = try engine.open(AutoFillV3Pointer(base: pointer.base, keyID: pointer.keyID, catalogID: UUID().uuidString.lowercased(), digest: pointer.digest), key: key, now: now) }
engine.fault = { stage in if stage == "catalogDurable" { throw AutoFillV3Error.invalid } }
rejects { _ = try engine.persist(empty, revision: 3, key: key) }
engine.fault = nil
expect(try engine.open(pointer, key: key, now: now).entries.count == 160, "Failed publication preserves previous pointer/files")
rejects { _ = try engine.open(pointer, key: key, now: now.addingTimeInterval(3600)) }
expect(try engine.open(pointer, key: key, now: now.addingTimeInterval(3600), allowExpired: true).entries.count == 160, "Full replacement can authenticate expired ownership only")

let writer = AutoFillV3Writer()
let epoch = try writer.begin(generation: 1)
try writer.install(key: key, keyID: pointer.keyID, epoch: epoch, generation: 1)
writer.end(epoch: epoch)
rejects { _ = try writer.openingMaterial(epoch: epoch, generation: 1) }
rejects { _ = try writer.withCurrent(epoch: epoch, generation: 1) { fatalError("Locked writer committed") } }
let newerEpoch = try writer.begin(generation: 1)
try writer.install(key: key, keyID: pointer.keyID, epoch: newerEpoch, generation: 1)
writer.end(epoch: epoch)
expect(try writer.openingMaterial(epoch: newerEpoch, generation: 1).key.count == 32, "Stale end cannot wipe newer writer")
writer.invalidate()
rejects { _ = try writer.openingMaterial(epoch: newerEpoch, generation: 1) }

// Exact lease and cache revision still guard an already-open picker.
let credential = try engine.records(reopened, key: key, now: now)[0]
let lease = AutoFillCredentialLease(record: credential.0, notAfter: credential.1, generation: 1, cacheId: pointer.cacheID, maximumObservedWallTime: now)
rejects { try AutoFillCredentialUseGuard.validate(lease, serviceIdentifiers: [.init(identifier: "example.invalid", type: .domain)], now: now, currentCounter: 1, currentFence: .init(generation: 1, state: .active, cacheId: emptyPointer.cacheID)) }
rejects { try AutoFillCredentialUseGuard.validate(lease, serviceIdentifiers: [.init(identifier: "example.invalid", type: .domain)], now: now.addingTimeInterval(3600), currentCounter: 1, currentFence: .init(generation: 1, state: .active, cacheId: pointer.cacheID)) }

// Identity updates preserve unchanged suggestions and never clear a newer revision.
let identityChange = try AutoFillV3IdentityChange(current: deleted.identities, previous: reopened.identities)
expect(identityChange.all.count == 159 && identityChange.removed.count == 1 && identityChange.saved.isEmpty, "Identity deletion projection")
var operations: [String] = []
var completionError: Error?
AutoFillV3IdentityUpdater.update(change: identityChange, hasPrevious: true, isCurrent: { true }, state: { $0(false) },
    remove: { _, _ in fatalError("Unexpected remove") }, save: { _, _ in fatalError("Unexpected save") },
    replace: { values, done in operations.append("replace-\(values.count)"); done(true, nil) }, completion: { completionError = $0 })
expect(operations == ["replace-159"] && completionError == nil, "Fallback publishes complete identities")
var currentRevision = true
var pendingRemoval: ((Bool, Error?) -> Void)?
AutoFillV3IdentityUpdater.update(change: identityChange, hasPrevious: true, isCurrent: { currentRevision }, state: { $0(true) },
    remove: { _, callback in pendingRemoval = callback }, save: { _, _ in fatalError("Stale identity callback saved") },
    replace: { _, _ in fatalError("Stale identity callback replaced") }, completion: { completionError = $0 })
currentRevision = false
pendingRemoval?(true, nil)
expect(completionError != nil, "Stale callback cannot acknowledge readiness")
print("iOS incremental denial, lease, writer, persistence and identity regressions passed")

func requiresRecovery(_ operation: () throws -> Void) {
    do { try operation(); fatalError("Expected typed recovery") }
    catch AutoFillV3Error.recoveryRequired {} catch { fatalError("Incorrect recovery classification") }
}
requiresRecovery { _ = try engine.open(pointer, key: key, now: now.addingTimeInterval(3600)) }
requiresRecovery { _ = try engine.open(AutoFillV3Pointer(base: pointer.base, keyID: pointer.keyID, catalogID: UUID().uuidString.lowercased(), digest: pointer.digest), key: key, now: now) }
let damagedBody = reopened.entries["vault:entry-1"]!
let damagedURL = directory.appendingPathComponent("palladin_autofill_v3_1_\(damagedBody.bodyID)")
try Data([0]).write(to: damagedURL)
requiresRecovery { _ = try engine.delta(catalog: reopened, manifest: manifest(changed), upserts: [], removals: [], releasingDenies: [], key: key, now: now) }
print("iOS incremental typed recovery tests passed")

let identityAcknowledgement = AutoFillV3IdentityAcknowledgement()
let identityBase = AutoFillV3Base(generation: 1, revision: 3)
expect(!identityAcknowledgement.canApplyDelta(to: identityBase), "Missing OS acknowledgement forces full metadata repair")
identityAcknowledgement.set(.init(generation: 1, revision: 2))
expect(identityAcknowledgement.canApplyDelta(to: identityBase), "Exact acknowledged predecessor allows identity delta")
expect(!identityAcknowledgement.canApplyDelta(to: .init(generation: 2, revision: 3)), "Other generation cannot authorize identity delta")
identityAcknowledgement.set(nil)
expect(!identityAcknowledgement.canApplyDelta(to: identityBase), "Failed OS mutation forces full metadata repair")

let emptyOwner = try engine.deny(catalog: empty, entries: [], now: now)
expect(emptyOwner.catalog.denies[emptyOwner.token] == [], "Empty scoped deny still issues an owned CAS token")
let emptyReleased = try engine.delta(catalog: emptyOwner.catalog, manifest: manifest([:]), upserts: [], removals: [], releasingDenies: [emptyOwner.token], key: key, now: now)
expect(emptyReleased.denies.isEmpty, "Matching empty owner can be released")
rejects { _ = try engine.delta(catalog: emptyOwner.catalog, manifest: manifest([:]), upserts: [], removals: [], releasingDenies: ["other-owner"], key: key, now: now) }

let scopedWriter = AutoFillV3Writer()
let scopedEpoch = try scopedWriter.begin(generation: 9)
try scopedWriter.install(key: key, keyID: pointer.keyID, epoch: scopedEpoch, generation: 9)
scopedWriter.invalidate(generation: 8)
expect(try scopedWriter.openingMaterial(epoch: scopedEpoch, generation: 9).key.count == 32, "Delayed clear for an old generation preserves current writer")
scopedWriter.invalidate(generation: 9)
rejects { _ = try scopedWriter.openingMaterial(epoch: scopedEpoch, generation: 9) }
