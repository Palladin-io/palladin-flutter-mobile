import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../../../core/utils/app_logger.dart';
import '../../data/datasources/account_remote_datasource.dart';
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
/// 3. Stash the MK in the OS keychain/keystore so biometric unlock can
///    recover it next session without re-running Argon2id.
///
/// Biometric flow (shortcut):
/// 1. Prompt `LocalAuthentication` — OS surfaces Face ID / fingerprint.
/// 2. On success, read the stashed MK from secure storage and use it
///    to decrypt the private key (fresh `GET /api/account` each time
///    so key rotations propagate).
class UnlockCubit extends Cubit<UnlockState> {
  UnlockCubit({
    required this.datasource,
    required this.cryptoService,
    required this.secureStorage,
    LocalAuthentication? localAuth,
  })  : _localAuth = localAuth ?? LocalAuthentication(),
        super(const UnlockInitial());

  final AccountRemoteDatasource datasource;
  final UnlockCryptoService cryptoService;
  final FlutterSecureStorage secureStorage;
  final LocalAuthentication _localAuth;

  /// Key used to stash the base64-encoded master key in the OS
  /// keychain/keystore between sessions. Namespaced under `vault_` to
  /// keep it distinct from auth tokens.
  static const _masterKeyStorageKey = 'vault_mk';

  /// iOS keychain options for storing the MK — unlocked_this_device
  /// so the key never syncs off-device via iCloud and cannot be read
  /// before the device passcode has been entered post-reboot.
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  );

  /// Android options for storing the MK — uses EncryptedSharedPreferences
  /// (API 23+) so the key is protected by the Android Keystore.
  static const _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  /// Runs the master-password unlock pipeline.
  Future<void> unlock(String password) async {
    if (password.isEmpty) return;
    AppLogger.d('Unlock', 'Password unlock requested');
    emit(const UnlockLoading());

    try {
      final account = await datasource.getAccount();
      final result = await cryptoService.deriveAndDecrypt(
        masterPassword: password,
        saltBase64: account.salt,
        encryptedPrivateKeyBase64: account.encryptedPrivateKey,
      );

      // Stash MK for biometric unlock next session. Best-effort — a
      // storage failure here should not block the current unlock.
      try {
        await _persistMasterKey(result.masterKey);
      } catch (e, s) {
        AppLogger.w('Unlock',
            'Failed to persist MK for biometric unlock: ${e.runtimeType}');
        AppLogger.e('Unlock', 'Persist MK error', error: e, stackTrace: s);
      }

      AppLogger.i('Unlock', 'Password unlock succeeded');
      emit(UnlockSuccess(
        masterKey: result.masterKey,
        privateKey: result.privateKey,
      ));
    } on WrongMasterPasswordException catch (e) {
      AppLogger.w('Unlock', 'Wrong master password');
      emit(UnlockFailed(e));
    } catch (e, s) {
      AppLogger.e('Unlock', 'Unlock failed', error: e, stackTrace: s);
      emit(UnlockFailed(e));
    }
  }

  /// Attempts a biometric unlock.
  ///
  /// Assumes [isBiometricAvailable] returned true. Prompts the OS for
  /// Face ID / fingerprint, then recovers the persisted MK and
  /// decrypts the private key.
  ///
  /// On any failure emits [UnlockFailed] with a typed exception — the
  /// presentation layer surfaces a short error and leaves the password
  /// field focused so the user can fall back to manual entry.
  Future<void> unlockWithBiometrics({required String localizedReason}) async {
    AppLogger.d('Unlock', 'Biometric unlock requested');
    emit(const UnlockLoading());

    try {
      final stored = await secureStorage.read(
        key: _masterKeyStorageKey,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
      if (stored == null || stored.isEmpty) {
        AppLogger.w('Unlock', 'No stored MK — biometric unavailable');
        emit(const UnlockFailed(BiometricKeyMissingException()));
        return;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!didAuthenticate) {
        AppLogger.w('Unlock', 'Biometric auth refused');
        emit(const UnlockFailed(BiometricAuthFailedException()));
        return;
      }

      final masterKey = base64.decode(stored);
      final account = await datasource.getAccount();
      final result = await cryptoService.decryptWithMasterKey(
        masterKey: masterKey,
        encryptedPrivateKeyBase64: account.encryptedPrivateKey,
      );

      AppLogger.i('Unlock', 'Biometric unlock succeeded');
      emit(UnlockSuccess(
        masterKey: result.masterKey,
        privateKey: result.privateKey,
        viaBiometrics: true,
      ));
    } catch (e, s) {
      AppLogger.e('Unlock', 'Biometric unlock failed',
          error: e, stackTrace: s);
      emit(UnlockFailed(e));
    }
  }

  /// Returns `true` if the device has biometrics enrolled AND a master
  /// key has been persisted from a prior password unlock.
  ///
  /// Called from `initState` so the UI can decide whether to show the
  /// biometric button. Never throws — on any platform error returns
  /// `false` so the user can still unlock with their password.
  Future<bool> isBiometricAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;

      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;

      final available = await _localAuth.getAvailableBiometrics();
      if (available.isEmpty) return false;

      final stored = await secureStorage.read(
        key: _masterKeyStorageKey,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
      return stored != null && stored.isNotEmpty;
    } catch (e) {
      AppLogger.w('Unlock',
          'Biometric availability check failed: ${e.runtimeType}');
      return false;
    }
  }

  Future<void> _persistMasterKey(Uint8List masterKey) {
    return secureStorage.write(
      key: _masterKeyStorageKey,
      value: base64.encode(masterKey),
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  /// Clears the stashed MK on every platform — called on logout or
  /// when the user explicitly turns biometric unlock off.
  Future<void> clearBiometricKey() async {
    try {
      await secureStorage.delete(
        key: _masterKeyStorageKey,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
    } catch (e) {
      // Best-effort — cleanup should never break logout.
      AppLogger.w('Unlock',
          'Failed to clear stored MK: ${e.runtimeType}');
    }
  }

  /// True on platforms where `local_auth` ships native support. Kept
  /// as a static guard so callers can skip biometric UI entirely on
  /// desktop test runs.
  static bool get isPlatformSupported =>
      Platform.isIOS || Platform.isAndroid;
}
