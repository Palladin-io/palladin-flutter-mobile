# Palladin — Mobile App

Flutter mobile app for managing vaults, approving agent grants, and biometric unlock. Zero-knowledge architecture — all encryption/decryption happens on-device.

## Project Brain

Business and architecture knowledge for the project: `../brain/`

Key notes for this repository:
- `Technical/Mobile.md` — stack, flavors, BLoC, AppColors, i18n, conventions
- `Technical/Analytics Conventions.md` — PostHog, event format `mb:{module}:{event}`
- `Technical/Security Model.md` — zero-knowledge, on-device encryption
- `Product/Modules/Vault/` — Vault module: rules, API, onboarding flow
- `Product/Modules/Notification/Business Rules.md` — FCM/APNs, push tokens

Use `/brain` to navigate the brain, or: `grep -r "WORD" ../brain --include="*.md"`

**After a session that changes functionality, business rules, or architecture: update the relevant note in the brain.**

Repository: [Palladin-io/palladin-flutter-mobile](https://github.com/Palladin-io/palladin-flutter-mobile)

## Architecture Reference Docs

The **shared widget catalog lives in this file** (see "## Shared Widget Catalog" below — always loaded, so reuse is always at hand). `docs/architecture/` holds the per-feature structure docs.

**Reuse-first rule:** before building any widget, check the **Shared Widget Catalog** section below. If a shared widget exists, use it. If a pattern appears **2+ times**, extract it to `lib/core/widgets/` — duplicating an input/button/card/sheet style inline is a bug. Never inline `Color(0x..)` (use `AppColors.*`) or bare spacing numbers (use `AppSpacing.*`).

**Before implementing in a feature, read its architecture doc first** — it lists the cubit/bloc, existing pages and widgets, the data/domain/presentation layering, and cross-feature deps.

| Feature | Doc |
|---------|-----|
| Index + reuse philosophy | `docs/architecture/README.md` |
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
| autofill | `docs/architecture/features/autofill.md` |

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

Store testing is the one intentional exception to flavor/API matching: build
the `production` flavor with `PALLADIN_BACKEND_ENVIRONMENT=staging`. This keeps
the immutable store identity (`io.palladin.mobile`), production Firebase, and
production signing while targeting the staging API. Never upload the
`io.palladin.mobile.staging` package as the app that will later go to production.

### Android
- Product flavors in `android/app/build.gradle.kts` (`staging`, `production`)
- Firebase: place per-flavor `google-services.json` in `android/app/src/{flavor}/`

### iOS
- Schemes: `staging`, `production` (in `ios/Runner.xcodeproj/xcshareddata/xcschemes/`)
- Build configs: `Debug-{flavor}`, `Release-{flavor}`, `Profile-{flavor}`
- Xcconfig: `ios/Flutter/flavors/{flavor}.xcconfig`
- Firebase: place per-flavor `GoogleService-Info.plist` via xcconfig or build phase

## System Password Manager / AutoFill

System AutoFill on iOS and Android is required for MVP. The implementation must preserve the zero-knowledge boundary: the backend never receives plaintext credentials and system integrations may only decrypt on-device after explicit OS/user authorization.

Current implementation:
- `ios/CredentialProvider/` is an `ASCredentialProviderExtension` embedded in the Runner app.
- Runner and extension use the AutoFill entitlement and the per-flavor `APP_GROUP_IDENTIFIER` configured in Xcode/Apple Developer.
- iOS reads the explicit per-flavor `APP_GROUP_IDENTIFIER` from signed build configuration, stores only encrypted provider records in that App Group, and protects the dedicated cache key with `biometryCurrentSet` in the same App Group keychain access group. Never derive this identifier from a bundle ID.
- Android stores only encrypted provider records in `noBackupFilesDir` and protects the wrapping key with a biometric-bound Android Keystore key.
- Both providers fail closed without a normalized service domain. Android accepts a `webDomain` only from an Android 12+ package with an OS-verified App Link for that exact host or from the explicitly allowlisted, platform-authenticated system Chrome package; all other native/browser forms fail closed.
- System AutoFill behavior is tracked in Linear as **CVT-276** and documented in `docs/architecture/features/autofill.md`.

Security rules for all AutoFill work:
1. Never persist MK, VK, private keys, decrypted vault payloads, plaintext passwords, or TOTP seeds in App Groups, shared preferences, files, logs, analytics, or extension caches. A dedicated native AutoFill cache may persist only authenticated ciphertext encrypted with a random key unrelated to MK/VK.
2. AutoFill key sharing is limited to the explicit per-flavor App Group access group and requires biometric-set invalidation. Never reuse the app's normal keychain group or biometric-unlock key.
3. Match credentials against normalized service identifiers/domains and fail closed on ambiguous or mismatched domains.
4. A locked app/provider must return `userInteractionRequired`; never weaken authentication to make background AutoFill succeed.
5. Keep native provider code thin. Reuse the mobile crypto contract and wipe temporary plaintext/key buffers in `finally`/`defer` paths.
6. Treat any plaintext logging, broad shared-container storage, missing domain verification, or authentication bypass as a Critical blocking finding.

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

## Shared Widget Catalog

**Do not duplicate code.** Before writing any widget, check this catalog. If a shared widget exists, use it. If the same pattern appears twice, extract it to `lib/core/widgets/` and use it everywhere — duplicating the style of an input, button, or card is a bug.

### Core widgets — `lib/core/widgets/`

| Widget | File | Purpose / key params |
|--------|------|----------------------|
| `AppScreen` | `lib/core/widgets/app_screen.dart` | Gradient background + transparent Scaffold. `.titled(title, subtitle, actions, body)` for list tabs; `.appBar(appBar, body)` for pushed detail screens; default `(header, body)` is legacy. Also `floatingActionButton`, `endDrawer` |
| `ListScreenHeader` | `lib/core/widgets/list_screen_header.dart` | In-body title row used by `AppScreen.titled` (owns the `headerGap` below the title). Params: `title`, `subtitle`, `actions` |
| `AppSearchField` | `lib/core/widgets/app_search_field.dart` | Search input (wraps `OnboardingTextField`) with optional filter toggle (`tune` icon). Params: `controller`, `hint`, `onChanged`, `filterActive`, `onToggleFilter` |
| `SkeletonBox` | `lib/core/widgets/skeleton_box.dart` | The only skeleton primitive — never reimplement the opacity loop. Params: `height`, `borderRadius` (default 12), `delay` (stagger) |
| `SheetActionButtons` | `lib/core/widgets/sheet_action_buttons.dart` | Cancel (1×) + Confirm (2×) footer band for modal sheets. Params: `onCancel`, `onConfirm`, `confirmLabel`, `confirmColor`, `cancelLabel`, `busy` |
| `AppMenuSheet` | `lib/core/widgets/app_menu_sheet.dart` | `showAppMenuSheet<T>({title, items})` — native bottom-sheet action menu (the mobile "⋯" popover). `AppMenuItem<T>(value, icon, label, trailing?, danger, dividerBefore)`. Use for row/overflow menus instead of hand-rolling a sheet |
| `WarningZone` | `lib/core/widgets/warning_zone.dart` | Amber-bordered security warning box. Params: `title` (uppercase), `message` |
| `ApproveActionButton` | `lib/core/widgets/approve_action_button.dart` | Full-width green-tinted approve CTA. Params: `label`, `onPressed`, `icon`, `isLoading`, `height` (default 44) |
| `AppToggle` | `lib/core/widgets/app_toggle.dart` | Compact 32×18 pill toggle (brandRed when ON). Params: `value`, `onChanged` (null = locked/dimmed) |
| `AppFab` | `lib/core/widgets/app_fab.dart` | Brand-red 44×44 FAB with shadow, zero elevation. Params: `onPressed`, `tooltip` |
| `SheetDragHandle` | `lib/core/widgets/sheet_drag_handle.dart` | The 36×4 rounded pill at the top of a modal sheet. Use in new sheets; the ~17 inline copies migrate opportunistically |
| `FabRegistrar` | `lib/core/widgets/fab_registrar.dart` | 0×0 widget that claims the shell FAB slot for the current page. Param: `fab` (null = suppress a covered page's leaked FAB) |
| `AppBarTitle` | `lib/core/widgets/app_bar_title.dart` | Canonical pushed-screen AppBar title: 16/w700 name + optional 11px subtle subtitle (ellipsised). Params: `title`, `subtitle` (null/empty ⇒ title only). Use in every `AppBar(title:)` — never hand-roll the `Column(start, [Text, Text])` |
| `AppDropdownField` | `lib/core/widgets/app_dropdown_field.dart` | 44px bordered dropdown matching input height, generic `<T>`. Params: `label`, `value`, `items`, `onChanged`, `hint`, `enabled`, `filled` |
| `AppAutocompleteField` | `lib/core/widgets/app_autocomplete_field.dart` | Type-to-search autocomplete backed by `OnboardingTextField`, generic `<T extends Object>`. Params: `label`, `initialText`, `options`, `displayString`, `onSelected`, `onTextChanged` |
| `BrandHero` | `lib/core/widgets/brand_hero.dart` | Logo + "Palladin.io" wordmark (`.io` always brandRed). Param: `textColor`; static `BrandHero.textColorFor(brightness)` |
| `AuthBrandBackground` + `AuthContentWidth` | `lib/core/widgets/auth_brand_layout.dart` | Shared auth/confirmation frame: regular background plus brand glow, and centered 320px content width after the minimum screen gutters. Use with `AuthBrandHeader` so auth screens do not drift |
| `AuthLegalFooter` | `lib/core/widgets/auth_legal_footer.dart` | Localized Terms + Privacy footer for login and registration; opens the matching EN/PL palladin.io pages |
| `IconColorBrowserSheet` | `lib/core/widgets/icon_color_browser_sheet.dart` | Full icon + color picker bottom sheet. Params: `icons`, `colorOptions`, `initialIconKey`, `initialColor`, `title`, `confirmLabel`, `leadingTile`, `onPickCustom` |
| `IconPickerGrid` | `lib/core/widgets/icon_picker_grid.dart` | Grid of selectable icon tiles (used inside `IconColorBrowserSheet` and vault/entry icon pickers) |
| `MultiSelectDropdown` | `lib/core/widgets/multi_select_dropdown.dart` | Multi-select with chips, generic `<T>` (used in audit filter sheets) |
| `UploadIconButton` | `lib/core/widgets/upload_icon_button.dart` | Upload button with brandRed gradient shimmer label. Param: `onPressed`, upload state |

### Cross-feature widgets (live in a feature, reused by 2+ features)

These belong conceptually to `core` but currently sit in a feature folder. Reuse them as-is — do not duplicate.

| Widget | File | Purpose / reused by |
|--------|------|---------------------|
| `OnboardingTextField` + `FieldFeedbackSlot` | `lib/features/onboarding/presentation/widgets/onboarding_text_field.dart` | Primary 44px text input with label, border, and animated feedback slot below the input. Used by every feature with a form field (auth, onboarding, vault settings, recovery) |
| `PrimaryButton` | `lib/features/onboarding/presentation/widgets/primary_button.dart` | Brand-red full-width 44px CTA with loading state. Used in 14 files across 6 features — **should move to `lib/core/widgets/`** |
| `PasswordSecurityCheckController` + `resolvePasswordSecurityFeedback` + `PasswordSecurityStatusLine` | `lib/features/auth/presentation/widgets/password_security_status.dart` | Shared debounced HIBP state, presentation resolver, and compact one-line renderer. Registration reuses the resolver in its pinned copy; master-password screens use the line widget. Never duplicate breach-check state or message precedence |
| `AppBottomNav` | `lib/features/shell/presentation/widgets/app_bottom_nav.dart` | 5-slot bottom navigation bar with badge counts (used by `AppShell`) |
| `AgentAvatar` | `lib/features/agents/presentation/widgets/agent_avatar.dart` | Agent icon circle (tinted initials fallback or custom icon/color). Reused by grants (`OrgGrantCard`) + notifications (`NotificationCard`) |
| `AgentStatusBadge` | `lib/features/agents/presentation/widgets/agent_status_badge.dart` | Rounded status pill (pending/active/deactivated). Used by `AgentCard`, `AgentDetailBody` |
| `ApiKeyStatusBadge` | `lib/features/api_keys/presentation/widgets/api_key_status_badge.dart` | Status pill (active/revoked) — same shape as `AgentStatusBadge` |
| `AgentCard` | `lib/features/agents/presentation/widgets/agent_card.dart` | Tappable agent row (identity + footer zones) |
| `GrantDetailRow` | `lib/features/grants/presentation/widgets/org_grant_card.dart` (exported) | Fixed 76px label column + value text row. Used by `OrgGrantCard`, `NotificationCard` |

### Widgets to extract (missing shared widgets)

These patterns are duplicated and have **no** shared widget yet. Extract to `lib/core/widgets/` when next touching the affected code, then replace all instances. **Do not add another copy.**

- **Sheet drag handle (×17 files)** — `SheetDragHandle` now exists in `lib/core/widgets/` (used by `export_sheet`); the ~17 inline copies still need migrating: 7 private `_SheetHandle` classes (incl. one inside the core `icon_color_browser_sheet.dart`) + 10 inline 36×4 pills in approval (`approve_grant_sheet`, `deny_grant_sheet`, `grant_access_sheet`, `grant_methods_selector`, `regrant_sheet`), audit (`audit_legend_sheet`, `audit_log_filter_sheet`, `entry_logs_filter_sheet`), grants (`revoke_grant_sheet`), and `vault_list_page`. Replace with the shared widget on next touch.
- **Status pills (×2)** — `AgentStatusBadge` ≡ `ApiKeyStatusBadge` → extract `StatusPill({label, color})` (bg = `color.withValues(alpha:0.12)`, border = `alpha:0.5`, text 10/w700).
- **Label/value rows (×2)** — `_DetailRow` in `api_key_details_tab.dart` + `agent_detail_body.dart` → extract `LabelValueRow`.
- **Empty cards (×3)** — `_AgentsEmpty` (agents_page), `_KeysEmpty` (api_keys_page), `_EmptyCard` (notification_center_page) → extract `ListEmptyCard({icon, title, hint})`.
- **Move `PrimaryButton`** out of `features/onboarding/` into `lib/core/widgets/` — used in 14 files / 6 features; update all import paths.

### Skeleton reimplementations to replace

`SkeletonBox` is the canonical primitive, but two screens still ship their own `StatefulWidget` + `AnimationController` + `Tween(0.4, 0.85)`: `vault_list_page.dart` (`_SkeletonCard`) and `vault_entries_tab.dart` (`_SkeletonRow`). Replace both with `SkeletonBox(height: X, delay: Duration(milliseconds: i * 80))`.

### Screen titles — ALWAYS left-aligned

**Every screen title sits on the LEFT edge of the AppBar/header — never centered.** This is a hard product rule (recurring user finding, last: Import wizard centered on iOS).

- **Pushed screens** (`AppScreen.appBar`): `AppBar` MUST set `titleSpacing: 0` **and** `centerTitle: false` — without `centerTitle: false` iOS silently centers the title. Title widget = shared `AppBarTitle(title:, subtitle:)` (16/w700 + 11px subtle subtitle, e.g. screen name + vault name). Never hand-roll the title `Column`.
- **Top-level tabs**: `AppScreen.titled(...)` (in-body `ListScreenHeader`, inherently left-aligned).
- Decorative/context icons (e.g. the red upload glyph on the Import wizard) go on the **right** as `actions:` (padded `AppSpacing.screenH` from the edge) — never above/inside the body header.

### Reuse rules

1. **Colors** — only `AppColors.*` (`lib/core/theme/app_colors.dart`). Never `Color(0x..)`, `Colors.white`, or a hex literal anywhere outside that file.
2. **Spacing** — only `AppSpacing.*` (`lib/core/theme/app_spacing.dart`). No bare numbers in `SizedBox`, `EdgeInsets`, separator gaps, or `Wrap` spacing. Non-spacing dimensions (icon/font sizes, radii, border width, fixed component sizes like the 36×4 drag handle) stay raw.
3. **Screens** — top-level list tabs use `AppScreen.titled(...)`; pushed detail screens use `AppScreen.appBar(...)`. Never hand-roll `Container(gradient) + Scaffold(transparent)`.
4. **Skeletons** — use `SkeletonBox`; never reimplement an `AnimationController` opacity loop.
5. **Sheets** — footer actions via `SheetActionButtons`; drag handle via the shared `SheetDragHandle` (extract on first touch — do not add an 18th copy).
6. **Inputs** — `OnboardingTextField` for text, `AppSearchField` for search, `AppDropdownField` for dropdowns, `AppAutocompleteField` for autocomplete. Never re-style an input inline.
7. **Buttons** — `PrimaryButton` for the primary CTA, `ApproveActionButton` for approve actions, `AppFab` for floating actions. Never build a bare `ElevatedButton` with inline brand styling.

## Theming & Colors

**Theme mode:** The app supports both light and dark mode. Default is dark. User can change it in settings — preference is persisted. Never hardcode `ThemeMode.dark` permanently; use the stored user preference.

**Color palette:** All colors must be defined in `lib/core/theme/app_colors.dart` (`AppColors` class). Never use inline color literals elsewhere in the codebase — always reference `AppColors.*`.

| Constant | Value | Usage |
|----------|-------|-------|
| `AppColors.darkBackground` | `#15171B` | Dark scaffold background — deep graphite |
| `AppColors.darkSurface` | `#20242C` | Dark elevated surfaces |
| `AppColors.mobileSurface` | `#23262C` | Graphite card background (vault list/detail) |
| `AppColors.lightBackground` | `#E8EAED` | Light scaffold background — warm cream |
| `AppColors.lightSurface` | `#DCDEE2` | Light elevated surfaces |
| `AppColors.brandRed` | `#EB4747` | Primary/interactive color: "Vault" wordmark, errors, primary buttons, **all interactive actions** (links, Retry, button foregrounds), **active/focused inputs**, loaders |
| `AppColors.positiveAccent` | `#10B981` | Success / positive green — password-strength "strong/veryStrong", positive states. **Same green as web (`--cv-success`); web↔mobile parity. NEVER use teal (`#48ECDF`) or `#2EC4B6` as the success green.** |
| `AppColors.onBrandRed` | `#FFFFFF` | Text/icons on brandRed backgrounds (`onPrimary`, `foregroundColor`) |

Brightness-aware semantic colors are static methods (`AppColors.onSurface(brightness)`, `cardFill(brightness)`, `modalBackground(brightness)`, etc.), not consts. The full background is `AppColors.backgroundGradient(brightness)`.

**Common violations to avoid:**
- `Colors.white` — use `AppColors.onBrandRed`
- `Colors.white.withValues(alpha: x)` — add a named constant to `AppColors`
- `Color(0xFFxxxxxx)` — always add to `AppColors` with a descriptive name
- `onPrimary: Colors.white` in `ThemeData` — use `AppColors.onBrandRed`

**Audit Log colors:** when touching Audit Log UI (event colors, legend, badges), load the canonical taxonomy: **`../.agents/memory/reference_audit_log_colors.md`** (monorepo memory). Roles map to `AppColors`: `positiveAccent` (#10B981 success), `vaultPeach` (#FFAB87 = pending / `grant.requested`), `vaultBlue` (#60A5FA info), `brandRed` (danger), `textTertiary` (#8A95A6 neutral). Consumed in `lib/features/audit/.../audit_log_format.dart`. Web ↔ mobile parity required; `agent.enrolled` = vaultBlue, `agent.reactivated` = positiveAccent.

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

## Maintaining this file

Pull-request review automation is Codex-only. Keep the workflow at `.github/workflows/codex-pr-review.yml`, its support files under `.github/codex/`, and review skills under `.agents/`; do not add Claude Code PR workflows or `.claude/skills/pr-review` / `.claude/skills/fix-pr` adapters.

This file is **always loaded** into context, so keep it lean. Only guidance useful in **every** iteration belongs here — the shared widget catalog, tokens (`AppColors`/`AppSpacing`), screen/skeleton/error conventions, the reuse rules.

- **Deep or concern-specific guidance** (per-feature structure, cubits, cross-feature deps, architecture smells) lives in `docs/architecture/` — the per-feature docs under `docs/architecture/features/`. Add a **one-line pointer** from this file rather than inlining the detail.
- **Extend this file autonomously** as conventions emerge: a new shared widget, a renamed/changed token, or a new screen contract → add it to the catalog or the relevant section in the same PR that introduces it.
- **PR reviewers must check whether a code change requires updating `AGENTS.md` or a `docs/architecture/` doc** (new shared widget, changed token/convention, new feature). Doc drift is a review finding.
- `AGENTS.md` and `CLAUDE.md` are intentionally maintained as complete, byte-for-byte identical copies by product-owner decision. Every instruction change must update both files in the same commit and verify them with `cmp`.
