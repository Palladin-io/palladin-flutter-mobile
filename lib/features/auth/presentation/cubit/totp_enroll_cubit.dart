import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../data/datasources/password_auth_remote_datasource.dart';
import '../../domain/password_auth_exceptions.dart';
import 'totp_enroll_state.dart';

export 'totp_enroll_state.dart';

/// Drives TOTP enrollment (CVT-274).
///
/// On mount [enroll] fetches a pending secret + otpauth URI; the user
/// scans / types it into an authenticator app, then [confirm]s a generated
/// code to enable TOTP and receive the one-time recovery codes.
class TotpEnrollCubit extends Cubit<TotpEnrollState> {
  TotpEnrollCubit({required this.datasource})
      : super(const TotpEnrollLoading());

  final PasswordAuthRemoteDatasource datasource;

  /// Requests the pending TOTP secret. Call once on page mount.
  Future<void> enroll() async {
    AppLogger.d('TotpEnroll', 'Requesting secret');
    emit(const TotpEnrollLoading());
    try {
      final model = await datasource.totpEnroll();
      emit(TotpEnrollReady(secret: model.secret, otpauthUri: model.otpauthUri));
    } on PasswordAuthServerException catch (e) {
      AppLogger.w('TotpEnroll', 'Enroll failed: ${e.kind.name}');
      emit(TotpEnrollLoadFailed(e));
    }
  }

  /// Confirms the pending secret with a generated [code]. On success emits
  /// [TotpEnrollConfirmed] with the recovery codes.
  Future<void> confirm(String code) async {
    final current = state;
    if (current is! TotpEnrollReady || code.isEmpty) return;
    AppLogger.d('TotpEnroll', 'Confirming code');
    emit(current.copyWith(confirming: true, clearError: true));

    try {
      final recoveryCodes = await datasource.totpConfirm(code);
      AppLogger.i('TotpEnroll', 'TOTP enabled');
      emit(TotpEnrollConfirmed(recoveryCodes));
    } on TotpInvalidException catch (e) {
      AppLogger.w('TotpEnroll', 'Confirmation code rejected');
      emit(current.copyWith(confirming: false, error: e));
    } on PasswordAuthServerException catch (e) {
      AppLogger.w('TotpEnroll', 'Confirm failed: ${e.kind.name}');
      emit(current.copyWith(confirming: false, error: e));
    }
  }
}
