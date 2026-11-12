import '../../../config/env_config.dart';
import '../../../core/crypto/biometric_profile_binding.dart';
import '../../unlock/data/datasources/account_remote_datasource.dart';
import '../../vault/data/services/member_sync_session_authority_provider.dart';
import '../../vault/data/services/member_sync_service.dart';
import 'autofill_source_access_service.dart';

enum AutoFillSourceConfigurationFailure {
  accountMismatch,
  missingUnlockMaterial,
}

class AutoFillSourceConfigurationException implements Exception {
  const AutoFillSourceConfigurationException(this.kind);
  final AutoFillSourceConfigurationFailure kind;
}

/// Builds the native provider's unlock projection from authenticated account
/// material. Token authority is independent of the account response and stays
/// fenced until the source owner acknowledges native publication.
final class AutoFillSourceConfigurationLoader {
  const AutoFillSourceConfigurationLoader({
    required MemberSyncSessionAuthorityProvider authorityProvider,
    required AccountRemoteDatasource accountDatasource,
    required EnvConfig config,
  }) : _authorityProvider = authorityProvider,
       _accountDatasource = accountDatasource,
       _config = config;

  final MemberSyncSessionAuthorityProvider _authorityProvider;
  final AccountRemoteDatasource _accountDatasource;
  final EnvConfig _config;

  Future<AutoFillSourceConfiguration> load() => _load(allowRefresh: true);

  Future<AutoFillSourceConfiguration> _load({
    required bool allowRefresh,
  }) async {
    final lifecycle = _authorityProvider.lifecycleRevision;
    final captured = await _authorityProvider.captureForPreparation();
    void validateLifecycle() {
      if (_authorityProvider.lifecycleRevision != lifecycle) {
        throw StateError('Source account lifecycle changed');
      }
    }

    validateLifecycle();
    final account = await _accountDatasource.getUnlockAccount();
    validateLifecycle();
    if (captured.sessionRevision != _authorityProvider.sessionRevision &&
        allowRefresh) {
      final refreshed = await _authorityProvider.captureForPreparation();
      validateLifecycle();
      void validateScope(MemberSyncSessionAuthority after) {
        final before = captured.claims;
        if (before.principalId != after.principalId ||
            before.organizationId != after.organizationId ||
            before.organizationMembershipGeneration !=
                after.organizationMembershipGeneration ||
            before.offlinePolicy != after.offlinePolicy ||
            before.offlinePolicyVersion != after.offlinePolicyVersion) {
          throw StateError('Source account authority changed');
        }
      }

      validateScope(refreshed.claims);
      // The account request may itself refresh an expired token. Discard that
      // response and fetch once under fresh authority; never retry OS consent.
      final reloaded = await _load(allowRefresh: false);
      validateLifecycle();
      reloaded.validateCurrent();
      validateScope(reloaded.authority);
      return reloaded;
    }
    captured.validateCurrent();
    if (account.userId != captured.claims.principalId) {
      throw const AutoFillSourceConfigurationException(
        AutoFillSourceConfigurationFailure.accountMismatch,
      );
    }
    final kdf = account.kdf;
    final encryptedPrivateKey = account.encryptedPrivateKey;
    if (kdf == null || encryptedPrivateKey == null) {
      throw const AutoFillSourceConfigurationException(
        AutoFillSourceConfigurationFailure.missingUnlockMaterial,
      );
    }
    return AutoFillSourceConfiguration(
      authority: captured.claims,
      profileBinding: biometricProfileBinding(
        flavor: _config.flavor,
        apiBaseUrl: _config.apiBaseUrl,
        principalId: captured.claims.principalId,
      ),
      accountUnlock: Map.unmodifiable({
        'accountId': account.userId,
        'encryptedPrivateKey': encryptedPrivateKey,
        'kdf': Map<String, Object?>.unmodifiable({
          'securityVersion': kdf.securityVersion,
          'minimumSecurityVersion': kdf.minimumSecurityVersion,
          'profileId': kdf.profileId,
          'kdfSalt': kdf.kdfSalt,
          'credentialRevision': kdf.credentialRevision,
          'privateKeyWrapRevision': kdf.privateKeyWrapRevision,
          if (kdf.deviceWrapperMetadata != null)
            'deviceWrapperMetadata': kdf.deviceWrapperMetadata,
        }),
      }),
      validateCurrent: () {
        validateLifecycle();
        captured.validateCurrent();
      },
    );
  }
}
