import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../data/datasources/recovery_remote_datasource.dart';
import '../../data/services/recovery_crypto_service.dart';
import '../../domain/recovery_exceptions.dart';
import 'recovery_state.dart';

export 'recovery_state.dart';

/// Drives the account-recovery wizard.
///
/// The cubit exposes two entry points that map 1:1 to wizard steps:
///
///   * [validateAndProceed] — called after the user enters their 24-word
///     mnemonic. Fetches `GET /api/account`, derives the recovery key,
///     and tries to open `encryptedPrivateKeyByRecovery`. On success the
///     mnemonic is retained in [RecoveryKeyValidated] so step 2 can
///     re-use it without re-prompting.
///
///   * [completeRecovery] — called after the user sets a new master
///     password. Re-runs the full crypto pipeline (unwrap → re-wrap with
///     new MK → re-wrap with a fresh RK + mnemonic) and submits the
///     bundle to `PUT /api/account/recovery`.
///
/// Failures surface as [RecoveryFailed] carrying typed exceptions so the
/// presentation layer can choose the correct localized message.
class RecoveryCubit extends Cubit<RecoveryState> {
  RecoveryCubit({
    required this.datasource,
    required this.cryptoService,
  }) : super(const RecoveryInitial());

  final RecoveryRemoteDatasource datasource;
  final RecoveryCryptoService cryptoService;

  /// Validates the user-supplied recovery mnemonic.
  ///
  /// On success emits [RecoveryKeyValidated]; the UI advances to the
  /// "choose new password" step. On failure emits [RecoveryFailed] with
  /// one of [WrongRecoveryKeyException], [RecoveryMaterialMissingException],
  /// or [RecoveryServerException].
  Future<void> validateAndProceed(String mnemonic) async {
    final trimmed = mnemonic.trim();
    if (trimmed.isEmpty) return;
    AppLogger.d('Recovery', 'Validating recovery mnemonic');
    emit(const RecoveryLoading());

    try {
      final account = await datasource.getAccount();
      final recoverySalt = account.recoverySalt;
      final encryptedByRecovery = account.encryptedPrivateKeyByRecovery;
      if (recoverySalt == null || encryptedByRecovery == null) {
        AppLogger.w('Recovery', 'Account missing recovery material');
        emit(const RecoveryFailed(RecoveryMaterialMissingException()));
        return;
      }

      // Cheaper than the full pipeline — we just need to verify the
      // mnemonic unwraps the private key. The real pipeline runs in
      // [completeRecovery] once the user has chosen a new master
      // password.
      await cryptoService.validateRecoveryMnemonic(
        recoveryMnemonic: trimmed,
        recoverySaltBase64: recoverySalt,
        encryptedPrivateKeyByRecoveryBase64: encryptedByRecovery,
      );

      AppLogger.i('Recovery', 'Recovery mnemonic validated');
      emit(RecoveryKeyValidated(validatedMnemonic: trimmed));
    } on WrongRecoveryKeyException catch (e) {
      AppLogger.w('Recovery', 'Wrong recovery mnemonic');
      emit(RecoveryFailed(e));
    } on RecoveryMaterialMissingException catch (e) {
      emit(RecoveryFailed(e));
    } on DioException catch (e, s) {
      AppLogger.e('Recovery', 'Account fetch failed', error: e, stackTrace: s);
      emit(RecoveryFailed(RecoveryServerException(_classifyDioError(e))));
    } catch (e, s) {
      AppLogger.e('Recovery', 'Validation failed', error: e, stackTrace: s);
      emit(RecoveryFailed(e));
    }
  }

  /// Runs the full recovery pipeline.
  ///
  /// Requires the cubit to be in [RecoveryKeyValidated] so the already-
  /// validated mnemonic is available. On success emits [RecoveryCompleted]
  /// with the freshly generated 24-word mnemonic for the user to back up.
  Future<void> completeRecovery(String newPassword) async {
    final current = state;
    if (current is! RecoveryKeyValidated) {
      AppLogger.w('Recovery', 'completeRecovery called without validated key');
      return;
    }
    if (newPassword.isEmpty) return;

    AppLogger.d('Recovery', 'Executing full recovery pipeline');
    emit(const RecoveryLoading());

    try {
      final account = await datasource.getAccount();
      final recoverySalt = account.recoverySalt;
      final encryptedByRecovery = account.encryptedPrivateKeyByRecovery;
      if (recoverySalt == null || encryptedByRecovery == null) {
        emit(const RecoveryFailed(RecoveryMaterialMissingException()));
        return;
      }

      final result = await cryptoService.recoverAccount(
        recoveryMnemonic: current.validatedMnemonic,
        newPassword: newPassword,
        recoverySaltBase64: recoverySalt,
        encryptedPrivateKeyByRecoveryBase64: encryptedByRecovery,
      );

      await datasource.recoverAccount(result.request);

      AppLogger.i('Recovery', 'Account recovery completed');
      emit(RecoveryCompleted(
        newRecoveryMnemonic: result.newRecoveryMnemonic,
      ));
    } on WrongRecoveryKeyException catch (e) {
      // The mnemonic was validated in step 1 but the server rotated the
      // ciphertext between steps — very unlikely but surface the same
      // error so the user can restart from the top.
      AppLogger.w('Recovery', 'Mnemonic no longer valid at completion');
      emit(RecoveryFailed(e));
    } on DioException catch (e, s) {
      AppLogger.e('Recovery', 'Recovery request failed',
          error: e, stackTrace: s);
      emit(RecoveryFailed(RecoveryServerException(_classifyDioError(e))));
    } catch (e, s) {
      AppLogger.e('Recovery', 'Recovery failed', error: e, stackTrace: s);
      emit(RecoveryFailed(e));
    }
  }

  /// Maps a [DioException] to a typed [RecoveryServerErrorKind] so the
  /// UI can resolve the correct localized message.
  RecoveryServerErrorKind _classifyDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return RecoveryServerErrorKind.serverNotResponding;
    }
    if (e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return RecoveryServerErrorKind.cannotConnect;
    }
    if (e.type == DioExceptionType.badResponse) {
      return RecoveryServerErrorKind.invalidResponse;
    }
    return RecoveryServerErrorKind.connectionFailed;
  }

  /// Drops any transient error / loading state back to [RecoveryInitial].
  ///
  /// Called when the user navigates backwards in the wizard so a stale
  /// server-error banner doesn't linger over the freshly-shown step.
  void reset() {
    if (state is RecoveryInitial) return;
    emit(const RecoveryInitial());
  }
}
