/// Structural deprovisioning state returned by the Vault Member directory.
enum VaultMemberStatus {
  active,
  pending,
  waitingForRotation,
  blockedLastMember;

  static VaultMemberStatus fromWire(String value) => switch (value) {
    'Active' => active,
    'Pending' => pending,
    'WaitingForRotation' => waitingForRotation,
    'BlockedLastMember' => blockedLastMember,
    _ => throw FormatException('Unknown Vault Member status'),
  };
}

/// One Member with access to a Vault and its staged removal state.
final class VaultMember {
  const VaultMember({
    required this.id,
    required this.addedAt,
    required this.status,
    this.name,
    this.rotationId,
  });

  final String id;
  final String? name;
  final DateTime addedAt;
  final VaultMemberStatus status;
  final String? rotationId;

  bool get removalInProgress => status != VaultMemberStatus.active;
}
