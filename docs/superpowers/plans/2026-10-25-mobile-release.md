# Mobile Release Implementation Plan

> For agentic workers: use superpowers:executing-plans task-by-task; preserve the owner's explicit authorization to implement.

**Goal:** Build and automatically distribute signed main builds to internal testers on demand.
**Architecture:** GitHub Actions orchestrates validation, an immutable tag ledger, reusable signed build jobs and Fastlane delivery. Upload retries consume verified artifacts, not source checkouts from the original run.
**Tech Stack:** Python standard library, Ruby/Fastlane with lockfile, GitHub Actions, existing Flutter toolchain.
**Spec:** ../specs/2026-10-23-mobile-on-demand-release-design.md

## Global Constraints
- main-only workflow_dispatch; prod and disabled-by-default stg map to distinct app identities.
- No public distribution, external beta, signing secrets in artifacts or direct version commits to main.
- Preserve checks, attestations, protected environments and signing cleanup.
- Keep/bump/manual marketing version; durable immutable sequence reservation; upload retries retain original bytes.
- Existing biometric release blocker remains in force; real uploads stay disabled until reviewed remediation.

## Review Focus
- Same-run reruns must reuse reservation, reject changed inputs, and never rebuild accepted binaries (tasks 1, 4).
- Old resumed Android builds must not replace newer internal builds (task 3).
- Store timeouts must not be mistaken for failed uploads safe to blindly repeat (task 3).
- GitHub artifact metadata, digest and source run must all bind to the reservation (tasks 1, 4).
- Missing staging/configuration/signing/processing requirements fail closed (tasks 2–4).

## Task 1: Release identity and verified artifacts
Files: tool/mobile_release.py, tool/tests/test_mobile_release.py.
Interfaces: resolve_version(base, mode, manual); ios_build(sequence); reserve_record(inputs, records, floor); verify_manifest(record, manifest, directory, platform). CLI subcommands reserve, validate-resume, manifest, verify, summary use value-free JSON.
- [x] Write failing tests for version modes, downgrade, platform bounds, environment mapping, rerun mismatches, wrong artifact identities/digest and source-run provenance.
- [x] Run python3 -m unittest discover -s tool/tests; verify RED.
- [x] Implement pure logic and gh API adapter with create-only annotated tags and repository-scoped API paths; never interpolate shell input.
- [x] Run all Python tests; require GREEN; commit.

## Task 2: iOS signing preflight
Files: tool/verify_ios_profiles.py, tool/tests/test_verify_ios_profiles.py.
Interface: validate_profiles(app, extension, team_id, bundle_id, now, certificate_fingerprints) validates decoded plist metadata before xcodebuild.
- [x] Tests: expired profiles, wrong IDs/team, missing Associated Domains/App Groups/AutoFill and certificate mismatch.
- [x] Run tests RED, implement, run all Python tests GREEN, commit.

## Task 3: Store delivery
Files: Gemfile, Gemfile.lock, fastlane/Fastfile, fastlane/lib/mobile_delivery.rb, fastlane/tests/mobile_delivery_test.rb.
Interfaces: delivery consumes verified release manifest and artifact path; emits value-free status JSON. Google adapter uses Application Default Credentials; Apple adapter API key env. Internal track/group only.
- [x] Stub store APIs; test existing uploaded builds, processing timeout, unknown same-number identity, partial delivery, superseded Android build, internal group configuration and failures.
- [x] Run Ruby tests RED, implement pinned Fastlane wrappers and bounded reconciliation; run GREEN; commit.

## Task 4: Workflow integration
Files: .github/workflows/test.yml, mobile-store-builds.yml, mobile-store-artifacts.yml, mobile-store-upload.yml.
Interfaces: test workflow_call has no secrets; artifacts workflow receives reserved record; upload workflow receives original run ID and platform subset. Environment variables supply configuration only.
- [x] Add dispatch/call to Test and script test jobs. Refactor existing signing/build jobs without changing unrelated commands.
- [x] Main orchestrator: validate main/environment, tests, reserve, build, upload, final summary; resume skips builds and resolves original record.
- [x] Retain immutable pins; scoped permissions and protected environments; enforce distribution-disabled gate; attest manifests and binaries.
- [x] actionlint and script suites GREEN; dry-run mocked API scenarios; commit.

## Task 5: Documentation, review and PR
Files: docs/mobile-store-builds.md, AGENTS.md/CLAUDE.md, design checkpoint.
- [x] Document inputs, provisioning, version encoding, trust boundaries, restart semantics, expiry and tester verification. Keep instruction mirrors identical.
- [ ] Review entire diff; run actionlint/Python/Ruby checks and repository CI on PR (authorized). Flutter checks run on CI; no PR app builds.
- [x] Independent whole-branch review; fix demonstrated significant findings with RED→GREEN tests.
- [ ] Open PR, report exact checks and external provisioning blockers; do not claim store delivery before real acceptance.

## Checkpoint
Pipeline PR126 and biometric cleanup PR127 are merged. Android0.1.0/build1 was accepted by Google Play and made available to internal testers; real iOS compilation exposed an outdated default SDK. The integrated follow-up includes explicit Xcode26.3 selection and the first Android tester feedback: prompt bounded Inbox hydration, branded dark launch, native adaptive launcher mask, safe action footers, email/TOTP biometric enrollment, and a live OS AutoFill activation warning on the initial Dashboard plus status in Security. OS selection remains user-controlled; refresh after returning from settings confirms it. Android uses its package-scoped selector; iOS17+ has the supported shortcut, older iOS shows manual instructions.

Integration branch fix/android-internal-feedback is based on0c83d459…ced6e3. Focused regressions were observed failing before fixes; independent review is clean. Analyzer, Python21, Fastlane15/25, actionlint, notices and source secret scan pass. Full integrated Flutter suite passed: 2000 tests, 2 skipped. Cloud PR review and repository CI are the next gates. The SDK change supersedes the separately pending PR128 when this integrated change merges. Original dirty checkouts are preserved. Physical Samsung S22 Ultra checks remain: cold launch, launcher masking, gesture/three-button footers, default provider selection/resume warning, biometric setup/relock/logout, and perceived Inbox timing. iOS real-device acceptance remains unavailable. Internal delivery enables these tests; public rollout remains gated on device acceptance.

### Implementation rulings
- Keep existing protected-environment approval gates on both build and upload jobs; bypassing them would weaken release authorization. Cost: GitHub may request more than one approval.
- Upload jobs receive contents:write to create immutable upload-intent tags. This binds ambiguous store responses to the original manifest, including Apple builds without an exposed digest. Cost: release token scope includes repository writes; protect the tag namespaces and environments.
- Reject build-job reruns after attempt one; resume only verified artifacts or dispatch a new release. Cost: even an early failed build consumes its reserved identity.

Android resume promotion regression: test_android_promotes_verified_existing_bundle_without_upload observed RED then GREEN; 13 Ruby tests / 19 assertions pass. Fastlane lane loads on pinned dependencies.

Final review: independent whole-branch reviewer identified two important findings; no deferred minor findings. Both fixed in one TDD pass: actual Spaceship IN_BETA_TESTING model now reconciles only with exact internal group membership; Google upload disables rescue_changes_not_sent_for_review. Both tests observed RED → GREEN; Ruby suite 15 tests / 25 assertions passes. PR CI is the next gate; external store acceptance remains blocked as above.
