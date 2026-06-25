---
name: patterns-spacing-system
description: AppSpacing token system + AppScreen wrapper — never use bare numeric gaps/paddings
metadata:
  type: project
---

Spacing is centralized like colors. Two pieces:

**`AppSpacing` (`lib/core/theme/app_spacing.dart`)** — single source of truth for all
gaps/paddings. Never write a bare number in a spacing position (`SizedBox` h/w,
`EdgeInsets`, `separatorBuilder` gaps, `Wrap` spacing/runSpacing).
- Raw 4-pt scale: `xxs`=2, `xs`=4, `sm`=8, `md`=12, `lg`=16, `xl`=20, `xxl`=24, `xxxl`=32.
- Semantic (prefer these): `screenH`=20 (the only screen gutter), `headerGap`=16,
  `section`=16, `fieldGap`=12 (input↔input / search→content), `cardGap`=10 (between cards /
  list separators), `cardPadding`=14 (card internal padding), `innerGap`=8 (elements in a
  card), `chipGap`=6, `screenBottom`=32 (static bottom), `listBottom`=96 (scrollable list
  bottom, clears FAB+nav).

**NOT spacing — leave raw:** icon/font sizes, `BorderRadius`/`Radius`, border `width`,
`strokeWidth`, fixed component dims (avatar 40×40, drag-handle 36×4, spinner 14×14, button
heights 44/36/52, FAB markers 0×0, `SkeletonBox` heights), durations, alpha.

**`AppScreen` (`lib/core/widgets/app_screen.dart`)** — shared skeleton for top-level screens:
owns gradient bg, transparent `Scaffold`, `SafeArea`, header slot, `headerGap`.
- `AppScreen.appBar(appBar:, body:, floatingActionButton:, endDrawer:, gapAfterHeader:)` for
  AppBar-over-gradient screens (Inbox/Agents/Settings/ApiKeys/InboxGrants pattern).
- `AppScreen(header:, body:, gapAfterHeader:)` for a custom in-body header (Vault list).
- **Both variants now default `gapAfterHeader: true`** — AppScreen.appBar inserts a
  `SizedBox(headerGap)` below the AppBar so title→content is ALWAYS 16 on every screen.
  Bodies of AppScreen.appBar consumers must NOT add their own top padding (set list/body
  top to 0) or you double the gap. Set `gapAfterHeader: false` only when the body owns the
  leading gap itself (e.g. agent_detail_page, where the shared AgentDetailBody owns the
  title→tabs gap so split-pane + pushed page match).
- Keep AppBar transparent config and any `FabRegistrar` exactly. Pages with a `Stack`+
  `Positioned(0,0)` FabRegistrar marker convert fine (put the Stack as `body:`); pages that
  own the shell bottom-nav FAB pattern (vault_list, api_keys) — vault_list stays custom
  Scaffold (bottom-nav FAB + custom header), api_keys converted to AppScreen.appBar.

**CANONICAL VERTICAL RHYTHM (enforce on every top-level/list screen):**
- page title (AppBar/custom header) → next (tabs/search/content): **headerGap (16)**
- tab/segment bar → next (search or content): **fieldGap (12)**
- search → first result / empty-state card: **fieldGap (12)**
- between cards / list separators: **cardGap (10)**
- scrollable list bottom: **listBottom (96)**; static bottom: **screenBottom (32)**
Empty-states sit as a card at the top fieldGap below the search (NOT vertically centered),
unless the screen has no search. Inner state views (skeleton/error/empty/list) under a
search/header carry top=0 — the leading gap is owned by the search bar / header / AppScreen.

`ContextGrantsTab` default `contentPadding` top = 0 (leading gap owned by host: AppScreen,
tab bar, or TabBarView wrapper). vault_detail/entry_detail tab→content = fieldGap (12),
owned by the TabBarView wrapper (vault) or each tab's own top (entry).

AppBar title→subtitle micro-gap is `AppSpacing.xs` (4) across all screens (was raw 3 on
agents/agent_detail — unified). Segmented-control track inset `EdgeInsets.all(3)` and the
log-timeline bullet `margin top:5` stay raw (documented component-internal dims).

Migrated whole app: 2026-06-22 commit fb249b9 (initial), commit a59ff78 (canonical rhythm
pass — title→next + search→first unified globally). `flutter analyze lib` clean, 308 tests
green. No golden/widget tests assert on spacing, so layout changes are test-safe. Doc lives
in CLAUDE.md "Spacing".
