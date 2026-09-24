# Palladin Mobile

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

Palladin Mobile is the iOS and Android client for Palladin, a zero-knowledge
password manager designed for people who delegate work to AI agents. The app
manages encrypted vaults, reviews agent access requests, and performs all
credential encryption and decryption on the device.

> [!CAUTION]
> This is security-sensitive software. Development builds and unreviewed
> changes should never be used with real credentials.

## Security model

The backend coordinates accounts, devices, agents, grants, and encrypted
records, but it is not entrusted with plaintext vault contents or client key
material. The mobile client is responsible for:

- deriving and handling key material on-device;
- wrapping and unwrapping vault keys for authorized members and agents;
- encrypting credential payloads before upload and decrypting them after
  download;
- keeping unlocked vault keys in process memory and clearing their byte buffers
  when a session ends;
- requiring explicit OS/user authorization for biometric unlock and system
  AutoFill;
- preventing sensitive values from entering logs, analytics, shared
  preferences, backups, or notification payloads.

Authentication tokens are persisted in platform secure storage. They authorize
API calls but cannot decrypt vault data. Optional biometric unlock uses a
dedicated, biometric-gated platform keystore path; normal unlocked key state is
held only in memory.

The high-level boundary is:

```text
master password / recovery material
                |
                v
      on-device key derivation
                |
                v
     member key + wrapped vault key
                |
                v
       on-device vault crypto  <---->  API: ciphertext, wrapped keys,
                |                      grants, and non-secret metadata
                v
      plaintext only in the app
```

Cryptographic primitives and protocols live under `lib/core/crypto/` and
`lib/features/vault/data/services/vault_protocol/`. Business logic belongs in
services, repositories, use cases, and BLoC/Cubit state—not in widgets.

## Architecture

The app follows feature-oriented clean architecture:

```text
lib/
  config/                    flavor and environment configuration
  core/                      crypto, network, storage, theme, routing, widgets
  features/<feature>/
    data/                    API models, data sources, repository implementations
    domain/                  entities, repository contracts, use cases
    presentation/            BLoCs/Cubits, pages, feature widgets
```

Core technologies include Flutter, `flutter_bloc`, `get_it`, `go_router`, Dio,
libsodium, Firebase Cloud Messaging, and ARB-based localization. See
[`docs/architecture/`](docs/architecture/) for the component catalog and
per-feature notes.

## Supported targets and flavors

The maintained application targets are Android and iOS.

| Flavor | Entry point | API | Application ID / bundle ID |
|---|---|---|---|
| `local` | `lib/main_local.dart` | local backend on port 5000 | `io.palladin.mobile.local` |
| `staging` | `lib/main_staging.dart` | `https://api.stage.palladin.io` | `io.palladin.mobile.staging` |
| `production` | `lib/main_production.dart` | `https://api.palladin.io` | `io.palladin.mobile` |

On the Android emulator, the local flavor maps the host to `10.0.2.2`; other
platforms use `localhost`. Environment values are defined in
`lib/config/env_config.dart` and must not be hardcoded in features.

## Prerequisites

- Flutter 3.41.4 stable with Dart 3.11.1 (the revision is recorded in
  `.metadata`)
- Android Studio/SDK for Android development
- Xcode and CocoaPods for iOS development
- a Palladin-compatible API listening on port 5000 for the `local` flavor
- libsodium for native protocol-vector tests (`libsodium-dev` on Ubuntu or
  `libsodium` through Homebrew)

This repository is self-contained for dependency resolution, static analysis,
and tests. It does not require a parent monorepo or private package checkout.

## Build and run

```bash
flutter pub get
flutter gen-l10n
flutter run --flavor local -t lib/main_local.dart
```

Other environments use the matching entry point:

```bash
flutter run --flavor staging -t lib/main_staging.dart
flutter run --flavor production -t lib/main_production.dart
```

Store testing may build the immutable production app identity against the
staging API:

```bash
flutter build appbundle \
  --release \
  --flavor production \
  -t lib/main_production.dart \
  --dart-define=PALLADIN_BACKEND_ENVIRONMENT=staging
```

Do not upload the staging application ID as a production-store artifact.

Public catalog icons use `EnvConfig.apiBaseUrl` and the immutable
`/api/public-assets/{assetId}/revisions/{revision}/content` endpoint. This also
applies when the production store identity targets staging, or when a deployment
configures a self-hosted API. There is no separate asset-host allowlist or build
variable. Deploy the backend content endpoint before releasing these clients;
unavailable images use a local glyph. Mobile still selects its API through the
build configuration; this change does not add a runtime server selector.

## Google OAuth build configuration

Before running or building Google Sign-In, supply explicit backend and iOS
client IDs using `tool/configure_google_oauth.py` and the generated
`--dart-define-from-file`. See [configuration instructions](docs/firebase-config.md#explicit-google-oauth-build-inputs).
A fresh clone has no OAuth audience configured; Google login fails closed.

## Firebase client configuration

Per-flavor `google-services.json` and `GoogleService-Info.plist` files are ignored
build inputs. Install your downloaded client file using
`tool/configure_firebase.py --flavor local --platform android --source /path/to/google-services.json`
(or `--platform ios` with the plist). Native builds require this explicit setup;
unit tests and analysis do not. The installer preserves existing OAuth metadata.
Store builds use distribution-scoped GitHub configuration variables.

Public client configuration is safe only when the Firebase/GCP projects are
secured independently. Maintainers must apply application and API restrictions
to client keys, deny-by-default Security Rules to every enabled Firebase data
product, and App Check enforcement wherever the selected Firebase product
supports it. App Check and Security Rules complement key restrictions; neither
turns a client API key into a secret. See
[`docs/firebase-config.md`](docs/firebase-config.md) for the full operational
boundary.

Never commit service-account JSON, APNs signing keys, Android signing stores,
private certificates, backend credentials, or production secrets.

## Tests and continuous integration

Scan a clean checkout (without ignored cloud configuration), then run the
checks used by pull-request CI:

```bash
(cd /path/to/clean-checkout && gitleaks dir . --config .gitleaks.toml --redact --no-banner)
python3 -m unittest discover -s tool/tests
dart run tool/generate_third_party_notices.dart --check
flutter analyze
flutter test test/performance/vault_v2_mobile_structural_budget_test.dart
flutter test
```

The test workflow uses only repository contents and read-only GitHub
permissions, so it is safe to run for pull requests from public forks. Store
builds are separate, maintainer-triggered workflows and require protected
signing secrets. Pull-request CI intentionally does not build APKs or other
application artifacts; it validates source quality and behavior through static
analysis, structural budgets, and the complete test suite.

CI runs Gitleaks 8.30.1 against the current tree. The repository configuration
extends the default rules and contains exact-path exceptions for synthetic
crypto tests and fixtures, dependency checksums, and cryptographic documentation.
A separate
`.gitleaksignore` contains one commit-, path-, rule-, and line-specific
fingerprint for a historical synthetic Stripe-shaped UI mock; it does not
suppress current-tree findings.

Vault protocol 2 tests consume a vendored, synthetic, hash-verified fixture
snapshot. Its exact source commit, path, manifest digest, and file digests are
recorded in
[`test/fixtures/vault_protocol_2/PROVENANCE.md`](test/fixtures/vault_protocol_2/PROVENANCE.md).
That provenance also records the single public-sanitization delta from the
source snapshot. No external or private checkout is required to execute the
tests.

## Contributing

All changes go through pull requests and must pass analysis and tests. Before
working on a feature, read [`AGENTS.md`](AGENTS.md), the shared widget catalog,
and the relevant file under [`docs/architecture/features/`](docs/architecture/features/).

Security invariants are release blockers:

- never send plaintext credentials or encryption keys to the backend;
- never persist raw vault keys in general-purpose storage;
- never log secrets, tokens, recovery material, or decrypted payloads;
- keep cryptographic operations inside dedicated services;
- use synthetic data in tests and issue reports.

Generated localization files under `lib/l10n/generated/` must not be edited by
hand. Update both ARB source files and run `flutter gen-l10n` instead.

The source code and documentation are licensed under
[Apache License 2.0](LICENSE). Palladin names and the artwork identified in
[TRADEMARKS.md](TRADEMARKS.md) are reserved and excluded from that grant. See
[CONTRIBUTING.md](CONTRIBUTING.md) for DCO sign-off requirements and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for dependency attributions.

## Optional client analytics

Client collection is disabled by default. `POSTHOG_PROJECT_KEY` alone cannot enable
it; a released build also needs `CLIENT_ANALYTICS_RELEASED=true`, current account
consent and explicit local activation. See [privacy architecture](docs/architecture/features/privacy.md).
