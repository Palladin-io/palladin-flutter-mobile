# vault

Vault and entry management — the largest feature. List, detail, create, edit; per-entry-type crypto.

- **Cubits:** `VaultListCubit`, `VaultDetailCubit`, `EntryListCubit`, `CreateVaultCubit`, `CreateEntryCubit`, `EditEntryCubit`, `ImportWizardCubit`, `ExportCubit`.
- **Pages:** `VaultListPage`, `VaultDetailPage` (5 tabs: Entries, Agents, Logs, Members, Settings; two FAB modes; AppBar kebab → Import / Export), `EntryDetailPage`, `AddEntryPage`, `ImportWizardPage`, `ImportVaultPickerPage`.
- **Key widgets:** `VaultEntriesTab`, `CreateVaultSheet`, entry-type forms, icon picker (via `IconColorBrowserSheet`), `ExportSheet`, `ImportPreviewList`, `ImportColumnMapper`.
- **Layering:** full data / domain / presentation split, with per-type crypto services in `data/services/` (zero-knowledge, `try/finally` zero-out).

### Vault protocol 2 crypto foundation

Individual Entry sharing has a separate, in-progress crypto boundary and a fifth
Entry Detail tab for list/revoke, documented in [entry-sharing.md](entry-sharing.md).
It does not reuse source Entry/Vault keys. Selected-field projection, create POSTs,
the session-fenced creation Cubit and a separate sender form are wired from the
list CTA. Guest reception has a tested page and isolated transport/Cubit connected
through an app-owned ingress host and the public constant `/share` route.
Android and iOS intake use the Dart one-shot RAM handoff; local ownership is checked
before claiming it, including guest/new/locked account contexts. Original ingress
deadlines survive mounting and can only shorten. Save/account continuation,
native domain/provisioning and real HTTP/device acceptance remain open; see the sharing
document for the native plugin-retention boundary and verification limits.
The received-copy projector now prepares private canonical plaintext for all
four Entry types, with explicit missing-field completion and strict TOTP handling;
its copy service and Cubit now compose canonical creation with scoped destination
crypto, an account-bound isolated transport and byte-identical encrypted retries.
The receiver now wires a Save CTA for an already authenticated, verified and
unlocked recipient. Its account-bound destination picker, completion form and
exact encrypted retry remain inside the original reception lifetime. Explicit
guest account/unlock continuation is now wired through an app-owned RAM transfer
and the existing auth routes. First-Vault creation and combined account/save
acceptance remain pending; local service/widget tests are not evidence of
deployed end-to-end saving.

- `data/services/vault_protocol/` owns the frozen protocol primitives: strict canonical bytes/base64url/UUID validation, binary TLV AAD profiles, HKDF-SHA-256 projection keys, XChaCha20-Poly1305 envelopes, bounded X25519 sealed packages and RFC 8785/Ed25519 signatures. Widgets, Cubits and remote datasources must not reproduce these operations.
- Native fixture tests consume the minimal public snapshot in `test/fixtures/vault_protocol_2/`, pinned to source commit `b370b56e4f65ecf5350bc4f9203fee6429572955` and verified against the manifest's SHA-256 list. `PROVENANCE.md` records the source digests and the single deterministic sanitization of an internal label in synthetic metadata. Tests always use the vendored snapshot, so a parent or private repository checkout is never required.
- All structural aliases, unsupported versions/suites, wrong scopes, stale Member generations, oversize payloads, malformed canonical encodings and authentication failures fail closed before plaintext reaches presentation state. Service-owned key/plaintext copies are disposed or zeroed in `finally` paths.

### Encrypted Member sync and local search

- `MemberSyncService` consumes the frozen policy-2 routes under `current-entries/sync` and requires protocol/policy response headers `2`/`2`. Each bounded item carries the complete current `EntryKey`, `MemberIndex` and `MemberSecret`. Snapshot pages stay in a staging SQLite generation until the closing delta is exhausted; only then are the ciphertext generation, applied sequence, finite access context and authoritative `memberVaultKey` swapped atomically. `resetRequired` removes the active generation before a replacement is staged.
- Access-context UTC timestamps accept the backend NodaTime Instant precision (up to nine fractional digits). Dart truncates sub-microsecond precision; expiry is never rounded up. Ciphertext and cryptographic bindings are unchanged.
- **Retained runtime checks:** authenticated envelope scope, Entry/Vault/organization, key version, member generation, wrapping Vault-key version, projection revision-to-head bindings, current `MemberIndex`/`MemberSecret` revision alignment, lease authority, cursor monotonicity and device resource limits remain fail-closed.
- **Removed duplicate/non-invariant check:** the client does not assert `EntryKey.resourceRevision == Entry.currentRevision`. The EntryKey wrapper has its own revision and normally stays unchanged when an edit reuses the existing Entry DEK; the backend-owned Entry head revision is not an independent authority for that wrapper revision.
- The SQLite cache contains only structural cursors, the finite access context, the encrypted Member Vault-key wrapper and serialized opaque `EntryKey` / `MemberIndex` / `MemberSecret` envelopes. It never stores a decrypted label, search term, secret, Entry DEK, VK, private key or master key. Reads use entry-id keyset pages of 100 instead of materializing the cache at once, and the complete profile is capped at 512 MiB.
- Entry-key unwrap and projection decrypt stay in dedicated crypto services. Decrypt concurrency defaults to two, response pages are capped at the backend's 200-item limit, and the runtime index fails closed above 20,000 entries. Organization, principal, membership generation, Vault, Member, revision, key-version and expiry bindings are checked against current session or structural authority; one corrupt item rejects the page and never activates a partial generation.
- Deterministic  gates live in `test/performance/vault_v2_mobile_structural_budget_test.dart`; their shared limits are `VaultPerformanceBudget`. They cover 1k/10k/20k snapshots, exact 1% deltas, page/count/envelope byte ceilings, bounded decrypt work, local search, one-secret grant approval, and lazy 100-version history. Physical low-end p95/memory evidence remains a separate release-blocking artifact documented in `docs/performance/vault-v2-mobile-release-gates.md`; simulator timing is never promoted to that evidence.
- Search operates only on the unlocked in-memory index. Reveal, copy and TOTP open the selected complete local item through `LocalCurrentEntryService`; they do not call the canonical single-Entry endpoint. Mutations remain online and refresh the Member stream after their authoritative outcome.
- `PalladinApp` clears all decrypted indexes on lock and purges the whole current-entry profile on logout. An unexpired policy context can reopen the complete encrypted generation offline; expiry or more than five minutes of wall-clock rollback purges it. `disabled` policy is usable only in the connected unlocked session. Foreground, unlock, SignalR reconnect and value-free Vault invalidations request authoritative repair. `durableUpdates` fires only after the snapshot plus closing delta or a delta is durably committed, and is the handoff consumed by the native AutoFill follow-up.
- `MemberIndexPreparationService` is the session-scoped single-flight boundary shared by Dashboard search and AutoFill. Concurrent unlock consumers share one Vault-list load and one Member sync chain per Vault. The independently loaded `memberVaultKey` wrapper from the Vault list is compared with every sync page, avoiding a `GET /api/vaults/{id}` fan-out. Copied private keys, opened VKs and in-flight preparation generations are invalidated on lock; key copies are wiped in `finally` paths.

### Dashboard global search

- Vault and Entry hits are derived only from the unlocked `VaultListCubit`
  metadata and `MemberIndexReader`; recent Entry suggestions use the same
  synchronized local index. No Vault/Entry label, search field, icon or query
  projection is sent to backend Search or persisted by the search feature.
- After the 250 ms debounce, bounded local search and the authorization-scoped
  Agent/Member request start concurrently. Local results render immediately;
  remote failure retains them. A `CancelToken` plus generation guard rejects
  stale completions after a newer query or security transition.
- The administrative query is ephemeral and sent only in the body of
  `POST /api/search`. It never appears in URL parameters, logs, analytics,
  crash breadcrumbs or a client cache. Unknown remote types remain visible as display-only hits. They cannot become
  locally authenticated Vault/Entry identities or reveal secrets.
- Results are sealed Agent/Member/Vault/Entry identities. Ranking is
  deterministic within local source groups, never compares local and remote
  score scales, and deduplicates by scoped identity. Candidate traversal is
  capped at 20,000; each source/result request is capped at 10.
- Background, lock, logout, reset and page disposal cancel transport and drop
  query intent/results. Corrupt, Archived and Deleted MemberIndex rows fail
  closed.

### Resumable staged key rotation

- `VaultRotationService` starts after unlock, lists only server-owned pending work, claims a fenced lease, verifies that the claimed plan matches the listed immutable generations/epochs, and uploads pages of at most 100 prepared envelopes. It retries a dirty atomic commit at most three times.
- Lease renewal receives a new fencing token and reopens the claimant's pending VK, VDK, and private-key envelopes. Every pending secret must match the process-local seed in constant time; a reset, changed plan, missing seed, or stale client fails closed instead of mixing generations.
- `VaultRotationCryptoService` is the sole rotation crypto boundary: it opens/seals scoped Member VK packages, rotates VK/VDK projections, rewraps Entry DEKs, generates Agent manifests, signs them with the pending Ed25519 seed, and creates one replacement `AgentWrappedVaultKey` for every retained active FULL grant. All generated and opened keys are process memory only and are wiped on success, failure, cancellation, lock, or app background pause; progress persistence remains ciphertext-only on the backend.
- `PalladinApp` resumes pending work when an authenticated Vault unlocks and cancels the active Dio token whenever that session locks or disappears. The current generation remains authoritative until the backend's atomic commit succeeds.

### Canonical Entry detail and versioned edit

- The canonical-to-form adapter maps `customFields` to the form's `fields` shape once, including stable ids, kind/type and index-visibility flags. Detail, local-cache reveal and grant projection share that adapter. Edits remove policy entries for fields absent from the new schema while preserving access modes for surviving fields; this does not change the retained owner selection on a grant.
- Entry Detail renders the already-decrypted in-memory MemberIndex first and automatically authenticates and decrypts MemberSecret on entry. Sensitive values remain masked and are revealed per field. A canonical authentication failure never falls back to the legacy plaintext/blob repository path.
- A save emits exactly one optimistic backend transition: immutable MemberSecret revision `N+1`, the next MemberIndex head and the next AgentDiscovery high-watermark revision are encrypted locally and switched atomically. A stale Member generation also rewraps the Entry DEK as the next key version before binding all projections to it.
- HTTP `409` is a dedicated edit-conflict state rather than a generic validation error. Lock, background and widget disposal drop decrypted Cubit state, controller values, reveal flags and TOTP state; keys and temporary plaintext byte buffers are wiped in `finally` paths.

### Entry Agent policy and exact-revision grants

- Entry Details decrypts the authenticated canonical policy only while unlocked and exposes Discovery as small, tooltip-labelled agent icons beside eligible inputs. The policy is saved in the same optimistic canonical transition as the Entry edit. The Entry Agents tab contains only actual scoped grants plus the host add-grant CTA; it never exposes protocol field ids or access-mode dropdowns. TOTP source fields accept only `never`/`onGrantDerived`; Script source and refs accept only `never`/`onGrantRuntime`. VK, VDK, EntryDEK and source secrets never enter widget state or copy actions.
- A policy save creates one immutable canonical revision. Discovery advances only when its effective projection changes; private-only policy changes do not leak through the Discovery cursor.
- Before GRANULAR grant encryption, the local projector proves every approved field is still within the Entry policy. Every active GRANULAR grant on that Entry is fetched with bounded cursor pagination, refreshed to the exact new Entry revision with a fresh GrantDEK, and submitted in the same optimistic Entry transaction. Every direct `ScriptExecution` package whose structural scope contains the edited Entry is also rebuilt locally and submitted in that transaction. FULL grants require no per-Entry material because they carry one Vault-key wrapper. Missing, extra, stale or widening scope fails closed and the backend commits all heads/envelopes/packages or none.
- Lock, background, conflict and successful save clear the decrypted snapshot. Member keys, GrantDEKs, plaintext payload bytes, recipient-key copies and sealed-package buffers are wiped in `finally` paths.

### Import / Export

- **Import engine** — `data/import/` is pure, testable Dart: `import_engine.dart` (structure-based format detection: ZIP → JSON → XML → CSV, never by extension), `import_csv.dart` (declarative `CsvProfile`s — add a format by appending a profile), `import_json.dart` (Bitwarden / Keeper / Proton / 1Password / Enpass / Palladin), `import_xml.dart` (KeePass), `import_normalizer.dart` (TOTP→`otpauth://`, URL→host, name-from-host, trim), `import_models.dart`. Unrecognised CSVs fall back to a manual column mapper.
- **Export** — `data/export/`: `CanonicalExportService` reads the unlocked runtime MemberIndex, opens one canonical Member VK session, and decrypts/writes one MemberSecret at a time. `ProtectedExportWriter` emits CSV or Palladin JSON format v2 incrementally into native protected staging; native append chunks are capped at 256 KiB and the file at 50 MiB. Default scope is Active/current only; Archive, Recently Deleted, and immutable history are separate explicit toggles. History uses bounded cursor pages and sequential N+1 MemberSecret reads.
- **Repository** — canonical imports request server-issued entry IDs, create a fresh EntryDEK and complete EntryKey / MemberIndex / MemberSecret / AgentDiscovery projections on-device, then POST atomic client batches of 50 (within the backend's 500-item contract limit). A lost response retries the exact same IDs and ciphertext; committed batches are not rebuilt or resent. Legacy overwrites fail closed because the canonical import endpoint is create-only. Export does not call an export endpoint or send export metadata/business payload to the backend.
- **Backend contract:** `POST /api/vaults/{id}/entries/creation-challenges` issues IDs; `POST /api/vaults/{id}/entries/import` accepts complete canonical transitions (`entryId`, `entryKey`, `memberIndex`, `memberSecret`, optional `agentDiscovery`, explicit `deliveryPolicy`) and commits each batch transactionally. Import does not fan out material to existing grants. Export has no backend endpoint.
- **Security:** all parsing, projection encryption, and export assembly happen on-device; secrets (`password`, `totp`) never reach request metadata, logs or mobile analytics. Export requires an unlocked session plus an explicit local confirmation. The Member VK and per-record byte buffers are wiped in `finally`; an epoch guard cancels on lock/close. Native staging is app-private, backup-excluded, uses complete file protection on iOS and owner-only permissions on Android, and is cleaned on success/cancel/failure, lock, and startup. Deletion is accurately disclosed as best effort on flash storage, and the selected share recipient owns any copy it creates.
- **Public website icons:** create/edit and import reserve catalog assets in pages of at most 500 (the coordinated backend contract) before encrypting presentation metadata. Import has no fixed elapsed-time timeout: while its explicit progress screen remains active, it waits for terminal `Ready`/`Failed` status and cancels immediately on lock, close, or session invalidation. Explicit transport or parsing failure still fails fast and leaves icons optional. Progress counts both terminal statuses as completed; only `Ready` contributes an asset. `MemberSecret` and `MemberIndex` contain the catalog `assetId`, immutable `revision`, and direct delivery `url` only for a published immutable object; pending/failed assets are omitted. Edit treats every persisted icon as authoritative and never replaces a glyph, upload, or manually selected catalog asset during an unrelated save. This is a pre-production clean cutover: test ciphertext containing the retired `{kind: website, hostname}` or id-only public-asset shape is intentionally reset rather than carried into the canonical schema. Catalog failure remains optional and never blocks saving credentials. Entry lists, detail screens, Dashboard and search render that allowlisted URL directly after decryption. They never resolve hostnames or fetch catalog metadata while reading a Vault, and a failed image GET falls back locally without retry or polling. Agent icons may still use ID lookup because their structural contract is separate from encrypted Vault Entry presentation.

### Entry richness — blob schema v2 + TOTP + Script + Credit Card

The decrypted entry blob is **additive v2**: well-known fields stay top-level, a
`fields[]` array of custom fields is added beside them, and a new `SCRIPT`
entry type (`EntryType.script`, wire `2`) carries `script` / `interpreter`
(`bash|sh|node|python`) / `refs[]` (explicit `env → entryId.fieldId` mappings)
plus execution metadata: required description, up to 32 typed CLI parameter
definitions, and `returnResultToAgent`. New Scripts default the result flag to
`true`; an absent legacy flag is interpreted as `false`.
`EntryType.creditCard` (wire `3`) carries cardholder name, PAN, expiry
month/year and optional billing address. It has no dedicated CVV/CVC or PIN
field. General custom fields remain neutral and are not detected, promoted, or
autofilled as card-verification data. Its Agent fields
are runtime-only, Discovery advertises only `inject`, and grant descriptors use
authenticated delivery policy `2` (`InjectOnly`); `get`/`exec` never receive the
card envelope. Entry type remains inside encrypted projections and is omitted
from create/import request metadata.
Absence of `v` ⇒ legacy v1. Unknown field types (`url`, `date`, … / anything
future) parse to `CustomFieldType.unknown` and are **held aside and re-emitted
unchanged** on save so an older client never drops a newer client's fields.

- **Models** (`domain/entities/`): `custom_field.dart` (`CustomField` +
  `CustomFieldType`), `totp_config.dart` (`TotpConfig` — parses `otpauth://`
  URIs and base32, RFC defaults SHA1/6/30), and `ScriptPayload` / `ScriptRef` /
  `ScriptInterpreter`, `ScriptExecutionMetadata`, and typed parameter
  definitions in `entry_entity.dart`. Reference environment names are unique
  case-insensitively and reject process-control names/prefixes such as
  `NODE_OPTIONS`, `LD_*`, `DYLD_*`, and `PALLADIN_*`. `KeyPayload` /
  `CredentialPayload` gained `fields`.
- **TOTP** (`data/services/totp_service.dart`): stateless RFC 6238 generator
  (HMAC via `crypto`, local base32 decoder); tested against the RFC 6238
  vectors. Never inline TOTP maths in a widget. `TotpDisplay` shows the live
  code + countdown ring; `TotpSetupSheet` + `TotpScannerPage` (mobile_scanner)
  capture a secret via QR / paste / manual base32.
- **Custom fields UI**: `CustomFieldsEditor` (reorderable rows: name + type +
  value/TOTP) on Add/Edit; the read-only detail renders each field with the
  Locked Value Pattern (concealed/totp masked until revealed).
- **Script UI**: `ScriptRefsEditor` (env ← entry.fieldId rows),
  `ScriptParametersEditor`, a result-delivery toggle and a warning explaining
  that stdout can reach the Agent/LLM. Before saving a changed Script, the
  value-free access-impact endpoint returns effective/direct/FULL Agent counts;
  the user must confirm and a failed impact check blocks the save. Script
  entries hide URL and use the `terminal` glyph.
- **Crypto:** Script metadata remains inside the canonical MemberSecret and its
  value-free subset enters AgentDiscovery. Direct execution additionally uses
  one Agent-sealed Script execution package; parameter values remain local to
  the CLI and never enter backend requests.
- **Granular Grant projection** — `AgentVisibilityProjector` converts the
  authenticated MemberSecret policy into the production
  `palladin.grant-payload.v2` plaintext consumed by the native runtime. It maps
  built-ins to canonical IDs, prefixes custom UUIDs with `custom:`, sorts the
  completed field array, and only then derives the structural Grant field list.
  Legacy Script references without `vaultId` are normalized to the Script
  Entry's current Vault before encryption. Existing envelope profiles and their
  bindings are unchanged: canonical envelopes retain their field-set commitment;
  the legacy frozen Grant AAD profile carries a structural field list only.
  Script reference packages explicitly retain their separate V1 payload contract.

### Add/Edit redesign + agent-visible fields (mockup parity)

The Add/Edit form matches the approved mockup: Type is a select-input (first),
the Label carries an inline `EntryIconTile` (opens the icon browser), sections
use `EntrySectionHeader` (small caption + divider), and the primary CTA stays a
44px `PrimaryButton`. Field order: Type → Label(+icon) → Description →
type-specific(+URL / injected data) → 2FA → Additional fields → Notes.

- **Field types** now include `CustomFieldType.multiline` (wire `"multiline"`,
  monospace growing input). Types: `text | multiline | concealed | totp | unknown`.
- **Two-factor** is its own section (`TotpSection`): dashed empty state → "Add
  2FA", configured → a card with the live code (`TotpDisplay`) + a "⋯" bottom
  sheet (copy / replace / remove). QR scanning lives only in `TotpSetupSheet`.
  Data-wise these are ordinary `totp` custom fields; `CustomFieldsEditor`
  excludes them so 2FA has a single home. The page keeps `_totpFields` +
  `_customFields` and folds `_allCustomFields` (2FA first) into the blob.
  During edit, a new custom TOTP identity defaults to `onGrantDerived`, matching
  creation. Replacement keeps the UUID and existing policy; explicit `never`
  (including an override for a new field) and a missing policy on an existing
  identity remain private. Credit-card edits follow the same rule instead of
  overwriting existing custom-field restrictions with defaults. Scoped grant
  refresh keeps the approved field identity when its TOTP configuration changes;
  standard Entry grants carry the encrypted V2 source to the native runtime,
  which derives a fresh code at operation time. Script reference packages keep
  V1 derived codes and never include a raw source.
  Regression coverage: `canonical_entry_v2_interop_test.dart`.
  Native `credential.totp` remains a native field during editing: the form
  carries canonical maps and legacy `otpauth://` URIs without a string cast.
  The canonical writer preserves maps and normalizes valid legacy URIs to a
  configuration map while retaining the field identity and owner policy. Missing
  policy on an existing native field remains `never` after normalization.
- **Additional fields** (`CustomFieldsEditor`) is a grouped card of one-line
  rows (type glyph + inline label/value + "⋯"). The row menu (`showAppMenuSheet`)
  changes type, toggles **Visible to agents** (text/multiline only), reorders,
  and removes. Field ids are stable (never regenerated).
- **agentVisible**: `CustomField.agentVisible` serializes
  `agentVisible:true` only for text/multiline; create/update requests carry a
  plaintext `agentFields:[{label,value}]` mirror (`CustomField.agentFieldsFrom`),
  patch semantics on update (null = unchanged, [] = clear). Backend limits
  20 fields / label 200 / value 2000 (`CustomField.max*`).
- **Script**: `ScriptEditorField` (line-number gutter, fixed height + internal
  scroll, inline interpreter picker in the field label, footer, and a calm
  script-accent exec-only note — not a `WarningZone`). Injected data uses the
  `Injected vault data` section header.
- **New shared widget**: `AppMenuSheet` (`lib/core/widgets/app_menu_sheet.dart`)
  — native bottom-sheet action menu (`showAppMenuSheet`), the mobile
  counterpart of the web "⋯" popover. Used by the field menus, add-field, and
  2FA menus.

**Cross-feature deps:** `approval` (grant access sheets), `audit` (`VaultAuditLogTab` embedded in detail), `grants` (`ContextGrantsTab` in detail), `agents` (agent list in the Agents tab).

The Entry Detail Logs tab delegates to Audit's opaque Entry-scoped feed. It is
lazy-loaded on first selection and never downloads Vault-wide pages for local
Entry filtering.

### Entry version history

`EntryDetailPage` owns a fourth History tab backed by `EntryHistoryCubit`.
Opening the tab is the only action that calls the bounded cursor endpoint;
normal member sync never downloads immutable versions. Each row keeps its
`MemberSecret` and matching historical `EntryKey` encrypted until explicitly
selected. `EntryHistoryService` authenticates and decrypts only that row on
device. Actor references use a `prefix…suffix` fallback when no display name
exists. Restoring content re-reads the current canonical head and uses the
existing optimistic atomic update, creating N+1 without modifying the source
version. The selected plaintext and every borrowed private-key copy are wiped
on success, error, lock/background, and disposal.

### Dedicated Entry Archive

The Entries tab is Active-only and links to a dedicated Archive page. Archive
rows come exclusively from the decrypted, unlocked `MemberIndex` where
`state == Archived`; `Deleted` remains a separate Recently Deleted concern.
Search, type filters and deterministic sorting run only over the bounded
runtime index. No label, search term or other decrypted field is sent to the
backend, persisted, logged or tracked.

Unarchive prepares one canonical `Restored` transition with the next
`MemberSecret`, `MemberIndex` and `AgentDiscovery` revisions. An ambiguous
transport retry reuses the byte-identical prepared envelope and `409` remains
an explicit optimistic conflict. The UI keeps the authoritative Archived row
until the subsequent Member delta reports the Active head; it never invents a
permanent local head. Lock/session loss clears the view, corrupt rows fail
closed, and lazy list rendering remains bounded by the 20,000-entry runtime
index limit.

### Recently Deleted Entry lifecycle

Recently Deleted is a separate surface from Archive. Structural lifecycle
pages provide only opaque Entry ids, `DeletedAt` and authoritative
`RetentionExpiresAt`; all
labels and searchable presentation are joined locally from the unlocked
`MemberIndex` with `state == Deleted`. Backend-supplied presentation fields are
ignored. Missing, corrupt or already-purged projections render only a safe
`prefix…suffix` identifier and cannot be restored.

Restore reuses the canonical `Restored` transition from Archive and reconciles
only after the next Member delta. Permanent purge requires an explicit warning
and calls the body-less destroy endpoint without decrypting content. `204` and
an already-purged `404` are idempotent success; `409` remains visible as an
invalid-state conflict. Search is runtime-only and bounded to 10,000 structural
rows; lock/session loss drops the joined plaintext view.

### Encrypted presentation assets

Vault and Entry icons share `EncryptedPresentationAssetService`. The picker
provides local bytes only; the client validates a bounded JPEG, PNG or WebP by
magic bytes and decoded dimensions before deriving a resource-scoped asset key
from the Vault key or Entry DEK. A fresh XChaCha20-Poly1305 nonce and AAD bind
the organization, Vault, asset id, target kind, optional Entry id, revision,
media type, key version and member generation. The API receives only the
opaque `PLDNV2AS` container and its SHA-256 digest—never a source URL, domain,
file path or plaintext image.

Rendering downloads authenticated opaque bytes, verifies length and digest,
then decrypts locally through the same service. Decoded byte ownership is
widget-scoped; disposal wipes the buffer, while lock/account switch wipes all
owned buffers and clears Flutter's pending/live image cache. Legacy Vault and
Entry presign/public-URL upload paths are intentionally absent.

**⚠ Architecture smells:**
- `VaultListPage` keeps its custom header layout, but now shares `AppBrandBackground` with the other tabs.
- `VaultDetailPage` / `EntryDetailPage` use `AppBrandBackground + DefaultTabController + Scaffold + AppBar` instead of `AppScreen.appBar(...)` (justified by the `PreferredSize` tab-bar height, but still skips the abstraction).
- `_SkeletonCard` (vault_list) and `_SkeletonRow` (vault_entries_tab) reimplement `SkeletonBox` — replace.
- AppBar titles duplicate the `AppBarTitle` pattern (see the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md)).

## Entry grant field selection

Both ordinary and canonical Entry updates refresh all-fields grants from current grantable fields. Selected grants intersect their retained allowlist with current policy; missing metadata preserves the delivered field list. Empty resulting scope blocks the update. Recipient, methods, expiry and remaining uses are unchanged.

### Trusted response metadata

Member-sync wrappers accept additional server metadata and nine-digit .NET
Instant fractions. Required fields and cryptographic/offline authority checks
remain enforced. See [API response boundaries](../api-response-validation.md)
for the audit of retained checks and forward-compatible display values.
