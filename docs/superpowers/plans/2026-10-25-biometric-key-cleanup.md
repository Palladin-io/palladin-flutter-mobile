# Biometric key cleanup

Approved scope: retain biometric unlock and its current per-operation OS protection. Replace marker-only cleanup with actual deletion on logout, biometric disable and password change. Do not claim immunity to a compromised OS. No credential or crypto protocol changes.

The pinned biometric_storage delete API loses native failure information. A fixed-name native cleanup channel will delete only its existing MK item: Keychain service/account on iOS; wrapping-key alias and ciphertext on Android. Missing items are success; errors are reported without secret values. Marker removal is attempted even on native failure. Existing authentication options remain unchanged.

- [x] Observe failing Dart cleanup and logout regressions.
- [x] Implement native deletion and wire all lifecycle paths.
- [x] Cover native deletion failures/idempotence and concurrency with enrollment.
- [x] Update architecture, run focused tests and required repository checks.
- [ ] Parent runs PR Codex Review Loop and CI before merge.

Device gate: actual Face ID/fingerprint prompts, changed biometric enrollment, cancellation, restart, and logout/re-enrollment still require device validation. Unit tests are not that evidence.

Checkpoint: isolated branch fix/biometric-key-cleanup rebased onto merged pipeline main e3e8f65. RED confirmed for protected deletion, logout retention, false-success failures, enrollment race, and deferred KDF/canStore after disposal. Native fixed-scope cleanup, typed failure handling, token revocation, and synchronous generation invalidation implemented. Focused lifecycle tests and Android JVM deletion tests pass. Validation: flutter analyze clean; full Flutter suite 1973 passed / 2 skipped with PALLADIN_LIBSODIUM_PATH pointing to the installed host library (default host library discovery failed); Android JVM 2 passed; Python tools 21 passed; Fastlane 15 passed / 25 assertions; notices, actionlint, gitleaks and diff/instruction parity checks passed. No APK/IPA was built. Real OS key deletion and biometric prompts remain device checks. Parent owns review/CI, root policy PR224 and store provisioning. Internal tester distribution follows review and automated gates; physical device acceptance remains pending for broad/public release.
