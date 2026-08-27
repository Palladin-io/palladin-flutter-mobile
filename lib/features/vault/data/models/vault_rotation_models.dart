/// Frozen structural plan for one staged Vault key rotation.
final class VaultRotationModel {
  const VaultRotationModel({
    required this.id,
    required this.vaultId,
    required this.status,
    required this.scope,
    required this.baseMemberKeyGeneration,
    required this.targetMemberKeyGeneration,
    required this.baseKeyEpoch,
    required this.targetKeyEpoch,
  });

  factory VaultRotationModel.fromJson(Map<String, dynamic> json) =>
      VaultRotationModel(
        id: _string(json, 'id'),
        vaultId: _string(json, 'vaultId'),
        status: _string(json, 'status'),
        scope: _strings(json, 'scope', maximum: 4),
        baseMemberKeyGeneration: _uint(json, 'baseMemberKeyGeneration'),
        targetMemberKeyGeneration: _uint(json, 'targetMemberKeyGeneration'),
        baseKeyEpoch: VaultKeyEpochModel.fromJson(_map(json, 'baseKeyEpoch')),
        targetKeyEpoch: VaultKeyEpochModel.fromJson(
          _map(json, 'targetKeyEpoch'),
        ),
      );

  final String id;
  final String vaultId;
  final String status;
  final List<String> scope;
  final int baseMemberKeyGeneration;
  final int targetMemberKeyGeneration;
  final VaultKeyEpochModel baseKeyEpoch;
  final VaultKeyEpochModel targetKeyEpoch;

  bool rotates(String value) => scope.contains(value);

  bool samePlan(VaultRotationModel other) =>
      id == other.id &&
      vaultId == other.vaultId &&
      baseMemberKeyGeneration == other.baseMemberKeyGeneration &&
      targetMemberKeyGeneration == other.targetMemberKeyGeneration &&
      baseKeyEpoch == other.baseKeyEpoch &&
      targetKeyEpoch == other.targetKeyEpoch;
}

final class VaultKeyEpochModel {
  const VaultKeyEpochModel({
    required this.vaultKeyVersion,
    required this.vdkVersion,
    required this.agentMessageKeyVersion,
    required this.manifestSigningKeyVersion,
  });

  factory VaultKeyEpochModel.fromJson(Map<String, dynamic> json) =>
      VaultKeyEpochModel(
        vaultKeyVersion: _uint(json, 'vaultKeyVersion'),
        vdkVersion: _uint(json, 'vdkVersion'),
        agentMessageKeyVersion: _uint(json, 'agentMessageKeyVersion'),
        manifestSigningKeyVersion: _uint(json, 'manifestSigningKeyVersion'),
      );

  final int vaultKeyVersion;
  final int vdkVersion;
  final int agentMessageKeyVersion;
  final int manifestSigningKeyVersion;

  @override
  bool operator ==(Object other) =>
      other is VaultKeyEpochModel &&
      vaultKeyVersion == other.vaultKeyVersion &&
      vdkVersion == other.vdkVersion &&
      agentMessageKeyVersion == other.agentMessageKeyVersion &&
      manifestSigningKeyVersion == other.manifestSigningKeyVersion;

  @override
  int get hashCode => Object.hash(
    vaultKeyVersion,
    vdkVersion,
    agentMessageKeyVersion,
    manifestSigningKeyVersion,
  );
}

final class VaultRotationClaimModel {
  const VaultRotationClaimModel({
    required this.organizationId,
    required this.rotation,
    required this.fencingToken,
    required this.currentMemberVaultKey,
    required this.currentDiscoveryKey,
    required this.currentVaultPrivateKeys,
    required this.pendingVaultPrivateKeys,
    required this.preparedMaterialReset,
    this.pendingMemberVaultKey,
    this.pendingDiscoveryKey,
  });

  factory VaultRotationClaimModel.fromJson(
    Map<String, dynamic> json,
  ) => VaultRotationClaimModel(
    organizationId: _string(json, 'organizationId'),
    rotation: VaultRotationModel.fromJson(_map(json, 'rotation')),
    fencingToken: _string(json, 'fencingToken'),
    currentMemberVaultKey: _map(json, 'currentMemberVaultKey'),
    currentDiscoveryKey: _map(json, 'currentDiscoveryKey'),
    currentVaultPrivateKeys: _maps(json, 'currentVaultPrivateKeys', maximum: 2),
    pendingMemberVaultKey: _nullableMap(json, 'pendingMemberVaultKey'),
    pendingDiscoveryKey: _nullableMap(json, 'pendingDiscoveryKey'),
    pendingVaultPrivateKeys: _maps(json, 'pendingVaultPrivateKeys', maximum: 2),
    preparedMaterialReset: json['preparedMaterialReset'] as bool,
  );

  final String organizationId;
  final VaultRotationModel rotation;
  final String fencingToken;
  final Map<String, dynamic> currentMemberVaultKey;
  final Map<String, dynamic> currentDiscoveryKey;
  final List<Map<String, dynamic>> currentVaultPrivateKeys;
  final Map<String, dynamic>? pendingMemberVaultKey;
  final Map<String, dynamic>? pendingDiscoveryKey;
  final List<Map<String, dynamic>> pendingVaultPrivateKeys;
  final bool preparedMaterialReset;
}

final class RotationPage<T> {
  const RotationPage({
    required this.items,
    this.nextAfterId,
    this.nextAfterVersion,
  });

  final List<T> items;
  final String? nextAfterId;
  final int? nextAfterVersion;
}

final class RotationMemberRecipient {
  const RotationMemberRecipient({
    required this.memberId,
    required this.recipientKeyVersion,
    required this.recipientKeyFingerprint,
    required this.x25519PublicKey,
  });

  factory RotationMemberRecipient.fromJson(Map<String, dynamic> json) =>
      RotationMemberRecipient(
        memberId: _string(json, 'memberId'),
        recipientKeyVersion: _uint(json, 'recipientKeyVersion'),
        recipientKeyFingerprint: _string(json, 'recipientKeyFingerprint'),
        x25519PublicKey: _string(json, 'x25519PublicKey'),
      );

  final String memberId;
  final int recipientKeyVersion;
  final String recipientKeyFingerprint;
  final String x25519PublicKey;
}

final class RotationFullGrantRecipient {
  const RotationFullGrantRecipient({
    required this.grantId,
    required this.agentId,
    required this.agentAccessEpoch,
    required this.recipientKeyVersion,
    required this.recipientKeyFingerprint,
    required this.x25519PublicKey,
  });

  factory RotationFullGrantRecipient.fromJson(Map<String, dynamic> json) =>
      RotationFullGrantRecipient(
        grantId: _string(json, 'grantId'),
        agentId: _string(json, 'agentId'),
        agentAccessEpoch: _uint(json, 'agentAccessEpoch'),
        recipientKeyVersion: _uint(json, 'recipientKeyVersion'),
        recipientKeyFingerprint: _string(json, 'recipientKeyFingerprint'),
        x25519PublicKey: _string(json, 'x25519PublicKey'),
      );

  final String grantId;
  final String agentId;
  final int agentAccessEpoch;
  final int recipientKeyVersion;
  final String recipientKeyFingerprint;
  final String x25519PublicKey;
}

final class RotationDiscoverySource {
  const RotationDiscoverySource({
    required this.sourceRevision,
    required this.envelope,
  });

  factory RotationDiscoverySource.fromJson(Map<String, dynamic> json) =>
      RotationDiscoverySource(
        sourceRevision: _string(json, 'sourceRevision'),
        envelope: _map(json, 'envelope'),
      );

  final String sourceRevision;
  final Map<String, dynamic> envelope;
}

final class RotationAgentRecipient {
  const RotationAgentRecipient({
    required this.agentId,
    required this.x25519PublicKey,
    required this.ed25519PublicKey,
    required this.recipientKeyVersion,
    this.manifestRevision,
  });

  factory RotationAgentRecipient.fromJson(Map<String, dynamic> json) =>
      RotationAgentRecipient(
        agentId: _string(json, 'agentId'),
        x25519PublicKey: _string(json, 'x25519PublicKey'),
        ed25519PublicKey: _string(json, 'ed25519PublicKey'),
        recipientKeyVersion: _uint(json, 'recipientKeyVersion'),
        manifestRevision: json['manifestRevision'] as String?,
      );

  final String agentId;
  final String x25519PublicKey;
  final String ed25519PublicKey;
  final int recipientKeyVersion;
  final String? manifestRevision;
}

Map<String, dynamic> _map(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! Map) throw FormatException('$field must be an object');
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic>? _nullableMap(Map<String, dynamic> json, String field) =>
    json[field] == null ? null : _map(json, field);

List<Map<String, dynamic>> _maps(
  Map<String, dynamic> json,
  String field, {
  required int maximum,
}) {
  final value = json[field];
  if (value is! List || value.length > maximum) {
    throw FormatException('$field exceeds its bound');
  }
  return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
}

String _string(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

int _uint(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! int || value < 1 || value > 0xffffffff) {
    throw FormatException('$field must be a positive uint32');
  }
  return value;
}

List<String> _strings(
  Map<String, dynamic> json,
  String field, {
  required int maximum,
}) {
  final value = json[field];
  if (value is! List || value.length > maximum) {
    throw FormatException('$field exceeds its bound');
  }
  return value.map((item) => item as String).toList(growable: false);
}
