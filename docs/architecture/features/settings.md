# settings

Organization and account settings. The settings drawer mirrors the web panel's
information architecture and exposes two groups:

- **Organization:** General, Team, Permissions, API Keys, Audit Logs, Billing.
- **Account:** Security, Data Import.

The canonical paths live in `AppRoutes` and use the `/settings/*` namespace.
Legacy `/settings`, `/api-keys`, and `/audit` links redirect into that namespace.

## Organization

| Surface | Visibility and mutation boundary | Implementation |
| --- | --- | --- |
| General | The organization-name card is visible to every authenticated member; rename requires `OrganizationManagement` (`2`) and Save lives in a pinned full-width footer | `SettingsPage`, `SettingsCubit`, `OrgSettingsSection` |
| Team | Member list is visible to every member; member cards place the localized role count on the left and joined date on the right of a distinct footer; invitations require `AddUser` (`1`); member-role changes require `OrganizationManagement` (`2`) | `TeamPage`, member/invitation detail pages, `TeamCubit` |
| Permissions | Route and drawer item require `OrganizationManagement` (`2`) | `PermissionsPage`, `PermissionRolePage`, `PermissionsCubit` |
| API Keys | Read requires `ReadApiKey` (`4096`); mutations require `WriteApiKey` (`8192`) | presentation remains in the `api_keys` feature |
| Audit Logs | Route and drawer item require `AuditView` (`128`) | presentation remains in the `audit` feature |
| Billing | Visible to every member | Honest placeholder; the backend Billing module does not exist yet |

The drawer hides unauthorized destinations and the router repeats the same
checks. These client checks are affordances only; the backend remains the
authorization boundary.

Invite-member and create-role sheets are pushed on the root navigator and hide
the Shell bottom navigation for their full lifetime. This keeps the modal
barrier and canonical action footer above Shell-owned navigation and FABs.
Invite Member loads the authoritative `seatUsage` and `seatLimit` returned by
`GET /api/org`; it never derives capacity from the rendered member list. The
backend remains authoritative at submit time. An
`organization-seat-limit-reached` conflict keeps the email draft and renders a
localized inline error inside the sheet. When the authoritative capacity is
already full, the e-mail and role form is not rendered; the sheet shows focused
seat guidance, a compact usage ratio with a progress bar, and a single primary
Manage seats action. With free capacity, Manage seats is omitted from the invite
form so it does not compete with Send invitation. A late backend seat-limit
conflict keeps Manage seats secondary inside the preserved form. Manage seats
opens the existing honest Billing placeholder until paid seat-quantity
management ships.

Team loads the public member directory for all callers. Invitation collections
and invitation-safe roles are fetched only for callers with `AddUser`; the
caller-aware full role catalogue is fetched only with
`OrganizationManagement`. Supported mutations are invite, cancel, resend,
change an invitation's initial role, and replace a member's complete role set.
There is intentionally no mobile invitation-acceptance deep link: mobile does
not yet own an approved contract for replacing the active organization session.

Role editing is caller-aware. System roles and custom roles with
`canAssign == false` are read-only. Member-role controls also disable the owner,
higher-permission peers, and roles the caller cannot delegate. Already assigned
non-delegable roles stay visible and remain in the submitted complete role set.
The backend revalidates every operation. A
`organization-role-grant-manage-cutover-unavailable` conflict is mapped to a
dedicated localized error so the draft remains intact and the fail-closed
cutover state is explained; unrelated HTTP 409 responses stay generic.

## Account

`SecurityPage` groups the existing password-change and TOTP surfaces. OAuth-only
accounts receive an explanatory read-only state. `DataImportPage` hands off to
the existing `ImportVaultPickerPage`; file parsing, validation, encryption, and
upload stay in the established import flow and no plaintext is persisted by
Settings.

## Layers

- **Cubits:** `SettingsCubit`, `TeamCubit`, `PermissionsCubit`.
- **Domain:** organization/member/role/invitation entities and the shared
  `SettingsRepository` boundary.
- **Data:** `SettingsRemoteDataSource` covers `/api/org`, `/api/api-keys`, and
  `/api/organization/*`; `SettingsRepositoryImpl` maps Dio failures to typed
  `SettingsErrorKind` values.
- **Presentation:** General, Team, Permissions, Billing, Security, and Data
  Import pages plus shared Settings errors, permission fields, and the
  `RoleNameRow`/`SystemRoleBadge` used by role lists, details, and member
  assignment so the marker stays right-aligned beside the role name.
- **Lifetime:** organization member, invitation, and role collections live only
  in Cubit state. They are never persisted and are not reused as the Audit actor
  directory.

**⚠ Architecture smell — owns another feature's domain.** The `ApiKey` domain entity and the API-key data layer live **here** (`settings/domain/`, `settings/data/`), but the `api_keys` feature provides the UI. So `api_keys` presentation imports `settings/domain/entities/api_key.dart` and `settings/presentation/widgets/settings_error_text.dart`. If you touch API-key data/domain, you edit it under `settings`, not `api_keys`. The AppBar title here duplicates the `AppBarTitle` pattern — see the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md).

General intentionally contains only the organization-name card. Member details
belong to Team, and the static source-tree licence inventory remains available
in `THIRD_PARTY_NOTICES.md` without a dedicated General-screen row.

**Cross-feature deps:** provides domain/data to `api_keys`; links to the existing
authentication security and Vault import flows; routed from `shell`.
