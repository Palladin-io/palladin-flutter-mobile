# Palladin — Mobile App

Flutter mobile app for managing vaults, approving agent grants, and biometric unlock. Zero-knowledge architecture — all encryption/decryption happens on-device.

## Project Brain

Wiedza biznesowa i architektoniczna projektu: `../docs/obsidian/palladin/`

Kluczowe noty dla tego repozytorium:
- `Technical/Mobile.md` — stack, flavory, BLoC, AppColors, i18n, konwencje
- `Technical/Analytics Conventions.md` — PostHog, format zdarzeń `mb:{module}:{event}`
- `Technical/Security Model.md` — zero-knowledge, szyfrowanie on-device
- `Product/Modules/Vault/` — Vault module: reguły, API, onboarding flow
- `Product/Modules/Notification/Business Rules.md` — FCM/APNs, push tokens

Użyj `/brain` żeby nawigować po brain lub: `grep -r "SŁOWO" ../docs/obsidian/palladin --include="*.md"`

**Po sesji która zmienia funkcjonalność, reguły biznesowe lub architekturę: zaktualizuj odpowiednią notę w brain.**

Repository: [Flamingo-Co/palladin-flutter-mobile](https://github.com/Flamingo-Co/palladin-flutter-mobile)

## Architecture Reference Docs

`docs/architecture/` is the source of truth for shared widgets and per-feature structure.

**Reuse-first rule:** before building any widget, check [`docs/architecture/widget-catalog.md`](docs/architecture/widget-catalog.md). If a shared widget exists, use it. If a pattern appears **2+ times**, extract it to `lib/core/widgets/` — duplicating an input/button/card/sheet style inline is a bug. Never inline `Color(0x..)` (use `AppColors.*`) or bare spacing numbers (use `AppSpacing.*`).

**Before implementing in a feature, read its architecture doc first** — it lists the cubit/bloc, existing pages and widgets, the data/domain/presentation layering, and cross-feature deps.

| Feature | Doc |
|---------|-----|
| Index + reuse philosophy | `docs/architecture/README.md` |
| Shared widget catalog | `docs/architecture/widget-catalog.md` |
| auth | `docs/architecture/features/auth.md` |
| unlock | `docs/architecture/features/unlock.md` |
| onboarding | `docs/architecture/features/onboarding.md` |
| recovery | `docs/architecture/features/recovery.md` |
| shell | `docs/architecture/features/shell.md` |
| vault | `docs/architecture/features/vault.md` |
| agents | `docs/architecture/features/agents.md` |
| approval | `docs/architecture/features/approval.md` |
| grants | `docs/architecture/features/grants.md` |
| notifications | `docs/architecture/features/notifications.md` |
| audit | `docs/architecture/features/audit.md` |
| settings | `docs/architecture/features/settings.md` |
| api_keys | `docs/architecture/features/api_keys.md` |

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
| Bundle ID | `io.palladin.mobile.local` | `io.palladin.mobile.staging` | `io.palladin.mobile` |
| App name | Palladin (Local) | Palladin (Stage) | Palladin |
| API URL | `http://localhost:5000` | `https://api.stage.palladin.io` | `https://api.palladin.io` |

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

### Full widget catalog

The table above lists only a few. The full inventory lives in [`docs/architecture/widget-catalog.md`](docs/architecture/widget-catalog.md). Most-used shared widgets:

| Widget | Location | Use |
|--------|----------|-----|
| `AppScreen` | `lib/core/widgets/app_screen.dart` | Gradient + transparent Scaffold. `.titled(...)` for list tabs, `.appBar(...)` for pushed screens |
| `ListScreenHeader` | `lib/core/widgets/list_screen_header.dart` | In-body title row used by `AppScreen.titled` |
| `SkeletonBox` | `lib/core/widgets/skeleton_box.dart` | The only skeleton primitive — never reimplement the opacity loop |
| `SheetActionButtons` | `lib/core/widgets/sheet_action_buttons.dart` | Cancel + Confirm footer band for modal sheets |
| `WarningZone` | `lib/core/widgets/warning_zone.dart` | Amber security-warning box |
| `ApproveActionButton` | `lib/core/widgets/approve_action_button.dart` | Full-width green approve CTA |
| `AppToggle` | `lib/core/widgets/app_toggle.dart` | Compact 32×18 pill toggle |
| `AppFab` | `lib/core/widgets/app_fab.dart` | Brand-red 44×44 FAB |
| `FabRegistrar` | `lib/core/widgets/fab_registrar.dart` | Claims the shell FAB slot for the current page (`fab: null` suppresses) |
| `AppDropdownField` | `lib/core/widgets/app_dropdown_field.dart` | 44px bordered dropdown `<T>` |
| `AppAutocompleteField` | `lib/core/widgets/app_autocomplete_field.dart` | Type-to-search autocomplete `<T>` |
| `BrandHero` | `lib/core/widgets/brand_hero.dart` | Logo + "Palladin.io" wordmark |
| `IconColorBrowserSheet` | `lib/core/widgets/icon_color_browser_sheet.dart` | Icon + color picker bottom sheet |
| `MultiSelectDropdown` | `lib/core/widgets/multi_select_dropdown.dart` | Multi-select with chips `<T>` |
| `PrimaryButton` | `lib/features/onboarding/presentation/widgets/primary_button.dart` | Brand-red full-width CTA with loading state (used app-wide — pending move to `core/widgets/`) |
| `AgentAvatar` | `lib/features/agents/presentation/widgets/agent_avatar.dart` | Agent icon circle (reused by grants + notifications) |
| `AgentStatusBadge` / `ApiKeyStatusBadge` | `lib/features/agents/.../agent_status_badge.dart`, `lib/features/api_keys/.../api_key_status_badge.dart` | Status pills (identical shape — extract `StatusPill`) |

### Widgets to reuse, not re-implement

Known duplications — **use or extract the shared widget; do not add another copy.** Full counts + target files in [`docs/architecture/widget-catalog.md`](docs/architecture/widget-catalog.md).

- **Sheet drag handle (×15)** — 6 private `_SheetHandle` classes + 9 inline 36×4 pills → extract `SheetDragHandle` to `lib/core/widgets/`.
- **AppBar title (×6)** — `Column(name 16/w700 + subtitle 11/subtle)` duplicated across detail/settings pages → extract `AppBarTitle`.
- **Status pills (×2)** — `AgentStatusBadge` ≡ `ApiKeyStatusBadge` → extract `StatusPill({label, color})`.
- **Label/value rows (×2)** — `_DetailRow` in api_keys + agents → extract `LabelValueRow`.
- **Empty cards (×3)** — `_AgentsEmpty`, `_KeysEmpty`, `_EmptyCard` → extract `ListEmptyCard`.
- **Skeletons reimplemented (×2)** — `_SkeletonCard` (vault_list), `_SkeletonRow` (vault_entries_tab) hand-roll `AnimationController` → use `SkeletonBox`.

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

**Audit Log colors:** when touching Audit Log UI (event colors, legend, badges), load the canonical taxonomy: **`../.claude/memory/reference_audit_log_colors.md`** (monorepo memory). Roles map to `AppColors`: `positiveAccent` (#10B981 success), `vaultPeach` (#FFAB87 = pending / `grant.requested`), `vaultBlue` (#60A5FA info), `brandRed` (danger), `textTertiary` (#8A95A6 neutral). Consumed in `lib/features/audit/.../audit_log_format.dart`. Web ↔ mobile parity required; `agent.enrolled` = vaultBlue, `agent.reactivated` = positiveAccent.

## Spacing

**All spacing goes through `AppSpacing.*` (`lib/core/theme/app_spacing.dart`) — never a bare number.** This is the spacing analogue of `AppColors`: gaps and paddings (`SizedBox` height/width, `EdgeInsets`, `separatorBuilder` gaps, `Wrap` spacing) must reference a token. Only non-spacing dimensions stay raw: icon/font sizes, `BorderRadius`/`Radius`, border `width`, `strokeWidth`, and fixed component sizes (avatars, drag handles, button heights, spinners).

**Top-level list tabs (Vaults, Agents, Inbox) MUST use `AppScreen.titled(title:, subtitle:, actions:, body:)`** — never a Material `AppBar`. The title renders via the shared `ListScreenHeader` **inside the body**, so the title→content rhythm is pixel-identical on every tab. A Material `AppBar` adds its own toolbar height + vertical centering, which makes the title→content gap differ from Vaults — that is a bug, not a style choice. `AppScreen.appBar(...)` is reserved for **pushed** screens that need a back button (detail pages); the plain `AppScreen(header:)` is legacy. Keep any `FabRegistrar` (`fab: null` to suppress a leaked FAB) passed via `floatingActionButton:`.

### Under-title control row — fixed size & alignment

The first control under the title (search bar **or** segment toggle) is a **single contract**, enforced so it can't drift:

- **Left/right edge:** horizontal `AppSpacing.screenH` (20) — the same gutter as the search bar. The segment toggle must align flush with the search bar.
- **Height:** `AppSpacing.controlHeight` (44). `AppSearchField` and the segment toggle are both this tall. Never hardcode a control height — reference `controlHeight`.
- **Title → control:** `headerGap` (16, owned by `ListScreenHeader`). **Control → content:** `fieldGap` (12).
- **Overflow / "more" actions** (when a tab strip has extra destinations, e.g. Inbox → Grants/Preferences) go in a trailing button at the **end of the segment row**, sized `controlHeight × controlHeight`, styled like the segment track — not hidden in an AppBar kebab. Pattern: `Row(children: [Expanded(toggle), SizedBox(sm), _OverflowButton])`.

### Control scrolls WITH the content — only the title is pinned

On a list screen the search bar **and** the segment toggle row **scroll together with the list** — they are the leading slivers of one `CustomScrollView`, never pinned above a separate `Expanded(scroll)`. **Only the title** (via `AppScreen.titled`) stays pinned. Canonical reference: `vault_list_page.dart` → `CustomScrollView(slivers: [SliverToBoxAdapter(AppSearchField), …])`.

**Why:** a pinned control over a separate scroll area exposes a strip of background between the control and the list during an upward overscroll/bounce. Keeping the control inside the same scrollable makes it simply scroll away with the content, so no gap can appear.

**Pattern for every list screen:**
- `AppScreen.titled(... body: <scroll view that includes the control as its first sliver>)`.
- Inbox: the segment row + overflow button **and** the search field are a single leading `SliverToBoxAdapter`; pagination (`ScrollEndNotification` → `loadMore`) wraps the whole `CustomScrollView`.
- Per-state content (skeleton / error / empty / list) renders as **slivers below the control** — `SliverList.list` for skeleton/error cards, `SliverFillRemaining(hasScrollBody: false)` for centred empty/search-empty states, `SliverList.separated` for the cards.
- A tab that is not itself an `AppScreen` (e.g. `vault_entries_tab.dart`) follows the same rule inside its host's scroll area: search is the first sliver of the tab's own `CustomScrollView`.

**Never** put a search bar or segment row in a `Column` above an `Expanded(child: <scroll>)` on a list screen — that is the gap bug, not a style choice.

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

**Rule:** Skeletons replace **only the list/content area** — the pinned **title** (via `AppScreen.titled`) stays visible during loading. The skeleton renders as a **sliver inside the same `CustomScrollView`** as the (scrolling) search bar / segment row, matching the Vaults pattern. On a list screen the search bar is **not** separate static chrome above the content — it scrolls with the list (see "Control scrolls WITH the content" above), so during loading it sits as the first sliver and the skeleton slivers follow it. It is acceptable for the search bar to scroll off with the rest of the content, exactly as Vaults does.

```dart
// ✅ Correct — one CustomScrollView; title pinned by AppScreen.titled,
//    search + skeleton are slivers that scroll together.
AppScreen.titled(
  title: ...,
  body: CustomScrollView(
    slivers: [
      SliverToBoxAdapter(child: AppSearchField(...)),  // scrolls with content
      ...switch (state) {
        Loading() => const [_SkeletonSliver()],
        Loaded()  => _loadedSlivers(...),
      },
    ],
  ),
)

// ❌ Wrong — pinned search above a separate Expanded(scroll): overscroll
//    exposes a background strip between the search bar and the list.
Column(children: [AppSearchField(...), Expanded(child: switch (state) { ... })])
```

**Examples:**
- `vault_list_page.dart`: `_SkeletonList` rendered inside the loaded scroll view; title pinned above it.
- `agents_page.dart`: `_AgentsSkeletonSliver` after the search `SliverToBoxAdapter`.
- `vault_entries_tab.dart`: `_LoadingSliver` after the search `SliverToBoxAdapter`.
- `notification_center_page.dart`: `_SkeletonSliver` after the leading segment-row + search header sliver.

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
