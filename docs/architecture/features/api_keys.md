# api_keys

API key list, detail, generate, revoke, delete.

- **Cubit:** `ApiKeysCubit`.
- **Pages:** `ApiKeysPage`, `ApiKeyDetailPage` (reached from the settings drawer, not the bottom nav).
- **Widgets:** `ApiKeyCard`, `ApiKeyStatusBadge`, `ApiKeyDetailsTab`, `GenerateApiKeySheet`, `RevokeApiKeySheet`, `DeleteApiKeySheet`.

**⚠ Architecture smell — presentation-only feature.** This feature has **no `data/` or `domain/` directory**. The `ApiKey` entity and repository live in `settings`; `api_keys` presentation imports `settings/domain/entities/api_key.dart` and `settings/presentation/widgets/settings_error_text.dart`. Feature isolation is broken — treat `settings` + `api_keys` as one bounded context until refactored.

**Other smells:**
- `ApiKeyDetailPage` (~line 48) hand-rolls `Container + DefaultTabController + Scaffold + AppBar` instead of `AppScreen.appBar(...)`.
- `api_key_details_tab.dart:303` defines `_DetailRow` (duplicated in `agents`) → extract `LabelValueRow`.
- `ApiKeyStatusBadge` duplicates `AgentStatusBadge` → extract `StatusPill`.
- `_KeysEmpty` duplicates the empty-card pattern → extract `ListEmptyCard`.
- Three sheets define a private `_SheetHandle` → extract `SheetDragHandle`.

See [../widget-catalog.md](../widget-catalog.md).
