# Claw Vault — Mobile App

Flutter mobile app for managing vaults, approving agent grants, and biometric unlock. Zero-knowledge architecture — all encryption/decryption happens on-device.

## Project Brain

Wiedza biznesowa i architektoniczna projektu: `../docs/obsidian/claw-vault/`

Kluczowe noty dla tego repozytorium:
- `Technical/Mobile.md` — stack, flavory, BLoC, AppColors, i18n, konwencje
- `Technical/Analytics Conventions.md` — PostHog, format zdarzeń `mb:{module}:{event}`
- `Technical/Security Model.md` — zero-knowledge, szyfrowanie on-device
- `Product/Modules/Vault/` — Vault module: reguły, API, onboarding flow
- `Product/Modules/Notification/Business Rules.md` — FCM/APNs, push tokens

Użyj `/brain` żeby nawigować po brain lub: `grep -r "SŁOWO" ../docs/obsidian/claw-vault --include="*.md"`

**Po sesji która zmienia funkcjonalność, reguły biznesowe lub architekturę: zaktualizuj odpowiednią notę w brain.**

Repository: [Flamingo-Co/claw-vault-flutter-mobile](https://github.com/Flamingo-Co/claw-vault-flutter-mobile)

## Build & Run

```bash
flutter pub get                                              # Install dependencies
flutter gen-l10n                                             # Regenerate AppLocalizations
flutter analyze                                              # Lint
flutter test                                                 # Run all tests
flutter run --flavor local -t lib/main_local.dart            # Run local (localhost:5000)
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

Three flavors: **local**, **staging**, **production**. Each has its own entry point, bundle ID, and config.

| | Local | Staging | Production |
|--|-------|---------|------------|
| Entry point | `lib/main_local.dart` | `lib/main_staging.dart` | `lib/main_production.dart` |
| Bundle ID | `io.clawvault.mobile.local` | `io.clawvault.mobile.staging` | `io.clawvault.mobile` |
| App name | Claw Vault (Local) | Claw Vault (Stage) | Claw Vault |
| API URL | `http://localhost:5000` | `https://api.stage.clawvault.io` | `https://api.clawvault.io` |

Config class: `lib/config/env_config.dart` — `EnvConfig.local()` / `EnvConfig.staging()` / `EnvConfig.production()`.

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
| i18n | flutter_localizations + intl | ARB files, generated AppLocalizations |

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

## i18n / Localization

**Stack:** `flutter_localizations` (SDK) + `intl` — ARB files, generated `AppLocalizations`.

| File | Purpose |
|------|---------|
| `l10n.yaml` | Config — ARB dir: `lib/l10n/`, output: `lib/l10n/generated/` |
| `lib/l10n/app_en.arb` | English strings (template) |
| `lib/l10n/app_pl.arb` | Polish translations |
| `lib/l10n/generated/` | **Generated** — do not edit manually |

**Rules:**
1. **Never hardcode user-facing strings** — always add to ARB and use `AppLocalizations.of(context)!.key`
2. Error messages in the data/domain layer use **typed exceptions** (`AuthServerErrorKind` enum), not hardcoded strings — translation happens at the presentation layer where `BuildContext` is available
3. Regenerate after adding/changing keys: `flutter gen-l10n`
4. Supported locales: `en`, `pl` — add new locale by creating `app_{locale}.arb`

**Key naming:** `feature_action` or `feature_section_label` (snake_case, no dots — ARB keys are camelCase in Dart output).

## Shared Components — nie duplikuj kodu

Przed napisaniem nowego widgetu sprawdź czy coś podobnego już istnieje:

| Komponent | Lokalizacja | Zastosowanie |
|-----------|-------------|--------------|
| `OnboardingTextField` | `lib/features/onboarding/presentation/widgets/onboarding_text_field.dart` | Pola formularzy z labelem, borderem i animated feedback slotem (auth, onboarding, vault settings) |
| `AppSearchField` | `lib/core/widgets/app_search_field.dart` | Pola wyszukiwania z opcjonalną ikoną filtrów (`tune`) |
| `AppBottomNav` | `lib/features/shell/presentation/widgets/app_bottom_nav.dart` | Bottom navigation bar — używaj we wszystkich stronach które mają nav |
| `FieldFeedbackSlot` | razem z `OnboardingTextField` | Animowany slot na komunikaty walidacji poniżej inputa |

**Zasada:** nie kopiuj kodu widgetów inline — jeśli ten sam pattern pojawia się dwa razy, wyciągnij go do `lib/core/widgets/` i użyj wszędzie. Duplikacja stylu inputów, przycisków lub kart jest błędem.

## Theming & Colors

**Theme mode:** The app supports both light and dark mode. Default is dark. User can change it in settings — preference is persisted. Never hardcode `ThemeMode.dark` permanently; use the stored user preference.

**Color palette:** All colors must be defined in `lib/core/theme/app_colors.dart` (`AppColors` class). Never use inline color literals elsewhere in the codebase — always reference `AppColors.*`.

| Constant | Value | Usage |
|----------|-------|-------|
| `AppColors.darkBackground` | `#000B2E` | Dark scaffold background |
| `AppColors.darkSurface` | `#1A2A4A` | Dark elevated surfaces |
| `AppColors.lightBackground` | `#FDF9E4` | Light scaffold background |
| `AppColors.lightSurface` | `#EEEAD4` | Light elevated surfaces |
| `AppColors.brandRed` | `#FF4F4F` | "Vault" wordmark, errors, primary buttons |
| `AppColors.tealAccent` | `#48ECDF` | Primary interactive, loaders |
| `AppColors.onBrandRed` | `#FFFFFF` | Text/icons on brandRed backgrounds (`onPrimary`, `foregroundColor`) |

**Common violations to avoid:**
- `Colors.white` — use `AppColors.onBrandRed`
- `Colors.white.withValues(alpha: x)` — add a named constant to `AppColors`
- `Color(0xFFxxxxxx)` — always add to `AppColors` with a descriptive name
- `onPrimary: Colors.white` in `ThemeData` — use `AppColors.onBrandRed`

## Spacing

**All spacing goes through `AppSpacing.*` (`lib/core/theme/app_spacing.dart`) — never a bare number.** This is the spacing analogue of `AppColors`: gaps and paddings (`SizedBox` height/width, `EdgeInsets`, `separatorBuilder` gaps, `Wrap` spacing) must reference a token. Only non-spacing dimensions stay raw: icon/font sizes, `BorderRadius`/`Radius`, border `width`, `strokeWidth`, and fixed component sizes (avatars, drag handles, button heights, spinners).

**Top-level list tabs (Vaults, Agents, Inbox) MUST use `AppScreen.titled(title:, subtitle:, actions:, body:)`** — never a Material `AppBar`. The title renders via the shared `ListScreenHeader` **inside the body**, so the title→content rhythm is pixel-identical on every tab. A Material `AppBar` adds its own toolbar height + vertical centering, which makes the title→content gap differ from Vaults — that is a bug, not a style choice. `AppScreen.appBar(...)` is reserved for **pushed** screens that need a back button (detail pages); the plain `AppScreen(header:)` is legacy. Keep any `FabRegistrar` (`fab: null` to suppress a leaked FAB) passed via `floatingActionButton:`.

### Under-title control row — fixed size & alignment

The first control under the title (search bar **or** segment toggle) is a **single contract**, enforced so it can't drift:

- **Left/right edge:** horizontal `AppSpacing.screenH` (20) — the same gutter as the search bar. The segment toggle must align flush with the search bar.
- **Height:** `AppSpacing.controlHeight` (44). `AppSearchField` and the segment toggle are both this tall. Never hardcode a control height — reference `controlHeight`.
- **Title → control:** `headerGap` (16, owned by `ListScreenHeader`). **Control → content:** `fieldGap` (12).
- **Overflow / "more" actions** (when a tab strip has extra destinations, e.g. Inbox → Grants/Preferences) go in a trailing button at the **end of the segment row**, sized `controlHeight × controlHeight`, styled like the segment track — not hidden in an AppBar kebab. Pattern: `Row(children: [Expanded(toggle), SizedBox(sm), _OverflowButton])`.

### Tokens

| Token | Value | Use |
|-------|-------|-----|
| Raw scale | `xxs`=2, `xs`=4, `sm`=8, `md`=12, `lg`=16, `xl`=20, `xxl`=24, `xxxl`=32 | fall back here only when no semantic token fits |
| `screenH` | 20 | screen horizontal padding (the only screen gutter) |
| `headerGap` | 16 | header row → first content |
| `section` | 16 | between sections (vertical) |
| `fieldGap` | 12 | input↔input, search → content |
| `cardGap` | 10 | between cards / list separators |
| `cardPadding` | 14 | card internal padding |
| `innerGap` | 8 | elements inside a card |
| `chipGap` | 6 | between chips |
| `screenBottom` | 32 | last element → bottom (non-scrolling) |
| `listBottom` | 96 | scrollable list bottom (clears FAB + bottom nav) |
| `controlHeight` | 44 | height of an under-title control (search bar, segment toggle, overflow button) |

Prefer the semantic token over a raw step when one fits the context.

## Loading States — Skeleton Pattern

**Rule:** Skeletons go strictly in the list/content area (`Expanded`). Static chrome (header, page title, search bar) stays visible during loading.

```dart
// ✅ Correct
Column(
  children: [
    _HeaderRow(vaultCount: 0, entryCount: 0),  // always visible
    Expanded(
      child: switch (state) {
        Loading() => _SkeletonList(brightness: brightness),
        Loaded()  => _LoadedContent(...),
      },
    ),
  ],
)

// ❌ Wrong — replaces the entire view with skeletons
switch (state) {
  Loading() => _FullPageLoadingView(),  // hides header too
  Loaded()  => _LoadedView(),
}
```

**Examples:**
- `vault_list_page.dart`: `_SkeletonList` (skeleton cards only, header always above it)
- `vault_entries_tab.dart`: `AppSearchField` always rendered, only `Expanded` switches to `_LoadingView`

**Skeleton widget pattern:** `StatefulWidget` with `AnimationController`, `repeat(reverse: true)`, `Tween(0.4 → 0.85)` opacity. Use `SingleTickerProviderStateMixin`. Stagger multiple rows with `Future.delayed(Duration(milliseconds: i * 80))`.

## Error Handling

### Typed error enums in the service layer
Service-layer errors must use typed enums — not plain `Exception` with a hardcoded English string:

```dart
enum VaultIconUploadErrorKind { networkError, serverError, fileTooLarge }

class VaultIconUploadException implements Exception {
  final VaultIconUploadErrorKind kind;
  const VaultIconUploadException(this.kind);
}
```

Translate the enum to user-facing text **at the presentation layer** (where `BuildContext` is available), never inside the service or repository. This pattern is already established for auth errors (`AuthServerErrorKind`).

### Security-sensitive cleanup
When holding a copy of a sensitive value (private key bytes, decrypted payload) use `try/finally` to zero it out:

```dart
final keyCopy = Uint8List.fromList(privateKey);
try {
  // use keyCopy
} finally {
  keyCopy.fillRange(0, keyCopy.length, 0); // zero-out before GC
}
```

This applies to any crypto operation in `data/services/`. Do not return early from a function that holds a key copy without zeroing in the finally block.

## Analytics (PostHog)

```
mb:{module}:{event}
```

Mobile tracks **UI-only** events — page views, biometric usage, push taps. Business logic events are tracked by backend.
