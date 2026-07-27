# vault

Vault and entry management — the largest feature. List, detail, create, edit; per-entry-type crypto.

- **Cubits:** `VaultListCubit`, `VaultDetailCubit`, `EntryListCubit`, `CreateVaultCubit`, `CreateEntryCubit`, `EditEntryCubit`, `ImportWizardCubit`, `ExportCubit`.
- **Pages:** `VaultListPage`, `VaultDetailPage` (5 tabs: Entries, Agents, Logs, Members, Settings; two FAB modes; AppBar kebab → Import / Export), `EntryDetailPage`, `AddEntryPage`, `ImportWizardPage`, `ImportVaultPickerPage`.
- **Key widgets:** `VaultEntriesTab`, `CreateVaultSheet`, entry-type forms, icon picker (via `IconColorBrowserSheet`), `ExportSheet`, `ImportPreviewList`, `ImportColumnMapper`.
- **Layering:** full data / domain / presentation split, with per-type crypto services in `data/services/` (zero-knowledge, `try/finally` zero-out).

### Import / Export (CVT-37 / CVT-235)

- **Import engine** — `data/import/` is pure, testable Dart: `import_engine.dart` (structure-based format detection: ZIP → JSON → XML → CSV, never by extension), `import_csv.dart` (declarative `CsvProfile`s — add a format by appending a profile), `import_json.dart` (Bitwarden / Keeper / Proton / 1Password / Enpass / Palladin), `import_xml.dart` (KeePass), `import_normalizer.dart` (TOTP→`otpauth://`, URL→host, name-from-host, trim), `import_models.dart`. Unrecognised CSVs fall back to a manual column mapper.
- **Export** — `data/export/`: `export_serializers.dart` (`toPalladinCsv` RFC 4180 / `toPalladinJson` v1, both pure), `export_sharer.dart` (`ExportSharer` interface; the concrete impl shares via `XFile.fromData` — no self-managed plaintext temp file, matching the recovery-key precedent).
- **Repository** — `EntryRepositoryImpl.importEntriesEncrypted` copies the in-memory VK once, encrypts every draft, POSTs bulk creates in chunks of 500 + PUTs overwrites, streams progress, and zeroes key copies in `finally`. Before create/update it exhausts the active-grant cursor and refreshes every covering canonical Grant envelope atomically; an empty refresh list is valid only when no active grant covers the Entry. `revealAllEntries` reuses the canonical reveal path. `logExportAudit` is best-effort.
- **Backend contract (CVT-35/233):** `POST /api/vaults/{id}/entries/import` accepts complete canonical Entry bundles plus `grantEnvelopes` for every active FULL grant and returns `{importedCount, entryIds}`; `POST /api/vaults/{id}/export-audit` accepts `{format, entryCount}`.
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

### Canonical Vault protocol-v2 crypto cutover

The shared client envelope primitives live under `lib/core/crypto/envelope/`.
They implement the accepted pre-production protocol-v2 contract: a stable,
purpose-validated `EnvelopeDescriptor`, canonical binary AAD and HKDF context,
the compiled `palladin-vault-xchacha-v1` allowlist, and a bounded opaque suite
payload (`nonce[24] || ciphertext+tag`, base64url without padding). X25519
recipient wrappers and Ed25519 signing keys are separate types and cannot be
substituted for one another.

The layer is intentionally not adapted to the legacy Entry API shape
(`encryptedBlob` + `nonce`). There is no dual-read or fallback. Feature
repositories switch to this layer only when the backend exposes the matching
protocol-v2 descriptor and opaque-payload contracts; the cutover then removes
the legacy XSalsa path atomically.

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

**⚠ Architecture smells:**
- `VaultListPage` builds a raw `Container(gradient) + Scaffold(transparent)` (~line 185) instead of `AppScreen.titled(...)` — the one inconsistent top-level tab.
- `VaultDetailPage` / `EntryDetailPage` hand-roll `Container + DefaultTabController + Scaffold + AppBar` instead of `AppScreen.appBar(...)` (justified by the `PreferredSize` tab-bar height, but still skips the abstraction).
- `_SkeletonCard` (vault_list) and `_SkeletonRow` (vault_entries_tab) reimplement `SkeletonBox` — replace.
- AppBar titles duplicate the `AppBarTitle` pattern (see the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md)).
