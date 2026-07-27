# approval

Zero-knowledge grant approval/denial — the crypto-sensitive heart of access control.

- **Cubits:** `PendingGrantsCubit`, `GrantApprovalCubit`, `GrantAccessCubit`, `RegrantCubit`.
- **Pages:** none — **sheets only**, presented over other features.
- **Widgets:** `ApproveGrantSheet`, `DenyGrantSheet`, `GrantAccessSheet`, `GrantLimitSelector`, `GrantMethodsSelector`, `RegrantSheet`.
- **Layering:** full data / domain / presentation split. `ApprovalRepositoryImpl` opens the canonical MemberSecret with the process-memory `VaultSessionStore`, projects the exact authorized field scope, and delegates protocol-v2 envelope sealing to `EntryV2CryptoService`. Agent recipient key versions and field scopes are authenticated in AAD; secret buffers are wiped in `finally`.

**Cross-feature deps:** `auth` (private key), `grants` (domain entities). Its sheets are invoked from `vault`, `agents`, and `notifications`.

**⚠ Architecture smell:** every sheet inlines the 36×4 drag handle → extract `SheetDragHandle` (see the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md)). Use `SheetActionButtons` for the footer.
