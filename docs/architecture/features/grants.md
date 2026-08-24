# grants

Org-wide grant history feed + per-context grants tab (vault / entry / agent).

- **Cubit:** `OrgGrantsCubit`.
- **Pages:** none standalone — `ContextGrantsTab` is embedded inside vault/entry/agent detail screens.
- **Widgets:** `OrgGrantCard`, `ContextGrantsTab`, `RevokeGrantSheet`, and `GrantDetailRow` (exported, also used by `notifications`).
- **Layering:** full data / domain / presentation split. Holds the grant domain entities consumed by `approval`.
- **Scopes:** `Granular`, `Full`, and `ScriptExecution` are separate domain cases. Script grants expose only value-free structural `scriptScopes` and `scriptPackageRevision` to Member UI; ciphertext is never returned by list/detail endpoints. Grant cards and re-grant sheets label Script execution explicitly and lock its method to `Exec`.
- **Encrypted history reasons:** list/detail DTOs retain the backend's canonical
  `EncryptedReason` envelope only in the data layer. `GrantReasonResolver`
  authenticates the Agent signing identity and Vault message-key fingerprint,
  then decrypts the justification with the process-memory Member key before
  mapping it into the in-memory `Grant` presentation entity. Temporary key and
  plaintext byte buffers are wiped; failures hide only the reason, never the
  structural grant row. No plaintext reason is persisted or logged.

**Cross-feature deps:** `agents` (`AgentAvatar`), `approval` (consumes grant entities). Embedded by `vault`.

**⚠ Architecture smell:** `RevokeGrantSheet` inlines the drag handle → extract `SheetDragHandle`. `GrantDetailRow` is a 76px-label variant of the duplicated label/value row pattern — fold into `LabelValueRow` if generalizing. See the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md).
