/// Ciphertext-free structural status for one Agent's Vault Discovery access.
final class AgentDiscoveryProvisioning {
  const AgentDiscoveryProvisioning({
    required this.agentId,
    required this.recipientKeyVersion,
    required this.status,
    required this.publicKey,
    required this.keySuiteId,
    required this.ed25519PublicKey,
    this.agentName,
    this.manifestRevision,
  });

  factory AgentDiscoveryProvisioning.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (json['agentId'] is! String ||
        json['recipientKeyVersion'] is! int ||
        json['publicKey'] is! String ||
        json['keySuiteId'] is! String ||
        json['ed25519PublicKey'] is! String ||
        (status != 'current' && status != 'pending')) {
      throw const FormatException('Malformed Discovery provisioning row');
    }
    return AgentDiscoveryProvisioning(
      agentId: json['agentId'] as String,
      agentName: json['agentName'] as String?,
      recipientKeyVersion: json['recipientKeyVersion'] as int,
      publicKey: json['publicKey'] as String,
      keySuiteId: json['keySuiteId'] as String,
      ed25519PublicKey: json['ed25519PublicKey'] as String,
      status: status as String,
      manifestRevision: json['manifestRevision'] as String?,
    );
  }

  final String agentId;
  final String? agentName;
  final int recipientKeyVersion;

  /// Agent encryption key from the authenticated directory.
  final String publicKey;

  /// Suite the key is published under; the authority for sealing to it.
  final String keySuiteId;
  final String ed25519PublicKey;
  final String status;
  final String? manifestRevision;
  bool get isCurrent => status == 'current';
}
