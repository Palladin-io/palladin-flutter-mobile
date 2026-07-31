# settings

Org/user settings (including theme mode + audit-log entry point).

- **Cubit:** `SettingsCubit`.
- **Pages:** `SettingsPage` (reached from the shell settings drawer). **Widgets:** `OrgSettingsSection`, `OpenSourceLicensesSection`, `SettingsErrorText`.
- **Layering:** full data / domain / presentation split.

**⚠ Architecture smell — owns another feature's domain.** The `ApiKey` domain entity and the API-key data layer live **here** (`settings/domain/`, `settings/data/`), but the `api_keys` feature provides the UI. So `api_keys` presentation imports `settings/domain/entities/api_key.dart` and `settings/presentation/widgets/settings_error_text.dart`. If you touch API-key data/domain, you edit it under `settings`, not `api_keys`. The AppBar title here duplicates the `AppBarTitle` pattern — see the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md).

`OpenSourceLicensesSection` opens Flutter's runtime `LicenseRegistry`; the static
source-tree inventory is generated as `THIRD_PARTY_NOTICES.md`.

**Cross-feature deps:** provides domain/data to `api_keys`; routed from `shell`.
