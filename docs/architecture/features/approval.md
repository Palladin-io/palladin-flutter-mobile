# approval

Zero-knowledge grant approval/denial — the crypto-sensitive heart of access control.

- **Cubits:** `PendingGrantsCubit`, `GrantApprovalCubit`, `GrantAccessCubit`, `RegrantCubit`.
- **Pages:** none — **sheets only**, presented over other features.
- **Widgets:** `ApproveGrantSheet`, `DenyGrantSheet`, `GrantAccessSheet`, `GrantLimitSelector`, `GrantMethodsSelector`, `RegrantSheet`.
- **Layering:** full data / domain / presentation split. `ApprovalRepositoryImpl` opens the canonical MemberSecret with the process-memory `VaultSessionStore`, projects the exact authorized field scope, and delegates protocol-v2 envelope sealing to `EntryV2CryptoService`. Agent recipient key versions are authenticated in AAD; secret buffers are wiped in `finally`.
- **Type-specific creation:** GRANULAR creation posts one revision-bound Entry envelope to the dedicated Entry endpoint. FULL creation opens the process-memory VK, seals it once to the current Agent X25519 identity as `AgentWrappedVaultKey`, and posts it to the dedicated FULL endpoint. The flows do not branch one generic request by a type flag and FULL remains O(1) in Vault size.
- **Pending-list refresh:** shell startup, Home, lifecycle resume, push, and an
  open Inbox share the Cubit's current in-flight list operation. This keeps the
  badge live without issuing overlapping `GET /api/dashboard/pending-grants`
  requests or replacing a visible list with a second loading transition. A
  push/resume invalidation or an Inbox action received during that operation
  queues at most one trailing quiet refresh, and callers that must resolve the
  new grant await that trailing request.

### Protocol-2 approval review

- Pending/push state is structural and ciphertext-only. Opening the approval sheet copies the unlocked Member key, fetches the current request and canonical Entry, resolves exactly one current authenticated Agent provisioning identity, verifies the encrypted-reason Ed25519 signature and frozen AAD, then decrypts the required reason locally. Plaintext review state is factory-scoped and cleared on lock/background/dispose/error/conflict.
- The pending-grant boundary parses the backend's canonical nested `EncryptedReasonEnvelopeContract`, including named JSON enums, so valid current requests are not misreported as unavailable. The ReasonDEK wrapper must match the parent scope and key binding exactly and target the Vault Message X25519 key; malformed or legacy envelopes fail closed.
- Approval narrows methods against the authenticated request, but in the MVP it always seals every currently present and grantable Entry field from the authenticated `AgentVisibilityPolicy`; fields marked `never`, Discovery-only fields, and authorized optional fields whose value is absent remain excluded, and the UI has no per-field selector. Review and submission derive this exact field set through the same projector. It binds the grant to the reviewed Entry revision and selected expiry/use policy, preserving the same microsecond-precision expiry in both the request and authenticated AAD, and creates a fresh GrantDEK sealed to the current Agent X25519 key. Async key opening completes before temporary ciphertext/signature buffers are wiped. Vault Protocol 2 carries `FieldIds` as structural Grant scope but does not include them in Grant-payload AAD; producers derive the structural list from the completed plaintext and consumers compare it for consistency, while the ciphertext itself contains only the locally policy-authorized projection. Adding a cryptographic outer field-set binding requires a new protocol-version decision. TOTP is grant-derived only; Script source/refs are runtime-only.

### Production GrantPayload boundary

- Granular approval and active-grant refresh emit the canonical JSON object `{"schema":"palladin.grant-payload.v1","entryType":...,"fields":[...]}`. Fields are unique and sorted by their canonical production `id`; every field contains exactly `id`, `kind`, `mode`, and `value`.
- Built-ins are mapped once by `AgentVisibilityProjector`; custom IDs use `custom:{uuid}`. Description is a built-in text field. Script references always leave the projector with `env`, `vaultId`, `entryId`, and canonical `fieldId`; an older blob that omits `vaultId` is normalized to the Script Entry's current Vault.
- `GrantCryptoService`, initial approval, re-grant, and active-envelope refresh all call the same projector and derive their submitted field list from the completed payload. The public synthetic vector is pinned in `test/fixtures/grant-payload/v1/` and consumed by exact-byte tests shared with React and Rust.
- `Get`, `Exec`, and `Inject` are owner-selected grant permissions, independent of the encrypted Entry type. Every type preserves the selected method mask unchanged and uses the standard delivery policy unless a future explicit policy is chosen. Refreshing an Entry preserves the grant's authenticated `FieldIds`; it never broadens an existing grant to newly grantable fields.
- The repository refetches the request and Entry revision before submit. A `409` is a dedicated conflict: decrypted review state is wiped and the user must explicitly fetch and review again; there is no silent retry. Denial has no reason field or request body and never decrypts or transmits secret material.

**Cross-feature deps:** `auth` (private key), `grants` (domain entities). Its sheets are invoked from `vault`, `agents`, and `notifications`.

**⚠ Architecture smell:** every sheet inlines the 36×4 drag handle → extract `SheetDragHandle` (see the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md)). Use `SheetActionButtons` for the footer.
