# vault

Vault and entry management — the largest feature. List, detail, create, edit; per-entry-type crypto.

- **Cubits:** `VaultListCubit`, `VaultDetailCubit`, `EntryListCubit`, `CreateVaultCubit`, `CreateEntryCubit`, `EditEntryCubit`, `ImportWizardCubit`, `ExportCubit`.
- **Pages:** `VaultListPage`, `VaultDetailPage` (5 tabs: Entries, Agents, Logs, Members, Settings; two FAB modes; AppBar kebab → Import / Export), `EntryDetailPage`, `AddEntryPage`, `ImportWizardPage`, `ImportVaultPickerPage`.
- **Key widgets:** `VaultEntriesTab`, `CreateVaultSheet`, entry-type forms, icon picker (via `IconColorBrowserSheet`), `ExportSheet`, `ImportPreviewList`, `ImportColumnMapper`.
- **Layering:** full data / domain / presentation split, with per-type crypto services in `data/services/` (zero-knowledge, `try/finally` zero-out).

### Vault protocol 2 crypto foundation (CVT-438)

- `data/services/vault_protocol/` owns the frozen protocol primitives: strict canonical bytes/base64url/UUID validation, binary TLV AAD profiles, HKDF-SHA-256 projection keys, XChaCha20-Poly1305 envelopes, bounded X25519 sealed packages and RFC 8785/Ed25519 signatures. Widgets, Cubits and remote datasources must not reproduce these operations.
- Native fixture tests consume the minimal byte-identical snapshot in `test/fixtures/vault_protocol_2/`, pinned to root commit `b370b56e4f65ecf5350bc4f9203fee6429572955` and verified against the manifest's SHA-256 list. `PALLADIN_VAULT_V2_FIXTURES` may override it locally to compare directly with a root checkout; update steps and provenance live beside the snapshot.
- All structural aliases, unsupported versions/suites, wrong scopes, stale Member generations, oversize payloads, malformed canonical encodings and authentication failures fail closed before plaintext reaches presentation state. Service-owned key/plaintext copies are disposed or zeroed in `finally` paths.

### Encrypted Member sync and local search (CVT-439)

- `MemberSyncService` consumes protocol-2 snapshot/delta pages with the frozen protocol/policy headers. Snapshot pages are streamed through a staging SQLite namespace and promoted atomically only after every page authenticates and decrypts; an interruption preserves the last complete cache. Delta items and their applied-through sequence commit in one SQLite transaction, and `resetRequired` starts a new snapshot.
- The SQLite cache contains only structural cursors plus serialized opaque `VaultEntryKey` and `MemberIndex` envelopes. It never stores a decrypted label, search term, Entry DEK, VK, or other key. Reads use entry-id keyset pages of 100 instead of materializing the cache at once.
- Entry-key unwrap and MemberIndex decrypt stay in `data/services/vault_protocol/`. Decrypt concurrency defaults to two, response pages are capped at the backend's 200-item limit, and the runtime index fails closed above 20,000 entries. Authenticated context is independently rebound to the requested Vault, Entry id, current key version, projection revision, and minimum Member generation.
- Search operates only on the unlocked in-memory index. `PalladinApp` clears all decrypted indexes on every unlocked-to-locked or session-loss transition; the ciphertext cache remains available to rebuild offline after the next unlock.

### Resumable staged key rotation (CVT-441)

- `VaultRotationService` starts after unlock, lists only server-owned pending work, claims a fenced lease, verifies that the claimed plan matches the listed immutable generations/epochs, and uploads pages of at most 100 prepared envelopes. It retries a dirty atomic commit at most three times.
- Lease renewal receives a new fencing token and reopens the claimant's pending VK, VDK, and private-key envelopes. Every pending secret must match the process-local seed in constant time; a reset, changed plan, missing seed, or stale client fails closed instead of mixing generations.
- `VaultRotationCryptoService` is the sole rotation crypto boundary: it opens/seals scoped Member VK packages, rotates VK/VDK projections, rewraps Entry DEKs, generates Agent manifests, and signs them with the pending Ed25519 seed. All generated and opened keys are process memory only and are wiped on success, failure, cancellation, lock, or app background pause; progress persistence remains ciphertext-only on the backend.
- `PalladinApp` resumes pending work when an authenticated Vault unlocks and cancels the active Dio token whenever that session locks or disappears. The current generation remains authoritative until the backend's atomic commit succeeds.

### Canonical Entry detail and versioned edit (CVT-452)

- Entry Detail renders the already-decrypted in-memory MemberIndex first and does not fetch MemberSecret until the user explicitly reveals details or enters edit mode. A canonical authentication failure never falls back to the legacy plaintext/blob repository path.
- A save emits exactly one optimistic backend transition: immutable MemberSecret revision `N+1`, the next MemberIndex head and the next AgentDiscovery high-watermark revision are encrypted locally and switched atomically. A stale Member generation also rewraps the Entry DEK as the next key version before binding all projections to it.
- HTTP `409` is a dedicated edit-conflict state rather than a generic validation error. Lock, background and widget disposal drop decrypted Cubit state, controller values, reveal flags and TOTP state; keys and temporary plaintext byte buffers are wiped in `finally` paths.

### Entry Agent policy and exact-revision grants (CVT-453)

- The Entry Agents tab decrypts the authenticated canonical policy only while unlocked, validates one closed `AgentFieldAccess` value per schema field and renders only the resulting Discovery preview. TOTP source fields accept only `never`/`onGrantDerived`; Script source and refs accept only `never`/`onGrantRuntime`. VK, VDK, EntryDEK and source secrets never enter widget state or copy actions.
- A policy save creates one immutable canonical revision. Discovery advances only when its effective projection changes; private-only policy changes do not leak through the Discovery cursor.
- Before any grant encryption, the local projector proves every approved field is still within the Entry policy. Every active covering grant is fetched with bounded cursor pagination, refreshed to the exact new Entry revision with a fresh GrantDEK, and submitted in the same optimistic Entry transaction. Missing, extra, stale or widening scope fails closed and the backend commits all heads/envelopes or none.
- Lock, background, conflict and successful save clear the decrypted snapshot. Member keys, GrantDEKs, plaintext payload bytes, recipient-key copies and sealed-package buffers are wiped in `finally` paths.

### Import / Export (CVT-37 / CVT-235)

- **Import engine** — `data/import/` is pure, testable Dart: `import_engine.dart` (structure-based format detection: ZIP → JSON → XML → CSV, never by extension), `import_csv.dart` (declarative `CsvProfile`s — add a format by appending a profile), `import_json.dart` (Bitwarden / Keeper / Proton / 1Password / Enpass / Palladin), `import_xml.dart` (KeePass), `import_normalizer.dart` (TOTP→`otpauth://`, URL→host, name-from-host, trim), `import_models.dart`. Unrecognised CSVs fall back to a manual column mapper.
- **Export** — `data/export/`: `export_serializers.dart` (`toPalladinCsv` RFC 4180 / `toPalladinJson` v1, both pure), `export_sharer.dart` (`ExportSharer` interface; the concrete impl shares via `XFile.fromData` — no self-managed plaintext temp file, matching the recovery-key precedent).
- **Repository** — `EntryRepositoryImpl.importEntriesEncrypted` unwraps the VK **once**, encrypts every draft, POSTs bulk creates in chunks of 500 + PUTs overwrites, streams progress, zeroes the VK in `finally`. `revealAllEntries` unwraps once for export. `logExportAudit` is best-effort.
- **Backend contract (implemented in parallel — CVT-35/233):** `POST /api/vaults/{id}/entries/import` `{format, entries:[…, grantEntries:[]]}` → `{importedCount, entryIds}`; `POST /api/vaults/{id}/export-audit` `{format, entryCount}`. Mobile sends an empty `grantEntries` list (the create flow does not carry FULL-grant wrap material — the backend re-wraps).
- **Security:** all parsing on-device; secrets (`password`, `totp`) never logged; the column mapper never samples cell values (would leak a password); the export sheet gates behind a `WarningZone` plaintext warning.

### Entry richness — blob schema v2 + TOTP + Script (CVT-174/175/176/245/246)

The decrypted entry blob is **additive v2**: well-known fields stay top-level, a
`fields[]` array of custom fields is added beside them, and a new `SCRIPT`
entry type (`EntryType.script`, wire `2`) carries `script` / `interpreter`
(`bash|sh|node|python`) / `refs[]` (explicit `env → entryId.field` mappings).
Absence of `v` ⇒ legacy v1. Unknown field types (`url`, `date`, … / anything
future) parse to `CustomFieldType.unknown` and are **held aside and re-emitted
unchanged** on save so an older client never drops a newer client's fields.

- **Models** (`domain/entities/`): `custom_field.dart` (`CustomField` +
  `CustomFieldType`), `totp_config.dart` (`TotpConfig` — parses `otpauth://`
  URIs and base32, RFC defaults SHA1/6/30), and `ScriptPayload` / `ScriptRef` /
  `ScriptInterpreter` in `entry_entity.dart`. `KeyPayload` / `CredentialPayload`
  gained `fields`.
- **TOTP** (`data/services/totp_service.dart`): stateless RFC 6238 generator
  (HMAC via `crypto`, local base32 decoder); tested against the RFC 6238
  vectors. Never inline TOTP maths in a widget. `TotpDisplay` shows the live
  code + countdown ring; `TotpSetupSheet` + `TotpScannerPage` (mobile_scanner)
  capture a secret via QR / paste / manual base32.
- **Custom fields UI**: `CustomFieldsEditor` (reorderable rows: name + type +
  value/TOTP) on Add/Edit; the read-only detail renders each field with the
  Locked Value Pattern (concealed/totp masked until revealed).
- **Script UI**: `ScriptRefsEditor` (env ← entry.field rows, backed by
  `entry_field_names.dart` well-known field options) + the `WarningZone`
  exec-only notice; Script entries hide the URL field and show a `terminal`
  glyph in the list. `OnboardingTextField` gained a `monospace` flag for the
  script body.
- **Crypto is unchanged** — `fields` / `script` / `refs` live inside the same
  opaque `crypto_secretbox` blob, so the existing encrypt / edit / re-wrap path
  covers them with no new endpoints.

### Add/Edit redesign + agent-visible fields (CVT-204, mockup parity)

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
- **Additional fields** (`CustomFieldsEditor`) is a grouped card of one-line
  rows (type glyph + inline label/value + "⋯"). The row menu (`showAppMenuSheet`)
  changes type, toggles **Visible to agents** (text/multiline only), reorders,
  and removes. Field ids are stable (never regenerated).
- **agentVisible (CVT-204)**: `CustomField.agentVisible` serializes
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

### Entry version history (CVT-454)

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

### Dedicated Entry Archive (CVT-456)

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

### Recently Deleted Entry lifecycle (CVT-457)

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

**⚠ Architecture smells:**
- `VaultListPage` builds a raw `Container(gradient) + Scaffold(transparent)` (~line 185) instead of `AppScreen.titled(...)` — the one inconsistent top-level tab.
- `VaultDetailPage` / `EntryDetailPage` hand-roll `Container + DefaultTabController + Scaffold + AppBar` instead of `AppScreen.appBar(...)` (justified by the `PreferredSize` tab-bar height, but still skips the abstraction).
- `_SkeletonCard` (vault_list) and `_SkeletonRow` (vault_entries_tab) reimplement `SkeletonBox` — replace.
- AppBar titles duplicate the `AppBarTitle` pattern (see the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md)).
