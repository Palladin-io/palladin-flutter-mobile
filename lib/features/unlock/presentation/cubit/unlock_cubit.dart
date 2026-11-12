import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/biometric_key_store.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../onboarding/data/services/default_vault_provisioner.dart';
import '../../data/datasources/account_remote_datasource.dart';
import '../../data/models/account_response.dart';
import '../../data/services/identity_kdf_service.dart';
import '../../data/services/unlock_crypto_service.dart';
import '../../domain/unlock_exceptions.dart';
import 'unlock_state.dart';

export 'unlock_state.dart';

/// Drives the master-password unlock screen.
///
/// Password flow (primary):
/// 1. `GET /api/account` — fetch salt + encrypted private key.
/// 2. Run Argon2id to derive MK, open `crypto_secretbox_easy` to
///    recover the private key.
/// 3. Transfer keys to the authenticated session without an enrollment prompt.
///
/// Biometric flow (shortcut):
/// 1. [BiometricKeyStore.unlockKey] triggers the OS biometric prompt; the
///    OS releases the MK only on a successful authentication.
/// 2. Decrypt the private key with the recovered MK (fresh
///    `GET /api/account` each time so key rotations propagate).
///
/// Biometric enrollment is optional, so a device without
/// biometrics — or any protected-storage failure — leaves password unlock fully working.
class UnlockCubit extends Cubit<UnlockState> {
  UnlockCubit({
    required this.datasource,
    required this.cryptoService,
    required this.keyStore,
    required this.defaultVaultProvisioner,
    this.captureRequestAuthorization,
  }) : super(const UnlockInitial());

  final AccountRemoteDatasource datasource;
  final UnlockCryptoService cryptoService;
  final BiometricKeyStore keyStore;
  final DefaultVaultProvisioner defaultVaultProvisioner;
  final FutureOr<Future<void> Function()?> Function()?
  captureRequestAuthorization;

  /// Runs the master-password unlock pipeline.
  ///
  /// Biometric enrollment is a separate explicit action after unlock.
  Future<void> unlock(String password, {String? defaultVaultName}) async {
    if (password.isEmpty || isClosed || state is UnlockLoading) return;
    final generation = keyStore.generation;
    bool canceled() => isClosed || generation != keyStore.generation;
    AppLogger.d('Unlock', 'Password unlock requested');
    emit(const UnlockLoading());

    UnlockResult? result;
    var keysHandedOff = false;
    try {
      final authorizeRequest = await captureRequestAuthorization?.call();
      if (canceled()) return;
      final account = await datasource.getUnlockAccount();
      if (canceled()) return;
      final kdf = account.kdf;
      final encryptedPrivateKey = account.encryptedPrivateKey;
      if (kdf == null || encryptedPrivateKey == null) {
        throw UnsupportedIdentityKdfException('missing-account-key-material');
      }
      result = await cryptoService.deriveAndDecrypt(
        masterPassword: password,
        accountId: account.userId,
        kdf: kdf,
        encryptedPrivateKeyBase64: encryptedPrivateKey,
      );

      if (canceled()) return;
      await keyStore.purgeLegacyRawKey();
      if (canceled()) return;

      await _provisionDefaultVault(
        privateKey: result.privateKey,
        name: defaultVaultName,
      );

      if (canceled()) return;
      await authorizeRequest?.call();
      if (canceled()) return;
      AppLogger.i('Unlock', 'Password unlock succeeded');
      emit(
        UnlockSuccess(
          masterKey: result.masterKey,
          privateKey: result.privateKey,
        ),
      );
      keysHandedOff = true;
    } on WrongMasterPasswordException catch (e) {
      AppLogger.w('Unlock', 'Wrong master password');
      if (!isClosed) emit(UnlockFailed(e));
    } on DioException catch (e, s) {
      if (e.response?.statusCode == 401) {
        AppLogger.w('Unlock', 'Session expired — routing to sign-in');
        emit(const UnlockFailed(SessionExpiredException()));
        return;
      }
      AppLogger.e('Unlock', 'Unlock failed', error: e, stackTrace: s);
      if (!isClosed) emit(UnlockFailed(e));
    } catch (e, s) {
      AppLogger.e('Unlock', 'Unlock failed', error: e, stackTrace: s);
      if (!isClosed) emit(UnlockFailed(e));
    } finally {
      if (!keysHandedOff && result != null) {
        result.masterKey.fillRange(0, result.masterKey.length, 0);
        result.privateKey.fillRange(0, result.privateKey.length, 0);
      }
    }
  }

  /// Attempts a biometric unlock.
  ///
  /// Assumes [isBiometricAvailable] returned true. [BiometricKeyStore.unlockKey]
  /// surfaces the OS Face ID / fingerprint prompt and only returns the MK on a
  /// successful OS-enforced authentication.
  ///
  /// On any failure emits [UnlockFailed] with a typed exception — the
  /// presentation layer surfaces a short error and leaves the password
  /// field focused so the user can fall back to manual entry.
  Future<void> unlockWithBiometrics({
    required BiometricPromptCopy copy,
    String? defaultVaultName,
  }) async {
    if (isClosed || state is UnlockLoading) return;
    final generation = keyStore.generation;
    bool canceled() => isClosed || generation != keyStore.generation;
    AppLogger.d('Unlock', 'Biometric unlock requested');
    emit(const UnlockLoading(viaBiometrics: true));

    UnlockResult? result;
    Uint8List? recoveredKey;
    var keysHandedOff = false;
    try {
      late final Future<AccountResponse> accountRead;
      try {
        final keyRead = keyStore.unlockKey(copy);
        // Overlap fresh account I/O with OS authentication without delaying the
        // local prompt. Cancellation must not leave an unobserved HTTP error.
        accountRead = Future.sync(datasource.getUnlockAccount)..ignore();
        recoveredKey = await keyRead;
        if (canceled()) return;
        AppLogger.d('Unlock', 'Biometric key read completed');
      } on BiometricAuthException catch (e) {
        AppLogger.w('Unlock', 'Biometric auth failed: ${e.reason.name}');
        if (!canceled()) emit(UnlockFailed(_mapBiometricFailure(e.reason)));
        return;
      }

      if (recoveredKey == null) {
        AppLogger.w('Unlock', 'No enrolled MK — biometric unavailable');
        emit(const UnlockFailed(BiometricKeyMissingException()));
        return;
      }

      final account = await accountRead;
      if (canceled()) return;
      AppLogger.d('Unlock', 'Biometric account lookup completed');
      final encryptedPrivateKey = account.encryptedPrivateKey;
      if (encryptedPrivateKey == null) {
        throw UnsupportedIdentityKdfException('missing-account-key-material');
      }
      result = await cryptoService.decryptWithMasterKey(
        masterKey: recoveredKey,
        encryptedPrivateKeyBase64: encryptedPrivateKey,
      );

      if (canceled()) return;
      if (keyStore case final VerifiedBiometricKeyMigration migration) {
        await migration.commitVerifiedKey(
          result.masterKey,
          expectedGeneration: generation,
        );
        if (canceled()) return;
      }
      await _provisionDefaultVault(
        privateKey: result.privateKey,
        name: defaultVaultName,
      );

      if (canceled()) return;
      AppLogger.i('Unlock', 'Biometric unlock succeeded');
      emit(
        UnlockSuccess(
          masterKey: result.masterKey,
          privateKey: result.privateKey,
          viaBiometrics: true,
        ),
      );
      keysHandedOff = true;
    } on DioException catch (e, s) {
      if (e.response?.statusCode == 401) {
        AppLogger.w('Unlock', 'Session expired — routing to sign-in');
        if (!canceled()) emit(const UnlockFailed(SessionExpiredException()));
        return;
      }
      AppLogger.e('Unlock', 'Biometric unlock failed', error: e, stackTrace: s);
      if (!canceled()) emit(UnlockFailed(e));
    } catch (e, s) {
      AppLogger.e('Unlock', 'Biometric unlock failed', error: e, stackTrace: s);
      if (!canceled()) emit(UnlockFailed(e));
    } finally {
      if (recoveredKey != null &&
          (!keysHandedOff || !identical(recoveredKey, result?.masterKey))) {
        recoveredKey.fillRange(0, recoveredKey.length, 0);
      }
      if (!keysHandedOff && result != null) {
        result.masterKey.fillRange(0, result.masterKey.length, 0);
        result.privateKey.fillRange(0, result.privateKey.length, 0);
      }
      if (keyStore case final VerifiedBiometricKeyMigration migration) {
        try {
          await migration.discardPendingMigration();
        } catch (error) {
          AppLogger.w(
            'Unlock',
            'Migration cancellation failed: ${error.runtimeType}',
          );
        }
      }
    }
  }

  Future<void> _provisionDefaultVault({
    required Uint8List privateKey,
    required String? name,
  }) async {
    if (name == null) return;

    final required = await defaultVaultProvisioner.isRequired;
    try {
      await defaultVaultProvisioner.ensureFromPrivateKey(
        privateKey: privateKey,
        name: name,
      );
    } catch (error) {
      if (required) rethrow;
      AppLogger.w(
        'Unlock',
        'Default vault availability could not be confirmed: '
            '${error.runtimeType}',
      );
    }
  }

  Exception _mapBiometricFailure(BiometricAuthFailureReason reason) {
    return switch (reason) {
      BiometricAuthFailureReason.canceled ||
      BiometricAuthFailureReason.failed => const BiometricAuthFailedException(),
      BiometricAuthFailureReason.unavailable =>
        const BiometricKeyMissingException(),
    };
  }

  /// Returns `true` if the device can perform a biometric-bound read AND a
  /// master key has been enrolled through explicit setup.
  ///
  /// Called from `initState` so the UI can decide whether to show the
  /// biometric button. Never throws — on any platform error returns `false`
  /// so the user can still unlock with their password.
  Future<bool> isBiometricAvailable() async {
    try {
      if (!await keyStore.isEnrolled()) return false;
      return await keyStore.canStore();
    } catch (e) {
      AppLogger.w(
        'Unlock',
        'Biometric availability check failed: ${e.runtimeType}',
      );
      return false;
    }
  }

  /// Clears the enrolled MK — called when the user explicitly turns biometric
  /// unlock off (or on logout).
  Future<void> clearBiometricKey() => keyStore.clear();
}
