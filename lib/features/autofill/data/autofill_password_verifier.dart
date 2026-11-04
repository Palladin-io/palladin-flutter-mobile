import '../../unlock/data/datasources/account_remote_datasource.dart';
import '../../unlock/data/services/unlock_crypto_service.dart';
import '../../vault/data/services/member_sync_session_authority_provider.dart';
import 'autofill_request_controller.dart';

/// Fresh per-request authorization for an already unlocked app. Reuses Identity
/// crypto without provisioning, changing app keys, or enrolling biometrics.
final class AutoFillPasswordVerifier {
  const AutoFillPasswordVerifier({
    required AccountRemoteDatasource account,
    required UnlockCryptoService crypto,
    required MemberSyncSessionAuthorityProvider authority,
    required Future<void> Function() Function() captureAuthorization,
  }) : _account = account,
       _crypto = crypto,
       _authority = authority,
       _captureAuthorization = captureAuthorization;
  final AccountRemoteDatasource _account;
  final UnlockCryptoService _crypto;
  final MemberSyncSessionAuthorityProvider _authority;
  final Future<void> Function() Function() _captureAuthorization;

  Future<void> verify(String password) async {
    final authorize = _captureAuthorization();
    final authority = await _authority.captureForPreparation();
    final account = await _account.getUnlockAccount();
    authority.validateCurrent();
    final kdf = account.kdf;
    final ciphertext = account.encryptedPrivateKey;
    if (password.isEmpty ||
        account.userId != authority.claims.principalId ||
        kdf == null ||
        ciphertext == null) {
      throw const AutoFillRequestInvalidated();
    }
    UnlockResult? result;
    try {
      result = await _crypto.deriveAndDecrypt(
        masterPassword: password,
        accountId: account.userId,
        kdf: kdf,
        encryptedPrivateKeyBase64: ciphertext,
      );
      authority.validateCurrent();
      await authorize();
    } finally {
      result?.masterKey.fillRange(0, result.masterKey.length, 0);
      result?.privateKey.fillRange(0, result.privateKey.length, 0);
    }
  }
}
