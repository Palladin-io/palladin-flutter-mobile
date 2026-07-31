# Contributing to Palladin Mobile

Palladin Mobile is security-critical. Start with a public issue describing the
problem, threat model, compatibility impact, and proposed tests before opening
a substantial pull request. Report vulnerabilities privately according to
`SECURITY.md`.

## Mobile changes

Read `AGENTS.md` and the relevant document under
`docs/architecture/features/` before changing a feature. Use synthetic data
only; never paste real credentials, tokens, recovery phrases, or production
logs into an issue, test, or pull request.

Install the Flutter version recorded in `.metadata`, then run:

```bash
flutter pub get
flutter gen-l10n
flutter analyze
flutter test test/performance/vault_v2_mobile_structural_budget_test.dart
flutter test
```

Pull-request CI runs these checks with read-only permissions and requires no
private parent repository. Keep changes focused, update relevant architecture
documentation, and add tests for behavior and security invariants.

When adding a dependency, verify its license compatibility, update
`pubspec.lock`, regenerate `THIRD_PARTY_NOTICES.md`, and confirm the in-app
open-source licences page includes it.

## Protocol changes

Released protocol directories and fixture contracts are immutable. Changes to
wire fields, algorithms, AAD, canonicalization, key derivation, signatures, or
fixture bytes require an explicit version decision and a new immutable
contract.

Every change must include appropriate positive and negative conformance tests.
Run all commands documented in `README.md` before requesting review.

## Legal terms

By contributing, you agree that your contribution is licensed under the
license applicable to the files you modify.

Every commit must include a Developer Certificate of Origin sign-off:

    Signed-off-by: Your Name <your.email@example.com>

Add it with `git commit -s`. Do not submit code copied from another project
unless its source, copyright, and license are identified and compatible.

Submitting a contribution does not grant rights to Palladin trademarks. See
`TRADEMARKS.md` and `docs/branding.md` before distributing a fork.
