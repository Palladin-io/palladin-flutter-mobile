# grants

Org-wide grant history feed + per-context grants tab (vault / entry / agent).

- **Cubit:** `OrgGrantsCubit`.
- **Pages:** none standalone — `ContextGrantsTab` is embedded inside vault/entry/agent detail screens.
- **Widgets:** `OrgGrantCard`, `ContextGrantsTab`, `RevokeGrantSheet`, and `GrantDetailRow` (exported, also used by `notifications`).
- **Layering:** full data / domain / presentation split. Holds the grant domain entities consumed by `approval`.
- **Scopes:** `Granular`, `Full`, and `ScriptExecution` are separate domain cases. Script grants expose only value-free structural `scriptScopes` and `scriptPackageRevision` to Member UI; ciphertext is never returned by list/detail endpoints. Grant cards and re-grant sheets label Script execution explicitly and lock its method to `Exec`.
- **Authoritative grant discriminator:** management DTOs require the backend's explicit `type` (`full`, `granular`, or `scriptExecution`). The data boundary rejects missing, unknown, and legacy alias-only values instead of reconstructing access scope from `entryId`, payload shape, endpoint, `mode`, `scope`, or `grantMode`.
- **Encrypted history reasons:** list/detail DTOs retain the backend's canonical
  `EncryptedReason` envelope only in the data layer. `GrantReasonResolver`
  authenticates the Agent signing identity and Vault message-key fingerprint,
  then decrypts the justification with the process-memory Member key before
  mapping it into the in-memory `Grant` presentation entity. Temporary key and
  plaintext byte buffers are wiped; failures hide only the reason, never the
  structural grant row. No plaintext reason is persisted or logged.
- **Local Entry labels:** management DTOs carry only the structural `vaultId`
  and `entryId`. `GrantEntryLabelResolver` groups rows by Vault and resolves
  each label from the locally decrypted, runtime-only `MemberIndex`; a
  server-supplied plaintext `entryLabel` is ignored. Resolution failure keeps
  the structural grant row visible with the localized unknown-Entry fallback.
  A monotonic Member-key session guard aborts multi-Vault resolution and drops
  every plaintext projection when the app locks or replaces the Member key.
  Independent Vault indexes load through a bounded four-worker pool so an
  org-wide page does not serialize one synchronization round trip per Vault.
- **Server-authoritative history footers:** `Grant` carries `canRevoke`,
  `canGrantAgain`, and `activeCoveringGrantIds`. Active cards revoke; terminal
  expired/consumed/denied/revoked cards re-grant when allowed. Coverage-blocked
  cards open the exact newer active Grant in a detail sheet, including its
  revoke action. An active FULL Grant can be resolved even when the source card
  came from an Entry-scoped list. Other unavailable terminal records link to
  the related Agent or Vault instead of presenting a dead footer. Pending rows
  visible in a context tab link back to the Inbox review queue.

**Cross-feature deps:** `agents` (`AgentAvatar`), `approval` (consumes grant
entities), `vault` (`MemberEntryListLoader` for local Entry presentation).
Embedded by `vault`.

**⚠ Architecture smell:** `RevokeGrantSheet` inlines the drag handle → extract `SheetDragHandle`. `GrantDetailRow` is a 76px-label variant of the duplicated label/value row pattern — fold into `LabelValueRow` if generalizing. See the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md).
