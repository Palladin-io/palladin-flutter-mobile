# Shared ciphertext AutoFill implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Each task retains its RED→GREEN and independent review gate.

**Goal:** Fill the selected login from the canonical encrypted Member source without a second bulk credential export.

**Architecture:** Native providers own OS requests and origin verification. Existing Dart MemberIndex and selected-entry crypto own matching and reveal. Android reuses the single main-app session; iOS runtime choice is gated by an executable credential-extension probe before production integration.

**Tech Stack:** Flutter/Dart, existing sodium FFI, SQLite WAL, Android Autofill, iOS AuthenticationServices.

**Spec:** `docs/superpowers/specs/2026-11-04-shared-ciphertext-autofill.md`

## Current checkpoint — 2026-11-04

- Accepted: one canonical encrypted Member database, index-only matching and one selected secret reveal; optional password/biometric unlock. Narrow shared iOS wrapping key + encrypted MK envelope is explicitly approved. No broad Runner Keychain group and no old bulk-cache fallback.
- Integration: `palladin-autofill-shared-ciphertext`, branch `feat/autofill-shared-ciphertext`; native adoption through Android `228287c1` and iOS `7236706a`. Source/app/DI retirement changes are being integrated locally; no replacement PR or release yet.
- Evidence: Android real Flutter cold/warm request harness and protected-source process-death tests passed; iOS OS-launched synthetic extension completed password KDF, canonical SQLite matching and selected username/password handoff. Device Release/AOT build passed; physical iPhone memory/biometric acceptance remains unverified and iOS publication is prohibited.
- Current regressions: actual SQLite WAL migration/restart and denial tests pass; held-open old-account write is rejected before native write admission. Picker/controller/Host 22 tests pass, including native source-change, cancellation and expiry clearing the old list. Loopback benchmark keeps 17 HTTP requests, lists 160 candidates with zero body opens, then opens one selected body with no additional HTTP.
- Local integration review is clean, including source transition, pre-open SQLite session fencing, initial-picker sync, and accepted-token authority changes. Same-claims refresh preserves the source; changed/unknown claims durably deny before token publication and rebootstrap. Android actual OS save/revoke/process-death smoke and six same-checkout iOS native runners passed.
- Next: run root's full Flutter/analyze/notices/budget gates on the frozen integration commit, build the production-API Debug and complete S22 acceptance. Latest user gate requires the physical test BEFORE any cloud Codex Review; cloud review/merge/store publication remain on hold. No merge/store readiness claim from isolated test totals.

## Global constraints

- No new plaintext MK/VK/private-key persistence, no crypto copying or silent auth bypass.
- Preserve exact origin/package/manual consent, finite lease, quarantine and revoke boundaries.
- Android Internal Testing only after review/CI; no iOS publication.
- No shipped fallback to two credential databases. Retire export only when both replacements are accepted.
- Root owns setup UX; core owns export/progress removal. Platform workers own disjoint native/harness files.

## Review focus

- Warm Android app must not start a second auth/sync engine; cold OS request must remain completable.
- Extension activation after app death must authenticate against an independent current profile authority.
- Concurrent initial database reads/migration must not open two migration owners or expose staging.
- Account replacement/revoke during password unlock or selected reveal must prevent late fill.
- Process interruption must not leave old plaintext-export records as an undocumented fallback.

## Task 1 — canonical database opening and shared-path migration

Files: `lib/features/vault/data/services/member_sync_cache.dart`, its existing test,
and an iOS App Group path accessor in the existing native bridge when reviewed.

- [x] Add concurrent first-read regression: two readers share one loader; failed opening remains retryable.
- [x] Observe RED: actual loader calls 2 versus expected 1.
- [x] Store one in-flight open Future, clear on failure, reuse opened database.
- [ ] Run real SQLite tests and focused analyzer; review the minimal change.
- [ ] Add migration tests before implementation: committed active generation and quarantine survive, staging remains unreadable, crash before/after destination commit is recoverable, migration is single-owner.
- [ ] Implement one canonical App Group path and migration only after iOS runtime/storage contract is approved. No database copying during ordinary fills.

## Task 2 — executable platform entrypoint gates

Android worker owns `tool/android-autofill-harness/` proof and native request-owner wiring.
iOS worker owns `tool/ios-credential-extension-probe/` and disposable target configuration.

- [ ] Android cold/warm MainActivity task proof: original nonexported auth Activity remains the sole OS result owner; in-process broker holds metadata only; cancellation/back/death consumes request.
- [ ] iOS Debug simulator CredentialProvider executes existing synthetic wrapper/index/selected-secret crypto and reports only fixed-stage memory/time metrics.
- [ ] iOS unsigned device Release build proves AOT linkage; physical OS activation/memory remains a separate gate, never inferred from simulator success.
- [ ] Review measured runtime result and choose production runtime before integrating new provider storage or key access.

## Task 3 — request-scoped Flutter selection and reveal

Core owns new `lib/features/autofill/data/autofill_request_controller.dart`,
`presentation/autofill_selection_page.dart`, app/router wiring and focused tests.
Native workers own channel request lifetimes and OS completion.

- [ ] Freeze the broker contract after Task 2: native-owned nonce/mode/exact host set; Flutter receives no field IDs as authority; final completion is one-shot and native revalidates origin.
- [ ] RED production repository integration: matching lists MemberIndex only; selecting one item opens exactly its body; no selection/cancel opens none.
- [ ] Implement current unlocked identity fencing and existing auth continuation, reusing `LocalCurrentEntryService` without duplicating crypto.
- [ ] RED and fix: lock/account switch, changed/deleted Entry, expired lease, native request replacement and delayed completion reject; username-only never returns a password.
- [ ] Preserve native per-fill authorization and exact-host/manual-mode policies; review before native handoff integration.

## Task 4 — iOS canonical source and protected authority

- [ ] Freeze independent protected claims/revocation projection from accepted session authority, not selected database rows. Do not share bearer tokens merely to obtain claim fields.
- [ ] Implement the reviewed runtime against the same database and crypto contract; password unlock remains available.
- [ ] Gate any reuse of the existing protected MK on explicit policy review: access-group entitlement grants group-wide access, not item-only access. Do not create a duplicate MK item.
- [ ] Test cross-process committed snapshot, revoke, lease expiry, process death, cancellation and late-auth callback with synthetic data.

## Task 5 — remove bulk export and integrate

Core deletes `autofill_incremental_publisher.dart`,
`durable_autofill_repair_coordinator.dart`, export-only cache bridge/service and
`autofill_preparation.dart` after separating remaining revoke/save consumers;
remove `autofill_preparation_card.dart` and `autofill_home_body.dart` plus app/DI
and Security/Home wiring. Platform workers delete dedicated credential catalog
writers/readers only after origin/save/history utility dependencies are separated.

- [ ] RED full app lifecycle: unlock/resume/remount/renewal perform zero MemberSecret reveals and zero credential-export writes.
- [ ] Remove export scheduling and progress; retain source index repair, provider selection, browser setup, save and generated-password recovery.
- [ ] Delete old encrypted provider artifacts under durable revocation, with interrupted cleanup regression; no dual-cache runtime fallback.
- [ ] Integrate setup commit `3e636aa2…aaaa8` and coordinate ARB changes with root.
- [ ] Run full Flutter tests/analyze/notices/scan/budgets, both native suites, platform runtime tests, independent security review and exact-head Codex Review/CI.
- [ ] Root performs S22 native/web cold/warm/revoke acceptance; do not publish until all required gates pass and remaining iOS limitations are explicit.
