/// Ciphertext-free structural status for one Agent's Vault Discovery access.
final class AgentDiscoveryProvisioning {
  const AgentDiscoveryProvisioning({
    required this.agentId,
    required this.recipientKeyVersion,
    required this.status,
    required this.x25519PublicKey,
    required this.ed25519PublicKey,
    this.agentName,
    this.manifestRevision,
  });

  factory AgentDiscoveryProvisioning.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (json['agentId'] is! String ||
        json['recipientKeyVersion'] is! int ||
        json['x25519PublicKey'] is! String ||
        json['ed25519PublicKey'] is! String ||
        (status != 'current' && status != 'pending')) {
      throw const FormatException('Malformed Discovery provisioning row');
    }
    return AgentDiscoveryProvisioning(
      agentId: json['agentId'] as String,
      agentName: json['agentName'] as String?,
      recipientKeyVersion: json['recipientKeyVersion'] as int,
      x25519PublicKey: json['x25519PublicKey'] as String,
      ed25519PublicKey: json['ed25519PublicKey'] as String,
      status: status as String,
      manifestRevision: json['manifestRevision'] as String?,
    );
  }

  final String agentId;
  final String? agentName;
  final int recipientKeyVersion;
  final String x25519PublicKey;
  final String ed25519PublicKey;
  final String status;
  final String? manifestRevision;
  bool get isCurrent => status == 'current';
}
