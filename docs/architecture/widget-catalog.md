# Shared Widget Catalog

The complete inventory of reusable widgets. **Check here before building any widget.** Paths are relative to the repo root.

## `lib/core/widgets/`

| Widget | File | Purpose | Key params / variants |
|--------|------|---------|-----------------------|
| `AppScreen` | `lib/core/widgets/app_screen.dart` | Background gradient + transparent `Scaffold` in one widget. The base for every screen. | `.titled(title, subtitle, actions, body)` for top-level list tabs; `.appBar(appBar, body)` for pushed detail screens; default `(header, body)` is legacy. Also `floatingActionButton`, `endDrawer`, `gapAfterHeader` |
| `ListScreenHeader` | `lib/core/widgets/list_screen_header.dart` | Canonical in-body title row for top-level list screens. | `title`, `subtitle`, `actions`. Used internally by `AppScreen.titled` — owns the `headerGap` (16) below the title |
| `AppSearchField` | `lib/core/widgets/app_search_field.dart` | Search input (wraps `OnboardingTextField`) with optional filter toggle. | `controller`, `hint`, `onChanged`, `filterActive`, `onToggleFilter` (shows `tune` icon) |
| `SkeletonBox` | `lib/core/widgets/skeleton_box.dart` | Pulsing skeleton placeholder (0.4→0.85 opacity loop). **The only skeleton primitive — never reimplement.** | `height`, `borderRadius` (default 12), `delay` (stagger) |
| `SheetActionButtons` | `lib/core/widgets/sheet_action_buttons.dart` | Cancel (1×) + Confirm (2×) footer band for modal sheets. | `onCancel`, `onConfirm`, `confirmLabel`, `confirmColor`, `cancelLabel`, `busy` |
| `WarningZone` | `lib/core/widgets/warning_zone.dart` | Amber-bordered security warning box. | `title` (uppercase), `message` |
| `ApproveActionButton` | `lib/core/widgets/approve_action_button.dart` | Full-width green-tinted approve CTA. | `label`, `onPressed`, `icon`, `isLoading`, `height` (default 44) |
| `AppToggle` | `lib/core/widgets/app_toggle.dart` | Compact 32×18 pill toggle (brandRed when ON). | `value`, `onChanged` (null = locked/dimmed) |
| `AppFab` | `lib/core/widgets/app_fab.dart` | Brand-red 44×44 FAB with shadow, zero elevation. | `onPressed`, `tooltip` |
| `FabRegistrar` | `lib/core/widgets/fab_registrar.dart` | 0×0 invisible widget that claims the shell FAB slot for the current page. | `fab` (null = suppress a covered page's leaked FAB) |
| `AppDropdownField` | `lib/core/widgets/app_dropdown_field.dart` | 44px bordered dropdown matching input height. Generic `<T>`. | `label`, `value`, `items`, `onChanged`, `hint`, `enabled`, `filled` |
| `AppAutocompleteField` | `lib/core/widgets/app_autocomplete_field.dart` | Type-to-search autocomplete backed by `OnboardingTextField`. Generic `<T extends Object>`. | `label`, `initialText`, `options`, `displayString`, `onSelected`, `onTextChanged` |
| `BrandHero` | `lib/core/widgets/brand_hero.dart` | Logo + "Palladin.io" wordmark (`.io` always brandRed). | `textColor`; static `BrandHero.textColorFor(brightness)` |
| `IconColorBrowserSheet` | `lib/core/widgets/icon_color_browser_sheet.dart` | Full icon + color picker bottom sheet. | `icons`, `colorOptions`, `initialIconKey`, `initialColor`, `title`, `confirmLabel`, `leadingTile`, `onPickCustom` |
| `IconPickerGrid` | `lib/core/widgets/icon_picker_grid.dart` | Grid of selectable icon tiles. | Used within `IconColorBrowserSheet` and vault/entry icon pickers |
| `MultiSelectDropdown` | `lib/core/widgets/multi_select_dropdown.dart` | Multi-select with chips. Generic `<T>`. | Used in audit filter sheets |
| `UploadIconButton` | `lib/core/widgets/upload_icon_button.dart` | Upload button with brandRed gradient shimmer label. | `onPressed`, upload state |

## Cross-feature widgets (live in a feature, reused by 2+ features)

These belong conceptually to `core` but currently sit in a feature folder. Reuse them as-is; do not duplicate.

| Widget | File | Purpose | Reused by |
|--------|------|---------|-----------|
| `OnboardingTextField` + `FieldFeedbackSlot` | `lib/features/onboarding/presentation/widgets/onboarding_text_field.dart` | Primary 44px text input with label, border, and animated feedback slot. | Every feature with a form field |
| `PrimaryButton` | `lib/features/onboarding/presentation/widgets/primary_button.dart` | Brand-red full-width 44px `ElevatedButton` with loading state. | 14 files across api_keys, recovery, settings, vault, unlock, onboarding — **should move to `lib/core/widgets/`** |
| `AppBottomNav` | `lib/features/shell/presentation/widgets/app_bottom_nav.dart` | 5-slot nav bar with badge counts. | `AppShell` |
| `AgentAvatar` | `lib/features/agents/presentation/widgets/agent_avatar.dart` | Agent icon circle (tinted initials fallback, or custom icon/color). | agents, grants (`OrgGrantCard`), notifications (`NotificationCard`) |
| `AgentStatusBadge` | `lib/features/agents/presentation/widgets/agent_status_badge.dart` | Rounded status pill (pending/active/deactivated). | `AgentCard`, `AgentDetailBody` |
| `ApiKeyStatusBadge` | `lib/features/api_keys/presentation/widgets/api_key_status_badge.dart` | Status pill (active/revoked) — same shape as `AgentStatusBadge`. | `ApiKeyCard`, `ApiKeyDetailsTab` |
| `AgentCard` | `lib/features/agents/presentation/widgets/agent_card.dart` | Tappable agent row (identity + footer zones). | agents list + split-view detail pane |
| `GrantDetailRow` | `lib/features/grants/presentation/widgets/org_grant_card.dart` (exported) | Fixed 76px label column + value text row. | `OrgGrantCard`, `NotificationCard` |

## Widgets to extract (missing shared widgets)

These patterns are duplicated and have **no** shared widget yet. Extract to `lib/core/widgets/` when next touching the affected code, then replace all instances.

| Proposed widget | Duplication count | Where | What it should be |
|-----------------|-------------------|-------|-------------------|
| `SheetDragHandle` → `lib/core/widgets/sheet_drag_handle.dart` | **15** (6 private `_SheetHandle` classes + 9 inline) | `delete_api_key_sheet.dart`, `revoke_api_key_sheet.dart`, `generate_api_key_sheet.dart`, `deactivate_agent_sheet.dart`, `approve_agent_sheet.dart`, `create_vault_sheet.dart` (private classes); `revoke_grant_sheet.dart`, `approve_grant_sheet.dart`, `regrant_sheet.dart`, `deny_grant_sheet.dart`, `grant_methods_selector.dart`, `audit_log_filter_sheet.dart`, `audit_legend_sheet.dart`, `entry_logs_filter_sheet.dart`, `vault_list_page.dart` (inline) | Centered 36×4 pill, `AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.4)`, radius 2 |
| `AppBarTitle` → `lib/core/widgets/app_bar_title.dart` | **6** | `vault_detail_page.dart` (`_DetailAppBar`), `entry_detail_page.dart` (`_EntryDetailAppBar`), `api_keys_page.dart` (inline), `api_key_detail_page.dart` (`_AppBarTitle`), `agent_detail_page.dart` (`_AppBarTitle`), `settings_page.dart` (inline) | `Column(start, [Text(title,16/w700), Text(subtitle,11/subtle)])` |
| `StatusPill` → `lib/core/widgets/status_pill.dart` | **2** (badges) | `agent_status_badge.dart`, `api_key_status_badge.dart` | `StatusPill({label, color})`; bg = `color.withValues(alpha:0.12)`, border = `alpha:0.5`, text 10/w700/letterSpacing 0.3 |
| `LabelValueRow` → `lib/core/widgets/label_value_row.dart` | **2** (`_DetailRow`) | `api_key_details_tab.dart:303`, `agent_detail_body.dart:855` | `Row(spaceBetween, [Text(label,12/subtle), Text(value,12/w600)])` + optional `mono` |
| `ListEmptyCard` → `lib/core/widgets/list_empty_card.dart` | **3** | `_AgentsEmpty` (`agents_page.dart`), `_KeysEmpty` (`api_keys_page.dart`), `_EmptyCard` (`notification_center_page.dart`) | `ListEmptyCard({icon, title, hint})` — icon + title + hint inside a surface card |
| **Move** `PrimaryButton` → `lib/core/widgets/primary_button.dart` | used in **14** files / 6 features | currently `lib/features/onboarding/presentation/widgets/primary_button.dart` | Same widget, relocated out of the onboarding feature; update all 14 import paths |

## Skeleton reimplementations to replace

`SkeletonBox` (`lib/core/widgets/skeleton_box.dart`) is the canonical skeleton primitive, but two screens still ship their own `StatefulWidget` + `AnimationController` + `Tween(0.4, 0.85)`:

- `vault_list_page.dart` → `_SkeletonCard` (~lines 560–592)
- `vault_entries_tab.dart` → `_SkeletonRow` (~lines 302–355)

Replace both with `SkeletonBox(height: X, delay: Duration(milliseconds: i * 80))`.

## Reuse rules

1. **Colors** — only `AppColors.*` (`lib/core/theme/app_colors.dart`). Never `Color(0x..)`, `Colors.white`, or a hex literal anywhere outside that file.
2. **Spacing** — only `AppSpacing.*` (`lib/core/theme/app_spacing.dart`). No bare numbers in `SizedBox` height/width, `EdgeInsets`, separator gaps, or `Wrap` spacing. Non-spacing dimensions (icon/font sizes, radii, border width, fixed component sizes like the 36×4 drag handle) stay raw.
3. **Screens** — top-level list tabs use `AppScreen.titled(...)` (title via `ListScreenHeader` inside the body). Pushed detail screens use `AppScreen.appBar(...)`. Never hand-roll `Container(gradient) + Scaffold(transparent)`.
4. **Skeletons** — use `SkeletonBox`. Never reimplement an `AnimationController` opacity loop.
5. **Sheets** — footer actions via `SheetActionButtons`; drag handle via the shared `SheetDragHandle` (extract it on first touch — do not add a 16th copy).
6. **Status pills, label/value rows, empty cards, AppBar titles** — reuse or extract the shared widget listed above; do not inline another copy.
7. **Inputs** — `OnboardingTextField` for text, `AppSearchField` for search, `AppDropdownField` for dropdowns, `AppAutocompleteField` for autocomplete. Never re-style an input inline.
8. **Buttons** — `PrimaryButton` for the primary CTA, `ApproveActionButton` for approve actions, `AppFab` for floating actions. Never build a bare `ElevatedButton` with inline brand styling.
