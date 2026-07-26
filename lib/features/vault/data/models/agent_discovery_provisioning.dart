/// Ciphertext-free structural status for one Agent's Vault Discovery access.
final class AgentDiscoveryProvisioning {
  const AgentDiscoveryProvisioning({
    required this.agentId,
    required this.recipientKeyVersion,
    required this.status,
    this.agentName,
    this.manifestRevision,
  });

  factory AgentDiscoveryProvisioning.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (json['agentId'] is! String ||
        json['recipientKeyVersion'] is! int ||
        (status != 'current' && status != 'pending')) {
      throw const FormatException('Malformed Discovery provisioning row');
    }
    return AgentDiscoveryProvisioning(
      agentId: json['agentId'] as String,
      agentName: json['agentName'] as String?,
      recipientKeyVersion: json['recipientKeyVersion'] as int,
      status: status as String,
      manifestRevision: json['manifestRevision'] as String?,
    );
  }

  final String agentId;
  final String? agentName;
  final int recipientKeyVersion;
  final String status;
  final String? manifestRevision;
  bool get isCurrent => status == 'current';
}
