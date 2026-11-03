# Incremental AutoFill Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update one credential on Android and iOS without revealing or re-encrypting every credential, retaining immediate durable invalidation and biometric provider protection.

**Architecture:** Native v3 stores independently encrypted records and an encrypted catalog selected by an authenticated, atomic revision fence. A native app-only writer capability is ephemeral and separate from the provider opening-key path; mutation scope and acknowledged base revisions drive bounded Dart deltas.

**Tech Stack:** Dart/Flutter, Kotlin/Android Keystore, Swift/CryptoKit/Keychain, existing SQLite Member sync and native test harnesses.

**Spec:** `docs/superpowers/specs/2026-11-03-incremental-autofill-cache-design.md`

## Global Constraints

- No persisted MK/VK/private keys or plaintext credential/cache metadata; no secret logging.
- Provider biometric retrieval, exact origins, lock/revoke, clock and lease checks remain mandatory.
- Ordinary lock invalidates the separate writer epoch synchronously; it does not revoke a still-authorized biometric provider generation.
- Missing, expired, quarantined or incompatible native delta base requires full recovery, never partial initial installation.
- iOS implementation/tests allowed; no iOS publication. Android publication is Internal Testing only.
- Resolve blocking technical design review before production v3 implementation. Keep PR 152 and progress UI independent.

## Ownership and shared bridge contract

Dart integration owns `autofill_cache_bridge.dart`, new value-free base/delta DTOs in `domain/`, `autofill_cache_service.dart`, `durable_autofill_repair_coordinator.dart`, `autofill_mutation_notifier.dart`, scoped canonical mutation call sites, and app writer lifecycle. Coordinate service status/app edits with the progress UI owner before cherry-picking.

Android owns `MainActivity.kt`, `autofill/AutoFillCacheStore.kt`, provider/authentication selection and handoff types, plus corresponding native tests. Extract focused v3 transaction/codec logic rather than further enlarging the existing store.

iOS owns `PalladinAutoFillBridgePlugin.swift`, `AutoFillCacheStore.swift`, provider/credential picker and identity synchronization, plus Swift SDK/native tests. Existing cross-process flock remains the transaction authority.

Shared operations, finalized with DTO contract fixtures before platform implementations:

- `beginWriterSession(sessionToken) -> writerEpoch`: app-only holder, no opening key returned to Dart.
- `endWriterSession(writerEpoch)`: synchronously invalidates capability and wipes memory.
- `replaceCacheV3(payload, sessionToken, writerEpoch) -> baseRevision`: complete recovery payload.
- `denyEntries(base, entries, writerEpoch) -> {base, denyToken}`: durable scoped deny acknowledged before remote mutation.
- `applyCacheDelta(baseRevision, completeAuthority, upserts, removals, releasingOwnerTokens, writerEpoch) -> baseRevision`: strict CAS; returns a typed recovery-required outcome for missing/unusable base, not success.

`baseRevision` binds provider generation and native catalog revision. Entry coordinates include organization/Vault/Entry IDs. Native code determines filenames; caller input never becomes a path. Catalog metadata remains encrypted. Unsupported new bridge methods must retain the existing fail-closed path, not silently claim incremental success.

## Review Focus

1. Writer epoch changes while crypto/file IO is pending must prevent commit; provider reads still require biometrics.
2. Restored old ciphertext/catalog or crash before/after pointer commit must not restore revoked/deleted credentials.
3. A lease-only refresh must not extend retained record authorization; key/membership changes require replacement or full recovery.
4. An old iOS identity completion must not erase or acknowledge newer identities; unchanged identities survive delta fallback.
5. Mixed scoped/unknown mutations and failed remote outcomes must preserve every independent deny owner.

## Task 1 — Native storage contract and crash-safe transaction fixtures

Files: new `test/fixtures/autofill_cache_v3/` protocol fixtures; new focused native catalog/record codec and transaction tests beside current Android/iOS cache tests; shared Dart base/delta DTO tests.

- [ ] Write RED fixtures: complete base plus one upsert and one removal, delete-last-entry produces a valid acknowledged empty catalog (distinct from missing base), retained ciphertext byte-identical; wrong generation/revision/digest, missing file, duplicate coordinates and unsupported version rejected.
- [ ] Define immutable record AAD, encrypted catalog schema, base revision, independent authority mapping and exact size/record budgets (retain current 2000-record limit).
- [ ] Implement immutable-file fsync, directory durability and authenticated fence-pointer CAS; keep old files until durable commit.
- [ ] Inject failure before/after every commit step: old valid base or durable deny remains; no hybrid catalog. Validate orphan cleanup cannot delete referenced files.
- [ ] Run Android cache-store JVM tests and Swift cache codec/transaction tests; commit contract/codec changes only when both agree on fixture semantics.

## Task 2 — Separate writer lifetime and scoped durable denial

Files: Android/iOS app bridge holders and native stores; `autofill_cache_bridge.dart`; lifecycle tests; later app integration.

- [ ] RED: start full publication, lock during encryption, then release completion; no fence commit and writer key bytes wiped. Provider biometric opening path still works on an authorized old generation.
- [ ] Implement writer epoch/capability without exposing key bytes to Flutter or provider read APIs. Check epoch immediately before commit under native transaction authority.
- [ ] RED: deny Entry A, retain B, open picker before deny then attempt A handoff; A blocked, B stays usable through a fresh authorized picker.
- [ ] Implement scoped deny with independent owner tokens. Failure to commit scoped denial falls back to global deny; failure of both aborts remote mutation.
- [ ] Cover overlapping owners, ambiguous result, logout/revoke, expired base and process death. Commit only after corresponding native tests pass.

## Task 3 — Native partial publication and provider reads

Files: Android/iOS stores, credential record/read-result types, authentication picker/handoff paths and bridge dispatch.

- [ ] RED: 160 synthetic records, one changed record causes one record encryption and zero unchanged record decryptions; delete causes no credential-body decryptions. Retained ciphertext unchanged.
- [ ] Implement delta CAS against exact acknowledged base. Validate retained complete authority/revision/key mapping and original record lease/AAD; effective expiry cannot exceed either original or current authority.
- [ ] RED: stale/missing/corrupt/quarantined base, expired retained lease, policy/key change, mismatched scope and lock during commit cannot succeed or release denies.
- [ ] Bind every provider result and final locked handoff to generation/catalog revision; keep exact domain/package verification unchanged.
- [ ] Test missing native base selects explicit full recovery rather than treating upserts as complete snapshot. Commit Android and iOS platform portions independently reviewable, feature not enabled until both contracts are integrated.

## Task 4 — iOS identity maintenance

Files: iOS bridge identity replacement coordinator and `AutoFillCacheStore.swift` identity helpers, Swift identity callback tests.

- [ ] RED: create/update/delete A leaves B suggestion intact; changed username/domain removes the prior identity; unsupported incremental identity store receives complete catalog projection.
- [ ] Use `getState.supportsIncrementalUpdates` to choose remove/save operations or complete identity replacement from encrypted catalog metadata. Never pass delta records to the existing full replacement method.
- [ ] RED: stale completion and compensation after a newer catalog commit neither acknowledge readiness nor erase newer identities.
- [ ] Validate SDK compilation at current minimum target and callback race tests; document physical biometric/identity-store acceptance still outstanding.

## Task 5 — Dart changed-entry planning and mutation scope

Files: `autofill_cache_service.dart`, `durable_autofill_repair_coordinator.dart`, `autofill_mutation_notifier.dart`, `canonical_entry_detail_service.dart`, `entry_repository_impl.dart`, app lifecycle; existing focused tests.

- [ ] RED service test: full publication of 160 records then current index changes one revision; only that Entry is revealed, all retained records have current independent authority, HTTP read count stays zero.
- [ ] Add validated whole-Vault publication-authority reading at the existing `MemberSyncService`/cache boundary, using independently current session authority, without revealing credential payloads. Empty Vaults still require profile authority; do not derive it from a nonexistent first record. Add memory-only acknowledged value-free base metadata. Derive upserts/removals from complete installed MemberIndex plus committed authority; missing authoritative change information uses full repair.
- [ ] RED mutation tests: known canonical update/delete passes exact scope to awaited native denial before transport; unknown/import/rotation scopes retain global invalidation. Two simultaneous owners cannot release each other's deny.
- [ ] Add optional explicit scope to `_commitAutoFillAwareMutation`; update create/update/delete/restore/destroy callers where coordinates are known. Keep uncertain/bulk paths global until complete scope proven.
- [ ] On native recovery-required result, execute existing full path only while current session/epoch/authority permits. No stale base reuse after revoke, missing key or process restart.
- [ ] Integrate writer invalidation on ordinary lock and status phases with progress owner. Preparation counts changed entries; readiness follows native commit/identity acknowledgment, never merely request completion.
- [ ] Run cache, coordinator, mutation, canonical Entry and native bridge regression suites; commit.

## Task 6 — End-to-end evidence and review

- [ ] Extend real synthetic SQLite/crypto benchmark: full prepare 160 entries, one update/delete/create, assert reveal/encryption counts and zero new Entry HTTP requests. Compare exact tested SHA before/after; do not substitute delayed mocks for timing proof.
- [ ] Android harness: initial base, delta while chooser open, provider lookup after delta, lock/revoke, and missing-base full recovery. Preserve origin/negative form regressions.
- [ ] Swift codec/SDK and supported native transaction tests; state explicitly that simulator checks do not prove physical Keychain/biometry.
- [ ] Run repository required checks, security review, Codex Review Loop and authorized CI. Merge only after all applicable gates pass; Android Internal Testing only, no iOS release.

## Checkpoint

Design security review accepted; implementation is isolated in `palladin-autofill-incremental` (`feat/autofill-incremental-cache`). Android native commit `9f8539dc` is integrated as `d46cbdfc` (148 native tests and real Kotlin compile passed); iOS native `924f10df` is integrated as `ca622d9d` (real CryptoKit synthetic suite and SDK checks passed). Dart publisher/metadata/scoped mutation integration is implemented and under security review. Fixed stale-clear callbacks, pre-await owner capture, and empty-denial CAS; focused race suite passes. Full Dart suite reruns with explicit libsodium path after environment-only failures. Real SQLite/crypto/loopback benchmark passed: 160 initial reveals, one per update, zero per delete and zero publication HTTP requests. Integration exposed full-scope denial release needing authoritative retained-reference reconciliation; security-approved fixes are integrated for both platforms (Android 149 native tests; iOS CryptoKit/SDK tests). Unclassified publication failures globally deny only the current generation; the focused regression passed RED→GREEN. No release readiness or physical v3 parity claim. Next: close review findings, benchmark actual delta, validate exact integrated SHA, open PR/review/CI. Diagnostic instrumentation remains separate and excluded.
