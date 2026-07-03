import 'dart:convert';
import 'dart:typed_data';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/app_logger.dart';
import 'biometric_key_store.dart';
import 'biometric_key_storage.dart';

/// [BiometricKeyStore] backed by the `biometric_storage` plugin (enclave
/// wrapping key, biometric-only, invalidated on biometric-set change).
/// [FlutterSecureStorage] holds only the non-secret marker + legacy cleanup.
class BiometricStorageKeyStore implements BiometricKeyStore {
  BiometricStorageKeyStore({
    required FlutterSecureStorage markerStorage,
    BiometricStorage? biometric,
  })  : _markerStorage = markerStorage,
        _biometric = biometric ?? BiometricStorage();

  final FlutterSecureStorage _markerStorage;
  final BiometricStorage _biometric;

  /// Enclave-file name. `_v2` distinguishes it from the pre-hardening raw key.
  static const _fileName = 'palladin_vault_mk_v2';

  StorageFileInitOptions _initOptions() => StorageFileInitOptions(
        authenticationRequired: true,
        // Per-operation auth (no time window) — the strongest posture.
        authenticationValidityDurationSeconds: -1,
        androidBiometricOnly: true,
        darwinBiometricOnly: true,
      );

  PromptInfo _promptInfo(BiometricPromptCopy copy) => PromptInfo(
        androidPromptInfo: AndroidPromptInfo(
          title: copy.promptTitle,
          negativeButton: copy.cancelLabel,
        ),
        iosPromptInfo: IosPromptInfo(
          saveTitle: copy.enrollTitle,
          accessTitle: copy.accessTitle,
        ),
        macOsPromptInfo: IosPromptInfo(
          saveTitle: copy.enrollTitle,
          accessTitle: copy.accessTitle,
        ),
      );

  @override
  Future<bool> canStore() async {
    try {
      final response = await _biometric.canAuthenticate();
      return response == CanAuthenticateResponse.success;
    } catch (e) {
      AppLogger.w('BiometricKey', 'canAuthenticate failed: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<bool> isEnrolled() async {
    try {
      final marker = await _markerStorage.read(
        key: BiometricKeyStorage.enrolledMarkerKey,
        iOptions: BiometricKeyStorage.iosOptions,
        aOptions: BiometricKeyStorage.androidOptions,
      );
      return marker == '1';
    } catch (e) {
      AppLogger.w('BiometricKey', 'isEnrolled read failed: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<void> enroll(Uint8List masterKey, BiometricPromptCopy copy) async {
    final base64Mk = base64.encode(masterKey);
    try {
      final file = await _biometric.getStorage(
        _fileName,
        options: _initOptions(),
        promptInfo: _promptInfo(copy),
      );
      await file.write(base64Mk, promptInfo: _promptInfo(copy));
    } on AuthException catch (e) {
      throw BiometricAuthException(_mapAuthError(e.code));
    } on BiometricStorageException catch (e) {
      AppLogger.w('BiometricKey', 'enroll storage error: ${e.message}');
      throw const BiometricAuthException(BiometricAuthFailureReason.unavailable);
    }

    // Mark enrolled + delete any legacy raw MK from a pre-hardening install.
    await _markerStorage.write(
      key: BiometricKeyStorage.enrolledMarkerKey,
      value: '1',
      iOptions: BiometricKeyStorage.iosOptions,
      aOptions: BiometricKeyStorage.androidOptions,
    );
    await purgeLegacyRawKey();
  }

  @override
  Future<Uint8List?> unlockKey(BiometricPromptCopy copy) async {
    if (!await isEnrolled()) return null;
    try {
      final file = await _biometric.getStorage(
        _fileName,
        options: _initOptions(),
        promptInfo: _promptInfo(copy),
      );
      final stored = await file.read(promptInfo: _promptInfo(copy));
      if (stored == null || stored.isEmpty) return null;
      return base64.decode(stored);
    } on AuthException catch (e) {
      throw BiometricAuthException(_mapAuthError(e.code));
    } on BiometricStorageException catch (e) {
      // The enclave key was likely invalidated (biometric set changed) or the
      // file is gone — treat as "not usable" and let the caller fall back to
      // the password path. Drop the now-stale marker so we re-enroll cleanly.
      AppLogger.w('BiometricKey', 'unlock storage error: ${e.message}');
      await clear();
      throw const BiometricAuthException(BiometricAuthFailureReason.unavailable);
    }
  }

  @override
  Future<void> clear() async {
    // Clear the enrollment marker (+ any legacy raw key). We deliberately do
    // NOT delete the enclave blob: deleting can surface a biometric prompt on
    // some platforms, and an orphaned blob is harmless — it stays biometric-
    // gated and is overwritten on the next enroll. With the marker gone,
    // isEnrolled() reports false, so the app never tries to read it.
    await BiometricKeyStorage.clear(_markerStorage);
  }

  @override
  Future<void> purgeLegacyRawKey() async {
    try {
      await _markerStorage.delete(
        key: BiometricKeyStorage.legacyRawKey,
        iOptions: BiometricKeyStorage.iosOptions,
        aOptions: BiometricKeyStorage.androidOptions,
      );
    } catch (_) {
      // Non-fatal — the legacy key may simply not exist.
    }
  }

  BiometricAuthFailureReason _mapAuthError(AuthExceptionCode code) {
    return switch (code) {
      AuthExceptionCode.userCanceled ||
      AuthExceptionCode.canceled =>
        BiometricAuthFailureReason.canceled,
      AuthExceptionCode.timeout => BiometricAuthFailureReason.failed,
      // Catch-all fails closed to `unavailable`. `biometric_storage` is an
      // external plugin, so a minor bump adding a new AuthExceptionCode must
      // not break compilation — the wildcard also covers the current
      // `unknown` and `linuxAppArmorDenied` codes.
      _ => BiometricAuthFailureReason.unavailable,
    };
  }
}
