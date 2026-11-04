import '../../../config/env_config.dart';
import '../../../core/crypto/biometric_profile_binding.dart';
import '../../unlock/data/datasources/account_remote_datasource.dart';
import '../../vault/data/services/member_sync_session_authority_provider.dart';
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

  Future<AutoFillSourceConfiguration> load() async {
    final captured = await _authorityProvider.captureForPreparation();
    final account = await _accountDatasource.getUnlockAccount();
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
      validateCurrent: captured.validateCurrent,
    );
  }
}
