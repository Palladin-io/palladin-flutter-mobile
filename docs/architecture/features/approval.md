# approval

Zero-knowledge grant approval/denial — the crypto-sensitive heart of access control.

- **Cubits:** `PendingGrantsCubit`, `GrantApprovalCubit`, `GrantAccessCubit`, `RegrantCubit`.
- **Pages:** none — **sheets only**, presented over other features.
- **Widgets:** `ApproveGrantSheet`, `DenyGrantSheet`, `GrantAccessSheet`, `GrantLimitSelector`, `GrantMethodsSelector`, `RegrantSheet`.
- **Layering:** full data / domain / presentation split. `GrantCryptoService` wraps/re-wraps the vault entry key per grant (reads the in-memory private key from `AuthBloc`, `try/finally` zero-out).

**Cross-feature deps:** `auth` (private key), `grants` (domain entities). Its sheets are invoked from `vault`, `agents`, and `notifications`.

**⚠ Architecture smell:** every sheet inlines the 36×4 drag handle → extract `SheetDragHandle` (see [../widget-catalog.md](../widget-catalog.md)). Use `SheetActionButtons` for the footer.
