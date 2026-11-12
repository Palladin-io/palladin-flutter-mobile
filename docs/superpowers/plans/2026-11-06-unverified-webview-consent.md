# Unverified WebView consent implementation plan

Goal: offer an authenticated exact-host Fill once path for unverified app WebViews.
Architecture: distinct MANUAL_WEB request mode, existing selection/consent tokens,
reportedHost distinct from verifiedHosts on the bridge. No persistent trust.
Tech stack: Kotlin AutofillService and shared Flutter picker.
Spec: ../specs/2026-11-06-unverified-webview-consent.md

- [x] RED: origin policy permits only explicit eligible manual Web requests; negative
  HTTP/multiple hosts/browser/query failure, and request consume requires consent.
- [x] Implement native policy, immutable destination metadata, final revalidation;
  save/generation reject mode. Verify all native tests.
- [x] RED: bridge rejects malformed manual-Web metadata; picker stays exact-host,
  cancel does not decrypt/fill, confirm required and invalidated on source changes.
- [x] Implement existing picker warning with installed app/host EN/PL; no iOS widening.
- [ ] Run Flutter checks and native tests, inspect diff and security boundaries,
  build/install Debug for physical acceptance. Stop before cloud review/release.

Review focus: no conversion of reported host into verified authority, no broad
manual search, no browser fallback, no changed-signature/locked-source completion,
no accidental SaveInfo or password generation. Native owns all final decisions.
