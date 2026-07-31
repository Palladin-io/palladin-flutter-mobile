import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/biometric_key_store.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../onboarding/data/services/default_vault_provisioner.dart';
import '../../data/datasources/account_remote_datasource.dart';
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
/// 3. On the FIRST successful password unlock, enroll the MK into the
///    enclave-bound, biometric-gated [BiometricKeyStore] so the biometric
///    shortcut can recover it next session — the MK is never persisted in a
///    form that can be read without a fresh biometric authentication.
///
/// Biometric flow (shortcut):
/// 1. [BiometricKeyStore.unlockKey] triggers the OS biometric prompt; the
///    enclave releases the MK only on a successful authentication.
/// 2. Decrypt the private key with the recovered MK (fresh
///    `GET /api/account` each time so key rotations propagate).
///
/// The password path never touches [BiometricKeyStore], so a device without
/// biometrics — or any enclave failure — leaves password unlock fully working.
class UnlockCubit extends Cubit<UnlockState> {
  UnlockCubit({
    required this.datasource,
    required this.cryptoService,
    required this.keyStore,
    required this.defaultVaultProvisioner,
  }) : super(const UnlockInitial());

  final AccountRemoteDatasource datasource;
  final UnlockCryptoService cryptoService;
  final BiometricKeyStore keyStore;
  final DefaultVaultProvisioner defaultVaultProvisioner;

  /// Runs the master-password unlock pipeline.
  ///
  /// [biometricCopy] carries localized OS-prompt strings for the one-time
  /// biometric enrollment. When `null`, enrollment is skipped (the unlock
  /// itself still succeeds).
  Future<void> unlock(
    String password, {
    BiometricPromptCopy? biometricCopy,
    String? defaultVaultName,
  }) async {
    if (password.isEmpty) return;
    AppLogger.d('Unlock', 'Password unlock requested');
    emit(const UnlockLoading());

    UnlockResult? result;
    var keysHandedOff = false;
    try {
      final account = await datasource.getAccount();
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

      if (biometricCopy != null) {
        await _maybeEnrollBiometric(result.masterKey, biometricCopy);
      }

      await _provisionDefaultVault(
        privateKey: result.privateKey,
        name: defaultVaultName,
      );

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
      emit(UnlockFailed(e));
    } on DioException catch (e, s) {
      if (e.response?.statusCode == 401) {
        AppLogger.w('Unlock', 'Session expired — routing to sign-in');
        emit(const UnlockFailed(SessionExpiredException()));
        return;
      }
      AppLogger.e('Unlock', 'Unlock failed', error: e, stackTrace: s);
      emit(UnlockFailed(e));
    } catch (e, s) {
      AppLogger.e('Unlock', 'Unlock failed', error: e, stackTrace: s);
      emit(UnlockFailed(e));
    } finally {
      if (!keysHandedOff && result != null) {
        result.masterKey.fillRange(0, result.masterKey.length, 0);
        result.privateKey.fillRange(0, result.privateKey.length, 0);
      }
    }
  }

  /// Enrolls [masterKey] into the biometric-gated store on first unlock only.
  ///
  /// Best-effort: an enrollment failure (device can't do biometric-bound
  /// storage, or the user declines the one-time Android confirm) must never
  /// block the current unlock.
  Future<void> _maybeEnrollBiometric(
    Uint8List masterKey,
    BiometricPromptCopy copy,
  ) async {
    // Purge the pre-hardening raw MK FIRST, unconditionally — before the
    // isEnrolled()/canStore() guards. On a non-biometric device canStore()
    // returns false and we bail out before enrollment; if the purge lived only
    // inside enroll(), an upgrading user on such a device would keep the raw MK
    // on disk until logout, partially undoing CVT-199. Best-effort; never
    // blocks unlock.
    await keyStore.purgeLegacyRawKey();
    try {
      if (await keyStore.isEnrolled()) return;
      if (!await keyStore.canStore()) return;
      await keyStore.enroll(masterKey, copy);
      AppLogger.i('Unlock', 'MK enrolled for biometric unlock');
    } catch (e) {
      // Never log the key or the raw error payload — just the type.
      AppLogger.w('Unlock', 'Biometric enrollment skipped: ${e.runtimeType}');
    }
  }

  /// Attempts a biometric unlock.
  ///
  /// Assumes [isBiometricAvailable] returned true. [BiometricKeyStore.unlockKey]
  /// surfaces the OS Face ID / fingerprint prompt and only returns the MK on a
  /// successful, enclave-enforced authentication.
  ///
  /// On any failure emits [UnlockFailed] with a typed exception — the
  /// presentation layer surfaces a short error and leaves the password
  /// field focused so the user can fall back to manual entry.
  Future<void> unlockWithBiometrics({
    required BiometricPromptCopy copy,
    String? defaultVaultName,
  }) async {
    AppLogger.d('Unlock', 'Biometric unlock requested');
    emit(const UnlockLoading());

    UnlockResult? result;
    var keysHandedOff = false;
    try {
      final Uint8List? masterKey;
      try {
        masterKey = await keyStore.unlockKey(copy);
      } on BiometricAuthException catch (e) {
        AppLogger.w('Unlock', 'Biometric auth failed: ${e.reason.name}');
        emit(UnlockFailed(_mapBiometricFailure(e.reason)));
        return;
      }

      if (masterKey == null) {
        AppLogger.w('Unlock', 'No enrolled MK — biometric unavailable');
        emit(const UnlockFailed(BiometricKeyMissingException()));
        return;
      }

      final account = await datasource.getAccount();
      final encryptedPrivateKey = account.encryptedPrivateKey;
      if (encryptedPrivateKey == null) {
        throw UnsupportedIdentityKdfException('missing-account-key-material');
      }
      result = await cryptoService.decryptWithMasterKey(
        masterKey: masterKey,
        encryptedPrivateKeyBase64: encryptedPrivateKey,
      );

      await _provisionDefaultVault(
        privateKey: result.privateKey,
        name: defaultVaultName,
      );

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
        emit(const UnlockFailed(SessionExpiredException()));
        return;
      }
      AppLogger.e('Unlock', 'Biometric unlock failed', error: e, stackTrace: s);
      emit(UnlockFailed(e));
    } catch (e, s) {
      AppLogger.e('Unlock', 'Biometric unlock failed', error: e, stackTrace: s);
      emit(UnlockFailed(e));
    } finally {
      if (!keysHandedOff && result != null) {
        result.masterKey.fillRange(0, result.masterKey.length, 0);
        result.privateKey.fillRange(0, result.privateKey.length, 0);
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
  /// master key has been enrolled from a prior password unlock.
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
