# audit

Audit log viewer — a global page plus tabs embedded in vault/entry detail.

- **Cubits:** `AuditLogCubit`, `EntryLogsCubit`.
- **Pages:** `GlobalAuditLogPage`.
- **Widgets:** `AuditLogRow`, `AuditLogContent` (reusable — consumed by both `GlobalAuditLogPage` and vault's `VaultAuditLogTab`), `AuditLegendSheet`, `AuditLogFilterSheet`, `EntryLogsTab`, `VaultAuditLogTab`.
- **Layering:** full data / domain / presentation split. Note `audit_log_format.dart` and `audit_filters.dart` sit directly under `presentation/`, not `presentation/widgets/`.
- **Colors:** event colors follow the canonical Audit Log taxonomy — see the "Audit Log colors" rule in `CLAUDE.md`. Never hardcode hex; map roles to `AppColors`.

**Cross-feature deps:** embedded by `vault` (Logs tab). Filter/legend sheets inline the drag handle → extract `SheetDragHandle`.
