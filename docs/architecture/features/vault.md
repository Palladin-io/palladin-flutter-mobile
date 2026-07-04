# vault

Vault and entry management — the largest feature. List, detail, create, edit; per-entry-type crypto.

- **Cubits:** `VaultListCubit`, `VaultDetailCubit`, `EntryListCubit`, `CreateVaultCubit`, `CreateEntryCubit`, `EditEntryCubit`, `ImportWizardCubit`, `ExportCubit`.
- **Pages:** `VaultListPage`, `VaultDetailPage` (5 tabs: Entries, Agents, Logs, Members, Settings; two FAB modes; AppBar kebab → Import / Export), `EntryDetailPage`, `AddEntryPage`, `ImportWizardPage`, `ImportVaultPickerPage`.
- **Key widgets:** `VaultEntriesTab`, `CreateVaultSheet`, entry-type forms, icon picker (via `IconColorBrowserSheet`), `ExportSheet`, `ImportPreviewList`, `ImportColumnMapper`.
- **Layering:** full data / domain / presentation split, with per-type crypto services in `data/services/` (zero-knowledge, `try/finally` zero-out).

### Import / Export (CVT-37 / CVT-235)

- **Import engine** — `data/import/` is pure, testable Dart: `import_engine.dart` (structure-based format detection: ZIP → JSON → XML → CSV, never by extension), `import_csv.dart` (declarative `CsvProfile`s — add a format by appending a profile), `import_json.dart` (Bitwarden / Keeper / Proton / 1Password / Enpass / Palladin), `import_xml.dart` (KeePass), `import_normalizer.dart` (TOTP→`otpauth://`, URL→host, name-from-host, trim), `import_models.dart`. Unrecognised CSVs fall back to a manual column mapper.
- **Export** — `data/export/`: `export_serializers.dart` (`toPalladinCsv` RFC 4180 / `toPalladinJson` v1, both pure), `export_sharer.dart` (`ExportSharer` interface; the concrete impl shares via `XFile.fromData` — no self-managed plaintext temp file, matching the recovery-key precedent).
- **Repository** — `EntryRepositoryImpl.importEntriesEncrypted` unwraps the VK **once**, encrypts every draft, POSTs bulk creates in chunks of 500 + PUTs overwrites, streams progress, zeroes the VK in `finally`. `revealAllEntries` unwraps once for export. `logExportAudit` is best-effort.
- **Backend contract (implemented in parallel — CVT-35/233):** `POST /api/vaults/{id}/entries/import` `{format, entries:[…, grantEntries:[]]}` → `{importedCount, entryIds}`; `POST /api/vaults/{id}/export-audit` `{format, entryCount}`. Mobile sends an empty `grantEntries` list (the create flow does not carry FULL-grant wrap material — the backend re-wraps).
- **Security:** all parsing on-device; secrets (`password`, `totp`) never logged; the column mapper never samples cell values (would leak a password); the export sheet gates behind a `WarningZone` plaintext warning.

**Cross-feature deps:** `approval` (grant access sheets), `audit` (`VaultAuditLogTab` embedded in detail), `grants` (`ContextGrantsTab` in detail), `agents` (agent list in the Agents tab).

**⚠ Architecture smells:**
- `VaultListPage` builds a raw `Container(gradient) + Scaffold(transparent)` (~line 185) instead of `AppScreen.titled(...)` — the one inconsistent top-level tab.
- `VaultDetailPage` / `EntryDetailPage` hand-roll `Container + DefaultTabController + Scaffold + AppBar` instead of `AppScreen.appBar(...)` (justified by the `PreferredSize` tab-bar height, but still skips the abstraction).
- `_SkeletonCard` (vault_list) and `_SkeletonRow` (vault_entries_tab) reimplement `SkeletonBox` — replace.
- AppBar titles duplicate the `AppBarTitle` pattern (see the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md)).
