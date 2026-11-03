# Incremental native AutoFill cache — proposed design

Status: design proposal, not implemented. Android and iOS implementation/tests are in scope; only Android Internal Testing may be published. This is independent of the lease-renewal fix in PR 152 and preparation-progress UI.

## Problem and evidence

The current Flutter publisher reveals every eligible Entry, then publishes one encrypted native payload. Each preparation clears the previous native payload first. S22 diagnostics measured roughly 300 ms per reveal and hundreds of reveals, leaving the provider unavailable during preparation. Success immediately followed by a new preparation has been observed; the exact repeat trigger is still under investigation and must not be called an infinite loop without evidence.

Android `AutoFillCacheStore.replace` creates a random AES key and RSA-wraps it with the biometric Keystore public key. iOS `AutoFillCacheStore.replace` creates a random AES key and stores it under `biometryCurrentSet` Keychain protection. Both encrypt one JSON payload containing all credential records and their authority. Reading the existing key requires biometric authorization. Neither platform can safely merge a delta into that existing ciphertext without opening the old payload.

## Choice

Use independently authenticated encrypted credential records and a small encrypted catalog. Retain only a dedicated native writer key/capability in app-process memory during the current unlocked session. It is unrelated to MK/VK/private keys, is never returned to Flutter, and lives in an app-bridge-only holder with a separate native writer epoch. Ordinary lock synchronously invalidates that epoch and wipes the holder without revoking the provider read generation. Pending encryption and commits recheck the writer epoch immediately before the fence commit. Provider APIs never consult the holder and always retrieve their opening key through the existing biometric path. Logout/session replacement also invalidate the writer epoch. Persistent opening-key protection and provider biometric authorization remain unchanged.

Rejected approaches:

- Read/merge/re-encrypt the existing v2 blob: requires biometric key access and decrypts every credential, defeating the requirement.
- Persist an unprotected writer key: violates the biometric cache boundary.
- Introduce a new iOS asymmetric key-wrapping scheme to permit writes without an in-memory key: larger cryptographic/platform migration than required for unlocked-session edits.

## Storage and authority

The v3 catalog contains the complete current independent profile/Vault authority and opaque Entry identifiers, revisions, key versions, ciphertext references/digests, denial state and the identity projection needed by the OS identity store (username/domain/record identifier). It is AES-GCM encrypted; labels, usernames, passwords, domains and plaintext authority are not added to persistent metadata. Each credential record is separately AEAD-encrypted and bound to its profile, organization, Vault, Entry, content revision/key version and lease. Record references are generated internally, never accepted as filesystem paths from the bridge.

The existing authenticated durable fence gains a monotonic catalog revision and catalog ciphertext digest. Write immutable new record and catalog files, fsync each and the containing directory, then CAS one atomically replaced authenticated fence pointer as the commit point. Hold the current native mutation lock and, on iOS, the existing cross-process flock for the CAS and handoff checks. Retain every old referenced file until the pointer commit is durable; orphan garbage collection runs afterward. A crash before pointer commit leaves the old authorized catalog; a crash after it selects only the new catalog. Denial transactions use the same durable commit point.

Native opening-key access continues to require biometric authorization. A provider decrypts catalog metadata after authentication, then opens selected records. Existing chooser code may initially decrypt candidate records after authentication; this does not authorize app-side rebuilds to decrypt unchanged records. Final handoff checks current generation, catalog revision, clock/lease, denial state and exact existing origin/package rules under the same mutation lock.

## Full publication and updates

Full publication remains required for first setup, missing/corrupt/expired native state, lost writer capability, unsupported v2 format and authority/key transitions that cannot retain existing records. A v2 cache is never treated as a partial v3 base. It can remain usable under its existing lease until an explicitly required invalidation; switching formats needs an atomic complete v3 publication.

A successful full publication returns an opaque base revision. Incremental publication requires that exact base generation/revision, the complete independently authenticated current authority, changed credential records and explicit removals. Native code authenticates the base and rejects stale, unavailable, expired or quarantined bases. It retains unchanged ciphertext only when the complete current independently authenticated eligibility/membership/revision/key mapping matches. Retained records keep their original AAD and original lease; current catalog authority cannot rebind them or extend their authorization. Effective expiry is no later than both the original record lease and current authority lease. A changed cryptographic scope/key binding requires a replacement record or full recovery. No delta is ever accepted as an empty initial snapshot. A missing base produces a typed recovery-required result and starts explicit full recovery through existing session/fence gates.

Dart retains value-free published revision/index metadata, never the complete plaintext credential list or a key. A committed local change is compared against that acknowledged base: only new/changed Entries are revealed and sent. Deleted, archived, policy-disabled and no-longer-eligible entries become explicit removals. If the complete changed set is unavailable or ambiguous, use authoritative repair; do not guess from notifications.

## Immediate mutation safety

Current `AutoFillMutationNotifier` signals have no Entry scope and all mutations clear the cache. Add explicit scope at known canonical Entry create/update/delete callers; preserve global invalidation for unknown scope, Vault removal/rotation, membership or organization policy changes.

Before an edit/delete remote mutation starts, atomically persist denial of the affected Entry and advance catalog revision. Other valid entries remain available. Old choosers become stale through their catalog revision, so even previously decrypted affected credentials cannot be released. A failed or ambiguous mutation retains its deny until authoritative reconciliation. Concurrent mutations have separate ownership and cannot clear each other's denies.

If the writer capability is absent, a scoped denial cannot be safely committed: fall back to the existing global durable deny, rather than letting the remote mutation begin while an affected native record remains usable. If persisting that global fallback fails, abort the remote mutation. Lock wipes writer capability but does not remove the existing policy allowing biometric provider use; logout/revoke continues to commit the global deny immediately.

## iOS identity publication

Read `ASCredentialIdentityStore.getState` and use `supportsIncrementalUpdates`: when supported, remove the old identity projections for changed/deleted records and save the new changed projections. Otherwise construct the complete identity list from the authenticated encrypted catalog projection for full identity replacement, never from delta records. This avoids deleting unchanged suggestions or decrypting unchanged password bodies. Verify the deployed minimum-SDK overloads during implementation. The catalog ciphertext remains the only additional storage for usernames/domains; no plaintext identity sidecar is introduced. Identity maintenance can be O(total identities) on platforms requiring fallback, while credential reveal/encryption remains O(changed entries).

Bind every asynchronous identity callback and compensation operation to provider generation plus catalog revision. A stale callback must neither acknowledge current readiness nor globally erase newer identities. Provider lookup and final handoff always consult the current authenticated catalog; an OS record identifier or cached identity is never authority. Keychain/identity-store failures remain typed and fail closed, and physical iOS biometric/cross-process acceptance is a separate release gate.

## Required regression and measurement gates

- Full baseline followed by one create/update/delete reveals only the changed Entry (zero for delete), makes zero Entry HTTP reads and does not decrypt unchanged credential records.
- Android and iOS native transactions reject wrong base generation/revision, missing catalog/key/blob, invalid MAC/AEAD, wrong profile/Vault/Entry/revision/key bindings, stale leases and clock rollback.
- A failed delta does not acknowledge readiness, release pending denies or overwrite the authoritative base. Missing base triggers full recovery, not partial cache installation.
- Deletion/update during biometric prompt or picker selection blocks stale handoff. Lock/revoke during encryption, file commit and OS identity update cannot reactivate a denied generation.
- Simultaneous updates, crashes between file/fence commits, stale iOS credential-identity callbacks and native cache quarantine all remain fail-closed.
- Synthetic real SQLite/crypto benchmark compares full preparation and one-entry change with the same dataset/SHA. Record request counts and actual reveal counts, not only wall time.
- Android native/emulator and Swift validator/SDK tests must run. iOS simulator tests do not prove physical biometric Keychain behavior; physical iOS testing remains a release gate. No iOS publication is authorized.

## Integration boundaries

Preparation progress reports changed entries examined and publication acknowledgment. It must not mark ready before native commit or claim a delta is a complete initial cache. Progress UI work owns its existing service additions; incremental changes should be integrated against that contract separately.

Implementation requires coordinated Dart mutation/durable-update contracts, native v3 stores/providers on both platforms, and bridge tests. It should not be hidden inside the current lease fix or delivered as a partial Android-only parity claim.
