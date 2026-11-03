import 'autofill_record.dart';

final class AutoFillCacheBase {
  const AutoFillCacheBase({required this.generation, required this.revision});
  final int generation;
  final int revision;

  factory AutoFillCacheBase.fromPlatform(Object? value) {
    if (value is! Map ||
        value.length != 2 ||
        value['generation'] is! int ||
        value['revision'] is! int ||
        (value['generation'] as int) <= 0 ||
        (value['revision'] as int) <= 0) {
      throw const FormatException('Invalid native AutoFill base');
    }
    return AutoFillCacheBase(
      generation: value['generation'] as int,
      revision: value['revision'] as int,
    );
  }
  Map<String, int> toPlatformMap() => {
    'generation': generation,
    'revision': revision,
  };
}

final class AutoFillEntryCoordinate {
  const AutoFillEntryCoordinate({required this.vaultId, required this.entryId});
  final String vaultId;
  final String entryId;
  Map<String, String> toPlatformMap() => {
    'vaultId': vaultId,
    'entryId': entryId,
  };
  @override
  bool operator ==(Object other) =>
      other is AutoFillEntryCoordinate &&
      other.vaultId == vaultId &&
      other.entryId == entryId;
  @override
  int get hashCode => Object.hash(vaultId, entryId);
}

final class AutoFillScopedDenial {
  const AutoFillScopedDenial({required this.base, required this.token});
  final AutoFillCacheBase base;
  final String token;
  factory AutoFillScopedDenial.fromPlatform(Object? value) {
    if (value is! Map ||
        value.length != 2 ||
        value['denyToken'] is! String ||
        (value['denyToken'] as String).isEmpty) {
      throw const FormatException('Invalid native AutoFill deny ownership');
    }
    return AutoFillScopedDenial(
      base: AutoFillCacheBase.fromPlatform(value['base']),
      token: value['denyToken'] as String,
    );
  }
}

/// V3 permits an authenticated empty catalog. Missing native state is never
/// represented by this complete manifest; it has no acknowledged base.
Map<String, Object> autoFillV3Manifest(AutoFillCacheManifest manifest) => {
  'principalId': manifest.principalId,
  'organizationId': manifest.organizationId,
  'organizationMembershipGeneration': manifest.organizationMembershipGeneration,
  'offlinePolicy': manifest.offlinePolicy,
  'offlinePolicyVersion': manifest.offlinePolicyVersion,
  'vaults': [
    for (final vault in manifest.vaults.entries)
      {
        'vaultId': vault.key,
        'contextVersion': vault.value.contextVersion,
        'memberId': vault.value.memberId,
        'memberKeyGeneration': vault.value.memberKeyGeneration,
        'vaultKeyVersion': vault.value.vaultKeyVersion,
        'memberRecipientKeyVersion': vault.value.memberRecipientKeyVersion,
        'memberRecipientKeyFingerprint':
            vault.value.memberRecipientKeyFingerprint,
        'issuedAt': vault.value.issuedAt.toUtc().toIso8601String(),
        'notAfter': vault.value.notAfter.toUtc().toIso8601String(),
        'entries': [
          for (final entry in vault.value.entries.entries)
            entry.value.toPlatformMap(entry.key),
        ],
      },
  ],
};
