/// Independent current-Entry authority carried by the authenticated cache
/// manifest and checked against each credential record by native providers.
final class AutoFillEntryAuthority {
  const AutoFillEntryAuthority({
    required this.revision,
    required this.keyVersion,
  });

  final String revision;
  final int keyVersion;

  Map<String, Object> toPlatformMap(String entryId) {
    if (entryId.isEmpty || revision.isEmpty || keyVersion < 1) {
      throw const FormatException('Invalid AutoFill Entry authority');
    }
    return {'entryId': entryId, 'revision': revision, 'keyVersion': keyVersion};
  }
}

/// Authenticated lease and high-water authority for one Vault.
final class AutoFillVaultAuthority {
  const AutoFillVaultAuthority({
    required this.contextVersion,
    required this.memberId,
    required this.memberKeyGeneration,
    required this.vaultKeyVersion,
    required this.memberRecipientKeyVersion,
    required this.memberRecipientKeyFingerprint,
    required this.issuedAt,
    required this.notAfter,
    required this.entries,
  });

  final int contextVersion;
  final String memberId;
  final int memberKeyGeneration;
  final int vaultKeyVersion;
  final int memberRecipientKeyVersion;
  final String memberRecipientKeyFingerprint;
  final DateTime issuedAt;
  final DateTime notAfter;
  final Map<String, AutoFillEntryAuthority> entries;

  Map<String, Object> toPlatformMap(String vaultId) {
    if (vaultId.isEmpty ||
        contextVersion != 1 ||
        memberId.isEmpty ||
        memberKeyGeneration < 1 ||
        vaultKeyVersion < 1 ||
        memberRecipientKeyVersion < 1 ||
        memberRecipientKeyFingerprint.isEmpty ||
        !issuedAt.isBefore(notAfter) ||
        entries.isEmpty) {
      throw const FormatException('Invalid AutoFill Vault authority');
    }
    final sortedEntries = entries.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return {
      'vaultId': vaultId,
      'contextVersion': contextVersion,
      'memberId': memberId,
      'memberKeyGeneration': memberKeyGeneration,
      'vaultKeyVersion': vaultKeyVersion,
      'memberRecipientKeyVersion': memberRecipientKeyVersion,
      'memberRecipientKeyFingerprint': memberRecipientKeyFingerprint,
      'issuedAt': issuedAt.toUtc().toIso8601String(),
      'notAfter': notAfter.toUtc().toIso8601String(),
      'entries': sortedEntries
          .map((entry) => entry.value.toPlatformMap(entry.key))
          .toList(growable: false),
    };
  }
}

/// Profile-scoped authority stored separately from credential records inside
/// the native authenticated ciphertext.
final class AutoFillCacheManifest {
  const AutoFillCacheManifest({
    required this.principalId,
    required this.organizationId,
    required this.organizationMembershipGeneration,
    required this.offlinePolicy,
    required this.offlinePolicyVersion,
    required this.vaults,
  });

  final String principalId;
  final String organizationId;
  final String organizationMembershipGeneration;
  final String offlinePolicy;
  final int offlinePolicyVersion;
  final Map<String, AutoFillVaultAuthority> vaults;

  Map<String, Object> toPlatformMap() {
    if (principalId.isEmpty ||
        organizationId.isEmpty ||
        !_decimal.hasMatch(organizationMembershipGeneration) ||
        !const {'1h', '4h', '24h'}.contains(offlinePolicy) ||
        offlinePolicyVersion < 1 ||
        vaults.isEmpty) {
      throw const FormatException('Invalid AutoFill cache manifest');
    }
    final sortedVaults = vaults.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return {
      'principalId': principalId,
      'organizationId': organizationId,
      'organizationMembershipGeneration': organizationMembershipGeneration,
      'offlinePolicy': offlinePolicy,
      'offlinePolicyVersion': offlinePolicyVersion,
      'vaults': sortedVaults
          .map((entry) => entry.value.toPlatformMap(entry.key))
          .toList(growable: false),
    };
  }

  static final RegExp _decimal = RegExp(r'^(?:0|[1-9][0-9]*)$');
}

/// One wipe-lifetime credential projection bound to the cache manifest.
final class AutoFillRecord {
  const AutoFillRecord({
    required this.id,
    required this.organizationId,
    required this.vaultId,
    required this.revision,
    required this.keyVersion,
    required this.label,
    required this.username,
    required this.password,
    required this.domains,
  });

  final String id;
  final String organizationId;
  final String vaultId;
  final String revision;
  final int keyVersion;
  final String label;
  final String username;
  final String password;
  final List<String> domains;

  Map<String, Object> toPlatformMap() => {
    'id': id,
    'organizationId': organizationId,
    'vaultId': vaultId,
    'revision': revision,
    'keyVersion': keyVersion,
    'label': label,
    'username': username,
    'password': password,
    'domains': domains,
  };
}

/// Versioned native cache payload. Record bindings are checked against the
/// independently serialized manifest before crossing the platform boundary.
final class AutoFillCachePayload {
  const AutoFillCachePayload({required this.manifest, required this.records});

  static const version = 2;

  final AutoFillCacheManifest manifest;
  final List<AutoFillRecord> records;

  Map<String, Object> toPlatformMap() {
    final seen = <String>{};
    for (final record in records) {
      final vault = manifest.vaults[record.vaultId];
      final authority = vault?.entries[record.id];
      final identity = '${record.vaultId}:${record.id}';
      if (record.organizationId != manifest.organizationId ||
          vault == null ||
          authority == null ||
          authority.revision != record.revision ||
          authority.keyVersion != record.keyVersion ||
          record.label.isEmpty ||
          record.password.isEmpty ||
          record.domains.isEmpty ||
          !seen.add(identity)) {
        throw const FormatException('AutoFill record authority mismatch');
      }
    }
    return {
      'version': version,
      'manifest': manifest.toPlatformMap(),
      'records': records
          .map((record) => record.toPlatformMap())
          .toList(growable: false),
    };
  }
}
