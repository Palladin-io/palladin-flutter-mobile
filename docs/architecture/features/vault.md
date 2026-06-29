# vault

Vault and entry management — the largest feature. List, detail, create, edit; per-entry-type crypto.

- **Cubits:** `VaultListCubit`, `VaultDetailCubit`, `EntryListCubit`, `CreateVaultCubit`, `CreateEntryCubit`, `EditEntryCubit`.
- **Pages:** `VaultListPage`, `VaultDetailPage` (5 tabs: Entries, Agents, Logs, Members, Settings; two FAB modes), `EntryDetailPage`, `AddEntryPage`.
- **Key widgets:** `VaultEntriesTab`, `CreateVaultSheet`, entry-type forms, icon picker (via `IconColorBrowserSheet`).
- **Layering:** full data / domain / presentation split, with per-type crypto services in `data/services/` (zero-knowledge, `try/finally` zero-out).

**Cross-feature deps:** `approval` (grant access sheets), `audit` (`VaultAuditLogTab` embedded in detail), `grants` (`ContextGrantsTab` in detail), `agents` (agent list in the Agents tab).

**⚠ Architecture smells:**
- `VaultListPage` builds a raw `Container(gradient) + Scaffold(transparent)` (~line 185) instead of `AppScreen.titled(...)` — the one inconsistent top-level tab.
- `VaultDetailPage` / `EntryDetailPage` hand-roll `Container + DefaultTabController + Scaffold + AppBar` instead of `AppScreen.appBar(...)` (justified by the `PreferredSize` tab-bar height, but still skips the abstraction).
- `_SkeletonCard` (vault_list) and `_SkeletonRow` (vault_entries_tab) reimplement `SkeletonBox` — replace.
- AppBar titles duplicate the `AppBarTitle` pattern (see the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md)).
