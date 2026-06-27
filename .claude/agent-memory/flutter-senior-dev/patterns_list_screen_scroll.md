---
name: patterns-list-screen-scroll
description: List screens — search bar and segment row scroll WITH the list (Vaults pattern), only the title is pinned. Prevents overscroll background-gap bug.
metadata:
  type: feedback
---

On every list screen, the search bar AND any segment/toggle row scroll TOGETHER with
the list — they are leading slivers of one `CustomScrollView`. Only the title is pinned
(via `AppScreen.titled`). Never put a search/segment row in a `Column` above
`Expanded(child: <scroll>)`.

**Why:** a pinned control over a separate `Expanded(scroll)` exposes a strip of
background between the control and the list during an upward overscroll/bounce. Owner
reported this as the "gap" bug (2026-06). Vaults never had it because its search is part
of the scroll.

**How to apply:**
- Canonical reference: `lib/features/vault/presentation/pages/vault_list_page.dart`
  (`CustomScrollView(slivers: [SliverToBoxAdapter(AppSearchField), SliverList(cards)])`).
- Per-state content renders as slivers below the control: `SliverList.list` for
  skeleton/error cards, `SliverFillRemaining(hasScrollBody:false)` for centred
  empty/search-empty states, `SliverList.separated` for cards.
- Pagination via `NotificationListener<ScrollEndNotification>` wraps the whole
  `CustomScrollView` (see notification_center_page `_Feed`).
- A tab that isn't itself an `AppScreen` (e.g. `vault_entries_tab.dart`) follows the same
  rule inside its host's scroll area.
- Skeleton-pattern rule was reconciled: search may scroll off during loading (Vaults
  behaviour). Documented in flutter-mobile/CLAUDE.md ("Control scrolls WITH the content"
  + "Loading States — Skeleton Pattern").

Applied 2026-06 to: agents_page, vault_entries_tab, notification_center_page. Vaults was
already correct. See [[patterns_spacing_system]].
