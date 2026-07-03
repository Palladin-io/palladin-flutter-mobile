/// Metadata-only snapshot of a recently updated entry.
///
/// Used exclusively on the Home (dashboard) screen to surface recent
/// vault activity without ever requesting or holding encrypted values.
/// ZK-safe: only the fields returned by `GET /api/entries?sort=recent`
/// are present here — no plaintext payload, no encryption material.
class RecentEntryEntity {
  const RecentEntryEntity({
    required this.id,
    required this.label,
    required this.vaultId,
    required this.vaultName,
    required this.typeWire,
    this.icon,
    required this.updatedAt,
    required this.createdAt,
  });

  final String id;
  final String label;
  final String vaultId;

  /// Human-readable vault name — resolved server-side, safe to display.
  final String vaultName;

  /// Wire-format entry type: 0 = Key, 1 = Credential.
  final int typeWire;

  /// Optional icon identifier (name like "vpn_key" or a remote URL).
  final String? icon;

  final DateTime updatedAt;
  final DateTime createdAt;
}
