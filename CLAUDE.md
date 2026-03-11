# Claw Vault — Mobile App

Flutter mobile app for managing vaults, approving agent grants, and biometric unlock. Zero-knowledge architecture — all encryption/decryption happens on-device.

Repository: [Flamingo-Co/claw-vault-flutter-mobile](https://github.com/Flamingo-Co/claw-vault-flutter-mobile)

## Build & Run

```bash
flutter pub get                                              # Install dependencies
flutter analyze                                              # Lint
flutter test                                                 # Run all tests
flutter run --flavor staging -t lib/main_staging.dart         # Run staging
flutter run --flavor production -t lib/main_production.dart   # Run production
```

## CI/CD

GitHub Actions workflow at `.github/workflows/test.yml` runs on PRs to `main`:
1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`

**All changes must go through PRs** — CI must pass before merging.

## Flavors

Two flavors: **staging** and **production**. Each has its own entry point, bundle ID, and config.

| | Staging | Production |
|--|---------|------------|
| Entry point | `lib/main_staging.dart` | `lib/main_production.dart` |
| Bundle ID | `io.clawvault.mobile.staging` | `io.clawvault.mobile` |
| App name | Claw Vault (Stage) | Claw Vault |
| API URL | `https://api.stage.clawvault.io` | `https://api.clawvault.io` |

Config class: `lib/config/env_config.dart` — `EnvConfig.staging()` / `EnvConfig.production()`.

### Android
- Product flavors in `android/app/build.gradle.kts` (`staging`, `production`)
- Firebase: place per-flavor `google-services.json` in `android/app/src/{flavor}/`

### iOS
- Schemes: `staging`, `production` (in `ios/Runner.xcodeproj/xcshareddata/xcschemes/`)
- Build configs: `Debug-{flavor}`, `Release-{flavor}`, `Profile-{flavor}`
- Xcconfig: `ios/Flutter/flavors/{flavor}.xcconfig`
- Firebase: place per-flavor `GoogleService-Info.plist` via xcconfig or build phase

## Tech Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| Framework | Flutter (Dart) | iOS + Android |
| State Management | flutter_bloc | Cubit for simple, Bloc for complex |
| DI | get_it + injectable | Service locator pattern |
| Navigation | go_router | Declarative routing |
| Crypto | libsodium via FFI | Zero-knowledge encryption on-device |
| Key Storage | OS Keychain / Android Keystore | Biometric unlock support |
| Push | Firebase Cloud Messaging | FCM for Android, APNs for iOS |
| Auth | flutter_appauth | OAuth 2.0 (Google, Apple, X) |
| HTTP | dio + retrofit | REST API client |
| Models | freezed + json_serializable | Immutable data classes |
| Analytics | PostHog | `mb:{module}:{event}` convention |

## Project Structure

```
lib/
  config/              # EnvConfig, app constants
  core/                # Theme, utils, errors, network
  features/
    feature_name/
      data/            # Models, datasources, repositories_impl
      domain/          # Entities, repositories, usecases
      presentation/    # Bloc, pages, widgets
  app.dart             # App widget
  main.dart            # Default entry (staging)
  main_staging.dart    # Staging entry point
  main_production.dart # Production entry point
```

## Analytics (PostHog)

```
mb:{module}:{event}
```

Mobile tracks **UI-only** events — page views, biometric usage, push taps. Business logic events are tracked by backend.
