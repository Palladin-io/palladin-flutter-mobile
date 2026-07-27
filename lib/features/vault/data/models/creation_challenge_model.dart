/// Server-reserved identifier used to bind client-side Vault creation.
final class VaultCreationChallengeModel {
  const VaultCreationChallengeModel({
    required this.vaultId,
    required this.expiresAt,
  });

  final String vaultId;
  final DateTime expiresAt;

  factory VaultCreationChallengeModel.fromJson(Map<String, dynamic> json) =>
      VaultCreationChallengeModel(
        vaultId: json['vaultId'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}

/// Server-reserved identifier used to bind a canonical Entry creation.
final class EntryCreationChallengeModel {
  const EntryCreationChallengeModel({
    required this.entryId,
    required this.expiresAt,
  });

  final String entryId;
  final DateTime expiresAt;

  factory EntryCreationChallengeModel.fromJson(Map<String, dynamic> json) =>
      EntryCreationChallengeModel(
        entryId: json['entryId'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}
