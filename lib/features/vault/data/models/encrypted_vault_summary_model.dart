/// Ciphertext-only Vault summary returned by the Vault v2 list endpoint.
final class EncryptedVaultSummaryModel {
  const EncryptedVaultSummaryModel({
    required this.id,
    required this.protocolVersion,
    required this.memberKeyGeneration,
    required this.memberVaultMetadata,
    required this.memberVaultKey,
    required this.currentKeyEpoch,
    this.discoveryKey,
    required this.createdAt,
    required this.updatedAt,
    required this.memberCount,
    required this.entryCount,
    required this.activeGrantCount,
  });

  factory EncryptedVaultSummaryModel.fromJson(Map<String, dynamic> json) {
    if (json['protocolVersion'] != 2 ||
        json['memberVaultMetadata'] is! Map ||
        json['memberVaultKey'] is! Map) {
      throw const FormatException('Malformed encrypted Vault summary');
    }
    return EncryptedVaultSummaryModel(
      id: json['id'] as String,
      protocolVersion: json['protocolVersion'] as int,
      memberKeyGeneration: json['memberKeyGeneration'] as int,
      memberVaultMetadata: Map<String, dynamic>.from(
        json['memberVaultMetadata'] as Map,
      ),
      memberVaultKey: Map<String, dynamic>.from(json['memberVaultKey'] as Map),
      currentKeyEpoch: Map<String, dynamic>.from(
        json['currentKeyEpoch'] as Map,
      ),
      discoveryKey: json['discoveryKey'] is Map
          ? Map<String, dynamic>.from(json['discoveryKey'] as Map)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      memberCount: json['memberCount'] as int,
      entryCount: json['entryCount'] as int,
      activeGrantCount: json['activeGrantCount'] as int,
    );
  }

  final String id;
  final int protocolVersion;
  final int memberKeyGeneration;
  final Map<String, dynamic> memberVaultMetadata;
  final Map<String, dynamic> memberVaultKey;
  final Map<String, dynamic> currentKeyEpoch;
  final Map<String, dynamic>? discoveryKey;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int memberCount;
  final int entryCount;
  final int activeGrantCount;
}

final class EncryptedVaultPage {
  const EncryptedVaultPage({required this.vaults, required this.total});
  final List<EncryptedVaultSummaryModel> vaults;
  final int total;
}
