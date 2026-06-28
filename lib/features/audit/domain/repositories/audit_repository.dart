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
  /// newest-first. Optional filters narrow the feed server-side.
  Future<AuditLogPage> listVaultLogs(
    String vaultId, {
    List<String> actions,
    String? agentId,
    String? userId,
    String? entryId,
    DateTime? from,
    DateTime? to,
    String? cursor,
    int pageSize,
  });

  /// Returns one page of org-wide audit logs (every vault the caller can
  /// see), newest-first. Optional filters narrow the feed server-side.
  Future<AuditLogPage> listOrgLogs({
    List<String> actions,
    String? vaultId,
    String? agentId,
    String? userId,
    String? entryId,
    DateTime? from,
    DateTime? to,
    String? cursor,
    int pageSize,
  });
}
