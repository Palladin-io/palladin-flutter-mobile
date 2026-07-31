# approval

Zero-knowledge grant approval/denial — the crypto-sensitive heart of access control.

- **Cubits:** `PendingGrantsCubit`, `GrantApprovalCubit`, `GrantAccessCubit`, `RegrantCubit`.
- **Pages:** none — **sheets only**, presented over other features.
- **Widgets:** `ApproveGrantSheet`, `DenyGrantSheet`, `GrantAccessSheet`, `GrantLimitSelector`, `GrantMethodsSelector`, `RegrantSheet`.
- **Layering:** full data / domain / presentation split. `ApprovalRepositoryImpl` opens the canonical MemberSecret with the process-memory `VaultSessionStore`, projects the exact authorized field scope, and delegates protocol-v2 envelope sealing to `EntryV2CryptoService`. Agent recipient key versions and field scopes are authenticated in AAD; secret buffers are wiped in `finally`.

### Protocol-2 approval review (CVT-458)

- Pending/push state is structural and ciphertext-only. Opening the approval sheet copies the unlocked Member key, fetches the current request and canonical Entry, resolves exactly one current authenticated Agent provisioning identity, verifies the encrypted-reason Ed25519 signature and frozen AAD, then decrypts the required reason locally. Plaintext review state is factory-scoped and cleared on lock/background/dispose/error/conflict.
- Approval narrows fields and methods against the authenticated `AgentVisibilityPolicy`, binds the grant to the reviewed Entry revision and selected expiry/use policy, and creates a fresh GrantDEK sealed to the current Agent X25519 key. TOTP is grant-derived only; Script source/refs are runtime-only.
- The repository refetches the request and Entry revision before submit. A `409` is a dedicated conflict: decrypted review state is wiped and the user must explicitly fetch and review again; there is no silent retry. Denial has no reason field or request body and never decrypts or transmits secret material.

**Cross-feature deps:** `auth` (private key), `grants` (domain entities). Its sheets are invoked from `vault`, `agents`, and `notifications`.

**⚠ Architecture smell:** every sheet inlines the 36×4 drag handle → extract `SheetDragHandle` (see the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md)). Use `SheetActionButtons` for the footer.
