# audit

Audit log viewer — a global page plus tabs embedded in vault/entry detail.

## Entry sharing activity (CVT-644, feature branch)

The shared renderer, legend and Vault/Entry filters include eight `entry-share.*`
events: created/protection-changed use info, delivered/confirmed success,
expired/ended neutral, and revoked/source-access-removed danger. All use existing
`AppColors` tokens and localized EN/PL labels and sentences. The external-recipient
actor (wire ordinal 4 or `externalRecipient`) always renders as external, never
as a locally resolved member or Agent. Delivery and confirmation remain distinct;
confirmation explicitly does not prove human reading. Sharing sentences wrap
without ellipsis; expanded `shareId` uses a localized label and prefix/suffix.
Local formatter/widget tests cover both locales, including 320px/150% rendering;
actual backend/device acceptance remains pending.

- **Cubits:** `AuditLogCubit`, `EntryLogsCubit`.
- **Pages:** `GlobalAuditLogPage` (reached under `/settings/audit`; the drawer
  item and route require `AuditView`).
- **Widgets:** `AuditLogRow`, `AuditLogContent` (reusable — consumed by both `GlobalAuditLogPage` and vault's `VaultAuditLogTab`), `AuditLegendSheet`, `AuditLogFilterSheet`, `EntryLogsTab`, `VaultAuditLogTab`.
- **Presentation resolver:** `AuditPresentationResolver` is shared by the full
  audit surfaces and Home `Recent Activity`; it resolves agent, Vault, Entry,
  and member names only from unlocked local organization state.
- **Layering:** full data / domain / presentation split. Note `audit_log_format.dart` and `audit_filters.dart` sit directly under `presentation/`, not `presentation/widgets/`.
- **Colors:** event colors follow the canonical Audit Log taxonomy — see the "Audit Log colors" rule in `CLAUDE.md`. Never hardcode hex; map roles to `AppColors`.
- **Entry Logs:** fetches lazily only when the Entry Detail Logs tab
  becomes active. Every cursor page is server-filtered by opaque `vaultId +
  entryId` (organization scope comes from the authenticated Vault membership),
  scope-validated on receipt, and capped at 500 structural rows. Entry, Vault,
  and actor presentation resolves from unlocked local MemberIndex/Vault/Agent
  state with `prefix…suffix` fallbacks. Legacy backend names, reasons, and
  metadata are discarded before rows reach presentation; local search never
  becomes an API query and never indexes Entry secret content. Org and Vault
  rows also expose the Entry's current MemberIndex login (memory only) in the
  expanded detail as "Current login": the local index has no timestamp, so it
  is never presented as the login used when the event happened.
- **Global Audit Log:** resolves only identifiers present in each
  fetched page through the current organization’s Agent/Vault directories and
  each accessible Vault’s local MemberIndex/Member directory. Resolution maps
  are retained only alongside the bounded 2,000-row feed; repeated cursors and
  duplicate rows terminate safely. Server-supplied names, reasons, and metadata
  are ignored, cross-organization Vault ids remain unresolved, and search plus
  structural filters are strictly local after fetch.
- **Home Recent Activity:** uses the same org-scoped presentation resolver as
  Global Audit Log and refreshes the already-fetched six-row feed whenever the
  relevant MemberIndex publishes a completed runtime-index update. That update
  uses the resolver's Entry-only path: it does not refetch Agents or Vault
  members when only local Entry labels may have changed.

**Cross-feature deps:** embedded by `vault` (Logs tab). Filter/legend sheets inline the drag handle → extract `SheetDragHandle`.

Unknown actor values render as unknown rather than being attributed to System.
Ordinary audit metadata remains displayable without response enum validation;
local identity resolution and removal of server-supplied sensitive presentation
remain unchanged.

`AuditLogList` owns the shared card surface around the feed. Its sliver constructor
keeps full Global/Vault/Entry feeds lazy; Home uses the regular constructor for
its bounded recent feed. Rows have no individual card or icon tile; date, event
and chips share one content column with separators only between rows.

The metadata row anchors relative time at the trailing edge, measures shared
StatusBadge typography with the current text scale, and displays the ordered
chips that fit. +N expands only the remaining chips; exact date stays in a tooltip.

Resource actions put the author last; grant approval names Entry → Agent before
the approver. Rows show one line, and tapping opens SheetSurface with the full
localized sentence, exact date and metadata. Chip expansion remains independent.

Agent Details uses AuditLogContent/AuditLogList with an immutable server-side agentId scope on AuditLogCubit, retained for pagination. It requires AuditView and replaces the separate lifecycle-date timeline. The offline preview uses the same feed with its local audit adapter.

AuditLogCubit fences fetch, name resolution and pagination completions by its
load generation and closed state, so leaving Agent Logs cannot publish stale
results or emit into a disposed tab.
