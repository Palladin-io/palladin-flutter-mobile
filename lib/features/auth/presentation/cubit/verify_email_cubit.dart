import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../onboarding/data/services/default_vault_provisioner.dart';
import '../../data/datasources/password_auth_remote_datasource.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/password_auth_exceptions.dart';
import 'verify_email_state.dart';

export 'verify_email_state.dart';

/// Drives the email-verification screen.
///
/// Two modes, one cubit:
///   * **result** — a token arrived (deep link `palladin://verify-email?token=…`
///     or the `?token=` query). [verify] POSTs it and maps the outcome to
///     verified / expired / invalid.
///   * **gate** — no token: an authenticated-but-unverified user sees a
///     "verify your email" prompt with a throttled [resend] action.
///
/// The verify endpoint is anonymous, so it works on a cold start even
/// before the session is restored.
class VerifyEmailCubit extends Cubit<VerifyEmailState> {
  VerifyEmailCubit({
    required this.datasource,
    required this.authRepository,
    required this.defaultVaultProvisioner,
  }) : super(const VerifyEmailState());

  final PasswordAuthRemoteDatasource datasource;
  final AuthRepository authRepository;
  final DefaultVaultProvisioner defaultVaultProvisioner;

  /// Verifies [token]. Emits verified / expired / invalid / serverError.
  Future<void> verify(String token) async {
    if (token.isEmpty) return;
    AppLogger.d('VerifyEmail', 'Verifying token');
    emit(
      state.copyWith(
        verification: VerificationStatus.verifying,
        clearServerError: true,
      ),
    );

    try {
      await datasource.verifyEmail(token);
      AppLogger.i('VerifyEmail', 'Email verified');
      emit(state.copyWith(verification: VerificationStatus.verified));
    } on VerificationTokenException catch (e) {
      AppLogger.w('VerifyEmail', 'Token rejected: ${e.kind.name}');
      emit(
        state.copyWith(
          verification: e.kind == VerificationTokenErrorKind.expired
              ? VerificationStatus.expired
              : VerificationStatus.invalid,
        ),
      );
    } on PasswordAuthServerException catch (e) {
      AppLogger.w('VerifyEmail', 'Verify failed: ${e.kind.name}');
      emit(
        state.copyWith(
          verification: VerificationStatus.serverError,
          serverErrorKind: e.kind,
        ),
      );
    }
  }

  /// Re-sends the verification email (JWT). Throttling is enforced
  /// server-side; a rejected resend surfaces as [ResendStatus.error].
  Future<void> resend() async {
    if (state.resend == ResendStatus.sending) return;
    AppLogger.d('VerifyEmail', 'Resending verification email');
    emit(state.copyWith(resend: ResendStatus.sending));

    try {
      await datasource.resendVerification();
      AppLogger.i('VerifyEmail', 'Verification email resent');
      emit(state.copyWith(resend: ResendStatus.sent));
    } on PasswordAuthServerException catch (e) {
      AppLogger.w('VerifyEmail', 'Resend failed: ${e.kind.name}');
      emit(state.copyWith(resend: ResendStatus.error));
    }
  }

  /// Refreshes the session and reads the server-issued verification claim.
  /// A network failure leaves the current authenticated session untouched.
  Future<void> checkAgain({
    required Uint8List? privateKey,
    required String defaultVaultName,
  }) async {
    if (state.check == VerificationCheckStatus.checking) return;
    AppLogger.d('VerifyEmail', 'Checking verification status');
    emit(state.copyWith(check: VerificationCheckStatus.checking));

    try {
      await authRepository.refreshToken();
      final verified = await authRepository.isEmailVerified();
      if (verified && privateKey != null) {
        await defaultVaultProvisioner.ensureFromPrivateKey(
          privateKey: privateKey,
          name: defaultVaultName,
        );
      }
      emit(
        state.copyWith(
          check: verified
              ? VerificationCheckStatus.verified
              : VerificationCheckStatus.pending,
        ),
      );
    } catch (e) {
      AppLogger.w(
        'VerifyEmail',
        'Verification status check failed: ${e.runtimeType}',
      );
      emit(state.copyWith(check: VerificationCheckStatus.error));
    }
  }
}
