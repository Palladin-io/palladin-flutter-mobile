import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/biometric_key_store.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../unlock/data/datasources/account_remote_datasource.dart';
import '../../../unlock/data/services/identity_kdf_service.dart';
import '../../data/datasources/password_auth_remote_datasource.dart';
import '../../data/services/password_auth_crypto_service.dart';
import 'change_password_state.dart';

export 'change_password_state.dart';

/// Drives the change-master-password flow (CVT-273).
///
/// Fetches the current account material, uses the **current** password to
/// unwrap the private key (proving knowledge of the old password), then
/// re-derives a fresh `authHash` and master key from the **new** password
/// and re-wraps the private key. The recovery mnemonic is left untouched.
///
/// Because the master key changes, any biometric-unlock enrollment (which
/// stashed the old master key) is cleared — it could no longer decrypt the
/// new ciphertext. The next password unlock re-enrolls it.
class ChangePasswordCubit extends Cubit<ChangePasswordState> {
  ChangePasswordCubit({
    required this.accountDatasource,
    required this.datasource,
    required this.cryptoService,
    required this.keyStore,
  }) : super(const ChangePasswordInitial());

  final AccountRemoteDatasource accountDatasource;
  final PasswordAuthRemoteDatasource datasource;
  final PasswordAuthCryptoService cryptoService;
  final BiometricKeyStore keyStore;

  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (email.isEmpty || currentPassword.isEmpty || newPassword.isEmpty) return;
    AppLogger.d('ChangePassword', 'Change requested');
    emit(const ChangePasswordLoading());

    ChangePasswordMaterial? material;
    try {
      // The current auth salt lives server-side; fetch it (anonymous
      // pre-check) so we can derive the current auth hash the server
      // verifies. The account material carries the current encryption salt
      // + wrapped private key.
      final account = await accountDatasource.getAccount();
      final kdf = account.kdf;
      if (kdf == null) {
        throw const UnsupportedIdentityKdfException('missing-kdf-metadata');
      }
      // Throws ChangePasswordWrongCurrentException if the current password
      // can't unwrap the private key (client-side proof before the server's).
      material = await cryptoService.buildChangePasswordMaterial(
        currentPassword: currentPassword,
        newPassword: newPassword,
        accountId: account.userId,
        currentKdfSaltBase64: kdf.kdfSalt,
        currentEncryptedPrivateKeyBase64: account.encryptedPrivateKey,
      );

      await datasource.changePassword(
        baseCredentialRevision: kdf.credentialRevision,
        basePrivateKeyWrapRevision: kdf.privateKeyWrapRevision,
        currentAuthCredential: material.currentAuthCredential,
        newAuthCredential: material.newAuthCredential,
        newKdfSalt: material.kdfSalt,
        newEncryptedPrivateKey: material.encryptedPrivateKey,
      );

      // The stashed biometric master key is now stale — drop it so a
      // biometric unlock can't try to decrypt the new ciphertext with the
      // old key. Best-effort; never blocks the change.
      try {
        await keyStore.clear();
      } catch (e) {
        AppLogger.w(
          'ChangePassword',
          'Biometric clear skipped: ${e.runtimeType}',
        );
      }

      AppLogger.i('ChangePassword', 'Master password changed');
      emit(
        ChangePasswordSuccess(
          masterKey: material.masterKey,
          privateKey: material.privateKey,
        ),
      );
    } catch (e) {
      // Zero any derived key material that never reached the live session.
      if (material != null) {
        material.masterKey.fillRange(0, material.masterKey.length, 0);
        material.privateKey.fillRange(0, material.privateKey.length, 0);
      }
      AppLogger.w('ChangePassword', 'Change failed: ${e.runtimeType}');
      emit(ChangePasswordFailure(e));
    }
  }
}
