import 'package:flutter/services.dart';

import '../../config/env_config.dart';
import '../../features/unlock/data/models/account_response.dart';
import '../../features/unlock/data/services/identity_kdf_service.dart';
import '../../features/vault/data/services/member_sync_session_authority_provider.dart';
import '../crypto/biometric_profile_binding.dart';

final class ProtectedAccountUnlockUnavailable implements Exception {
  const ProtectedAccountUnlockUnavailable();
}

/// Reads the native integrity-protected ACTIVE source configuration, never the
/// shared SQLite wrapper as its own authority. No source-session bootstrap is
/// needed here, so offline bootstrap cannot recurse through itself.
final class ProtectedAccountUnlockReader {
  const ProtectedAccountUnlockReader({
    required MemberSyncSessionAuthorityProvider authority,
    required EnvConfig config,
    MethodChannel channel = const MethodChannel(
      'io.palladin.mobile/autofill-request',
    ),
  }) : _authority = authority,
       _config = config,
       _channel = channel;

  final MemberSyncSessionAuthorityProvider _authority;
  final EnvConfig _config;
  final MethodChannel _channel;

  Future<AccountResponse> read() async {
    final captured = await _authority.captureForPreparation();
    final claims = captured.claims;
    if (claims.offlinePolicy == 'disabled') {
      throw const ProtectedAccountUnlockUnavailable();
    }
    final expected = <String, Object>{
      'profileBinding': biometricProfileBinding(
        flavor: _config.flavor,
        apiBaseUrl: _config.apiBaseUrl,
        principalId: claims.principalId,
      ),
      'principalId': claims.principalId,
      'organizationId': claims.organizationId,
      'organizationMembershipGeneration':
          claims.organizationMembershipGeneration,
      'offlinePolicy': claims.offlinePolicy,
      'offlinePolicyVersion': claims.offlinePolicyVersion,
    };
    final record = await _channel.invokeMapMethod<Object?, Object?>(
      'sourceConfiguration',
      expected,
    );
    captured.validateCurrent();
    if (record == null ||
        expected.entries.any((entry) => record[entry.key] != entry.value)) {
      throw const ProtectedAccountUnlockUnavailable();
    }
    final material = record['accountUnlock'];
    if (material is! Map || material['accountId'] != claims.principalId) {
      throw const ProtectedAccountUnlockUnavailable();
    }
    final ciphertext = material['encryptedPrivateKey'];
    final kdf = material['kdf'];
    if (ciphertext is! String || ciphertext.isEmpty || kdf is! Map) {
      throw const ProtectedAccountUnlockUnavailable();
    }
    try {
      return AccountResponse(
        userId: claims.principalId,
        encryptedPrivateKey: ciphertext,
        kdf: IdentityKdfMetadata.fromJson(Map<String, dynamic>.from(kdf)),
      );
    } on TypeError {
      throw const ProtectedAccountUnlockUnavailable();
    }
  }
}
