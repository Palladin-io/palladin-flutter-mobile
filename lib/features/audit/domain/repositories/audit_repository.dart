import '../entities/audit_log_entry.dart';

/// One page of audit log entries plus the cursor for the next page.
class AuditLogPage {
  const AuditLogPage({required this.entries, this.nextCursor});

  /// Entries on this page, newest-first as returned by the backend.
  final List<AuditLogEntry> entries;

  /// Opaque cursor for the next page, or `null` when the feed is
  /// exhausted.
  final String? nextCursor;
}

/// Domain contract for reading audit logs.
///
/// Implemented in the data layer by `AuditRepositoryImpl`. Failures
/// surface as `AuditException` with a typed `AuditErrorKind`.
abstract interface class AuditRepository {
  /// Returns one page of audit logs scoped to a single [vaultId],
  /// newest-first. The backend has no native entry-level filter, so
  /// entry scoping is applied by the caller (see `EntryLogsCubit`).
  Future<AuditLogPage> listVaultLogs(
    String vaultId, {
    String? cursor,
    int pageSize,
  });
}
