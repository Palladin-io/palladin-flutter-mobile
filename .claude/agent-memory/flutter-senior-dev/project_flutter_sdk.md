---
name: Flutter SDK path and project structure
description: Flutter SDK location, project naming, and flavor setup for the Palladin mobile app
type: project
---

## Flutter SDK
- Path: `/Users/patryk/Sdk/flutter`
- Must prepend to PATH: `export PATH="/Users/patryk/Sdk/flutter/bin:$PATH"`
- Flutter is NOT on the default shell PATH

## Project Identity
- Package name (pubspec): `mobile_palladin`
- Android namespace: `io.palladin.mobile`
- iOS bundle ID base: `io.palladin.mobile`
- Staging suffix: `.staging`

## Flavors (added 2026-03-11)
- Two flavors: `staging` and `production`
- Entry points: `lib/main_staging.dart`, `lib/main_production.dart`
- Config class: `lib/config/env_config.dart` (EnvConfig with factory constructors)
- Android: productFlavors in `android/app/build.gradle.kts`
- iOS: flavor-specific xcconfig files in `ios/Flutter/flavors/` and `ios/Flutter/{Debug,Release,Profile}-{staging,production}.xcconfig`
- iOS schemes: `staging.xcscheme` and `production.xcscheme` (old `Runner.xcscheme` removed)

## Run Commands
```
flutter run --flavor staging -t lib/main_staging.dart
flutter run --flavor production -t lib/main_production.dart
```

## CI
- `.github/workflows/test.yml` - runs `flutter analyze` + `flutter test` on PRs to main
