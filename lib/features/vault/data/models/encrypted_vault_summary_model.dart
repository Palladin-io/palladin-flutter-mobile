/// Ciphertext-only Vault summary returned by the Vault v2 list endpoint.
final class EncryptedVaultSummaryModel {
  const EncryptedVaultSummaryModel({
    required this.id,
    required this.isDefault,
    required this.protocolVersion,
    required this.memberSequence,
    required this.discoverySequence,
    required this.memberKeyGeneration,
    required this.memberVaultMetadata,
    required this.memberVaultKey,
    required this.currentKeyEpoch,
    required this.discoveryKey,
    required this.vaultPrivateKeys,
    required this.createdAt,
    required this.updatedAt,
    required this.memberCount,
    required this.entryCount,
    required this.activeGrantCount,
  });

  factory EncryptedVaultSummaryModel.fromJson(Map<String, dynamic> json) {
    final privateKeys = json['vaultPrivateKeys'];
    final memberSequence = json['memberSequence'];
    final discoverySequence = json['discoverySequence'];
    if (json['protocolVersion'] != 2 ||
        json['isDefault'] is! bool ||
        memberSequence is! String ||
        !_canonicalUint64.hasMatch(memberSequence) ||
        discoverySequence is! String ||
        !_canonicalUint64.hasMatch(discoverySequence) ||
        json['memberVaultMetadata'] is! Map ||
        json['memberVaultKey'] is! Map ||
        json['currentKeyEpoch'] is! Map ||
        json['discoveryKey'] is! Map ||
        privateKeys is! List ||
        privateKeys.length != 2 ||
        privateKeys.any((value) => value is! Map)) {
      throw const FormatException('Malformed encrypted Vault summary');
    }
    return EncryptedVaultSummaryModel(
      id: json['id'] as String,
      isDefault: json['isDefault'] as bool,
      protocolVersion: json['protocolVersion'] as int,
      memberSequence: json['memberSequence'] as String,
      discoverySequence: json['discoverySequence'] as String,
      memberKeyGeneration: json['memberKeyGeneration'] as int,
      memberVaultMetadata: Map<String, dynamic>.from(
        json['memberVaultMetadata'] as Map,
      ),
      memberVaultKey: Map<String, dynamic>.from(json['memberVaultKey'] as Map),
      currentKeyEpoch: Map<String, dynamic>.from(
        json['currentKeyEpoch'] as Map,
      ),
      discoveryKey: Map<String, dynamic>.from(json['discoveryKey'] as Map),
      vaultPrivateKeys: (json['vaultPrivateKeys'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList(growable: false),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      memberCount: json['memberCount'] as int,
      entryCount: json['entryCount'] as int,
      activeGrantCount: json['activeGrantCount'] as int,
    );
  }

  final String id;
  final bool isDefault;
  final int protocolVersion;
  final String memberSequence;
  final String discoverySequence;
  final int memberKeyGeneration;
  final Map<String, dynamic> memberVaultMetadata;
  final Map<String, dynamic> memberVaultKey;
  final Map<String, dynamic> currentKeyEpoch;
  final Map<String, dynamic> discoveryKey;
  final List<Map<String, dynamic>> vaultPrivateKeys;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int memberCount;
  final int entryCount;
  final int activeGrantCount;
}

final RegExp _canonicalUint64 = RegExp(r'^(0|[1-9][0-9]{0,19})$');

final class EncryptedVaultPage {
  const EncryptedVaultPage({required this.vaults, required this.total});
  final List<EncryptedVaultSummaryModel> vaults;
  final int total;
}
