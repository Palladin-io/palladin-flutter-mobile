import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../unlock/data/datasources/account_remote_datasource.dart';
import '../../../unlock/data/services/identity_kdf_service.dart';
import '../../data/datasources/password_auth_remote_datasource.dart';
import '../../data/services/password_auth_crypto_service.dart';
import '../../domain/password_auth_exceptions.dart';
import 'totp_enroll_state.dart';

export 'totp_enroll_state.dart';

/// Drives TOTP enrollment.
///
/// The user first re-enters the login password; [enroll] derives the
/// current auth credential (as for a password change) and requests a pending
/// secret + otpauth URI. The user then [confirm]s a generated code to enable
/// TOTP and receive the one-time recovery codes. The credential stays in
/// memory only between those two requests and is wiped afterwards.
class TotpEnrollCubit extends Cubit<TotpEnrollState> {
  TotpEnrollCubit({
    required this.datasource,
    required this.accountDatasource,
    required this.cryptoService,
  }) : super(const TotpEnrollPasswordRequired());

  final PasswordAuthRemoteDatasource datasource;
  final AccountRemoteDatasource accountDatasource;
  final PasswordAuthCryptoService cryptoService;

  Uint8List? _credential;

  /// Proves the login [password] and requests the pending TOTP secret.
  Future<void> enroll(String password) async {
    if (password.isEmpty || state is! TotpEnrollPasswordRequired) return;
    AppLogger.d('TotpEnroll', 'Requesting secret');
    emit(const TotpEnrollPasswordRequired(verifying: true));
    _wipeCredential();
    try {
      final account = await accountDatasource.getAccount();
      final kdf = account.kdf;
      if (kdf == null) {
        throw const UnsupportedIdentityKdfException('missing-kdf-metadata');
      }
      final credential = _credential = await cryptoService
          .deriveCurrentAuthCredential(
            password: password,
            accountId: account.userId,
            kdfSaltBase64: kdf.kdfSalt,
          );
      final model = await datasource.totpEnroll(credential);
      emit(TotpEnrollReady(secret: model.secret, otpauthUri: model.otpauthUri));
    } on TotpUnavailableException {
      _wipeCredential();
      emit(const TotpEnrollUnavailable());
    } catch (e) {
      _wipeCredential();
      AppLogger.w('TotpEnroll', 'Enroll failed: ${e.runtimeType}');
      emit(TotpEnrollPasswordRequired(error: e));
    }
  }

  /// Confirms the pending secret with a generated [code]. On success emits
  /// [TotpEnrollConfirmed] with the recovery codes.
  Future<void> confirm(String code) async {
    final current = state;
    final credential = _credential;
    if (current is! TotpEnrollReady || code.isEmpty || credential == null) {
      return;
    }
    AppLogger.d('TotpEnroll', 'Confirming code');
    emit(current.copyWith(confirming: true, clearError: true));

    try {
      final recoveryCodes = await datasource.totpConfirm(code, credential);
      _wipeCredential();
      AppLogger.i('TotpEnroll', 'TOTP enabled');
      emit(TotpEnrollConfirmed(recoveryCodes));
    } on TotpInvalidException catch (e) {
      AppLogger.w('TotpEnroll', 'Confirmation code rejected');
      emit(current.copyWith(confirming: false, error: e));
    } on TotpUnavailableException {
      _wipeCredential();
      emit(const TotpEnrollUnavailable());
    } on TotpCurrentCredentialException catch (e) {
      // The password changed since enrollment began; start over.
      _wipeCredential();
      emit(TotpEnrollPasswordRequired(error: e));
    } on PasswordAuthServerException catch (e) {
      AppLogger.w('TotpEnroll', 'Confirm failed: ${e.kind.name}');
      emit(current.copyWith(confirming: false, error: e));
    }
  }

  void _wipeCredential() {
    if (_credential case final credential?) {
      credential.fillRange(0, credential.length, 0);
    }
    _credential = null;
  }

  @override
  Future<void> close() {
    _wipeCredential();
    return super.close();
  }
}
