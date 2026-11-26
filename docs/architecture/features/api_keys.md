# api_keys

API key list, detail, generate, revoke, delete.

- **Cubit:** `ApiKeysCubit`.
- **Pages:** `ApiKeysPage`, `ApiKeyDetailPage` (reached under
  `/settings/api-keys`, not the bottom nav). The drawer and route require
  `ReadApiKey`; generate/revoke/activate/delete controls additionally require
  `WriteApiKey`.
- **Widgets:** `ApiKeyCard`, `ApiKeyStatusBadge`, `ApiKeyDetailsTab`, `GenerateApiKeySheet`, `RevokeApiKeySheet`, `DeleteApiKeySheet`.

**⚠ Architecture smell — presentation-only feature.** This feature has **no `data/` or `domain/` directory**. The `ApiKey` entity and repository live in `settings`; `api_keys` presentation imports `settings/domain/entities/api_key.dart` and `settings/presentation/widgets/settings_error_text.dart`. Feature isolation is broken — treat `settings` + `api_keys` as one bounded context until refactored.

**Other smells:**
- `ApiKeyDetailPage` (~line 48) uses `AppCanvasBackground + DefaultTabController + Scaffold + AppBar` instead of `AppScreen.appBar(...)`.
- API-key Details composes shared `EntryFieldRow.labeled` with full-width separators.
- `ApiKeyStatusBadge` reuses `StatusBadge` for the same neutral outline as agents.
- `_KeysEmpty` duplicates the empty-card pattern → extract `ListEmptyCard`.
- Revoke/Delete use `ConfirmationSheet`; generation reuses `WarningZone` and `AccentButton`.

See the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md).

## Current presentation contract

See `docs/design/mobile-ui-alignment.md` (Current approved UI contract). Resource
lists reuse AppRecordList/AppRecordRow; metadata uses read-only details and root
Edit routes with one pinned AppActionFooter. Preserve existing permission guards.
