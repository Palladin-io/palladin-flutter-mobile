---
name: Flutter l10n setup
description: Localization configuration - ARB files, gen-l10n with output-dir, import paths, and error type pattern
type: project
---

## l10n Configuration
- Config file: `l10n.yaml` at project root
- ARB directory: `lib/l10n/`
- Template: `app_en.arb` (English), also `app_pl.arb` (Polish)
- Generated output: `lib/l10n/generated/` (non-synthetic, concrete files)
- Run `flutter gen-l10n` to regenerate after ARB changes

## Important: Synthetic Package Deprecated
- `synthetic-package` option is deprecated in Flutter 3.x and has no effect
- Use `output-dir: lib/l10n/generated` to generate concrete Dart files
- Import as relative path: `import '../../l10n/generated/app_localizations.dart';`
- Do NOT use `package:flutter_gen/gen_l10n/...` (fails `flutter analyze`)

## Error Localization Pattern
- Data layer throws typed exceptions with enum kinds (no user-facing strings)
- `AuthServerException(AuthServerErrorKind kind)` — kind enum: serverNotResponding, cannotConnect, connectionFailed, invalidResponse
- `AuthError` state carries `Object error` (not a string message)
- Presentation layer resolves localized message in widget using `AppLocalizations.of(context)!` and `switch` on error kind

## pubspec.yaml Requirements
- `flutter_localizations` (sdk: flutter) in dependencies
- `intl: any` in dependencies
- `generate: true` under `flutter:` section
