/// Runtime-only snapshot projected from the decrypted local MemberIndex.
///
/// It carries the authenticated structural head coordinates required to open
/// the selected local MemberSecret without persisting plaintext or key data.
class RecentEntryEntity {
  const RecentEntryEntity({
    required this.id,
    required this.label,
    required this.vaultId,
    required this.vaultName,
    required this.typeWire,
    required this.currentRevision,
    required this.currentKeyVersion,
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
  final String currentRevision;
  final int currentKeyVersion;

  /// Optional icon identifier (name like "vpn_key" or a remote URL).
  final String? icon;

  final DateTime updatedAt;
  final DateTime createdAt;
}
