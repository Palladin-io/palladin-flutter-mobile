import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'biometric_key_storage.dart';
import 'biometric_key_store.dart';

typedef BiometricSourceMutation =
    Future<T> Function<T>(
      Future<T> Function(Map<String, Object> sourceTicket) operation,
    );
typedef BiometricRequestUnlock =
    Future<Uint8List?> Function(BiometricPromptCopy);

/// Runner's adapter. Source tickets come from authenticated source authority,
/// never from the biometric envelope or caller-controlled page metadata.
class IOSBiometricKeyStore
    implements BiometricKeyStore, VerifiedBiometricKeyMigration {
  IOSBiometricKeyStore({
    required FlutterSecureStorage markerStorage,
    required Future<Map<String, Object>> Function() sourceTicket,
    required BiometricSourceMutation withMutation,
    BiometricRequestUnlock? Function()? activeRequestUnlock,
  }) : _markerStorage = markerStorage,
       _sourceTicket = sourceTicket,
       _withMutation = withMutation,
       _activeRequestUnlock = activeRequestUnlock;

  static const _channel = MethodChannel(
    'io.palladin.mobile/shared-biometric-unlock',
  );
  final FlutterSecureStorage _markerStorage;
  final Future<Map<String, Object>> Function() _sourceTicket;
  final BiometricSourceMutation _withMutation;
  final BiometricRequestUnlock? Function()? _activeRequestUnlock;
  int _generation = 0;
  bool _unlocking = false;
  String? _migrationId;
  int? _migrationGeneration;

  @override
  int get generation => _generation;

  @override
  Future<bool> canStore() async {
    try {
      return await _channel.invokeMethod<bool>('canStore') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isEnrolled() async {
    try {
      return await _channel.invokeMethod<bool>(
            'isEnrolled',
            await _sourceTicket(),
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  void _requireGeneration(int expected) {
    if (expected != _generation) {
      throw const BiometricAuthException(BiometricAuthFailureReason.canceled);
    }
  }

  @override
  Future<void> enroll(
    Uint8List masterKey,
    BiometricPromptCopy copy, {
    required int expectedGeneration,
  }) async {
    _requireGeneration(expectedGeneration);
    final bytes = Uint8List.fromList(masterKey);
    try {
      await _withMutation<void>((ticket) async {
        _requireGeneration(expectedGeneration);
        try {
          await _channel.invokeMethod<void>('enroll', {
            ...ticket,
            'masterKey': bytes,
            'reason': copy.enrollTitle,
            'cancelLabel': copy.cancelLabel,
          });
        } on PlatformException catch (error) {
          if (error.code == 'canceled_no_changes') {
            throw const BiometricMutationCanceledWithoutChanges();
          }
          rethrow;
        }
        _requireGeneration(expectedGeneration);
        await purgeLegacyRawKey();
      });
    } on PlatformException catch (error) {
      throw _authError(error);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<Uint8List?> unlockKey(BiometricPromptCopy copy) async {
    if (_unlocking) {
      throw const BiometricAuthException(BiometricAuthFailureReason.canceled);
    }
    _unlocking = true;
    final expected = _generation;
    Uint8List? bytes;
    var handedOff = false;
    try {
      await discardPendingMigration();
      final requestUnlock = _activeRequestUnlock?.call();
      if (requestUnlock != null) {
        bytes = await requestUnlock(copy);
      } else {
        final ticket = await _sourceTicket();
        _requireGeneration(expected);
        final result = await _channel.invokeMapMethod<String, Object?>(
          'unlockKey',
          {
            ...ticket,
            'reason': copy.accessTitle,
            'cancelLabel': copy.cancelLabel,
          },
        );
        if (result == null) return null;
        final rawKey = result['masterKey'];
        if (rawKey is! Uint8List) {
          throw const BiometricAuthException(
            BiometricAuthFailureReason.unavailable,
          );
        }
        bytes = rawKey;
        final migration = result['migrationId'];
        if (migration is String && migration.isNotEmpty) {
          _migrationId = migration;
          _migrationGeneration = expected;
        }
      }
      _requireGeneration(expected);
      if (bytes == null) return null;
      if (bytes.length != 32) {
        throw const BiometricAuthException(
          BiometricAuthFailureReason.unavailable,
        );
      }
      handedOff = true;
      return bytes;
    } on PlatformException catch (error) {
      throw _authError(error);
    } finally {
      _unlocking = false;
      if (!handedOff) {
        bytes?.fillRange(0, bytes.length, 0);
        await discardPendingMigration();
      }
    }
  }

  @override
  Future<void> commitVerifiedKey(
    Uint8List masterKey, {
    required int expectedGeneration,
  }) async {
    _requireGeneration(expectedGeneration);
    final id = _migrationId;
    if (id == null) return;
    if (_migrationGeneration != expectedGeneration) {
      throw const BiometricAuthException(BiometricAuthFailureReason.canceled);
    }
    final bytes = Uint8List.fromList(masterKey);
    try {
      await _withMutation<void>((ticket) async {
        _requireGeneration(expectedGeneration);
        await _channel.invokeMethod<void>('commitMigration', {
          ...ticket,
          'migrationId': id,
          'masterKey': bytes,
        });
        _requireGeneration(expectedGeneration);
        await purgeLegacyRawKey();
      });
      if (_migrationId == id) {
        _migrationId = null;
        _migrationGeneration = null;
      }
    } on PlatformException catch (error) {
      throw _authError(error);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<void> discardPendingMigration() async {
    final id = _migrationId;
    _migrationId = null;
    _migrationGeneration = null;
    if (id != null) {
      await _channel.invokeMethod<void>('cancelMigration', {'migrationId': id});
    }
  }

  @override
  Future<void> clear() async {
    ++_generation;
    var failed = false;
    var cancellationAttempted = false;
    try {
      // Admit the old source owner before waiting for cancellation. A queued
      // logout must never acquire the next account's cleanup authority.
      await _withMutation<void>((ticket) async {
        var mutationFailed = false;
        cancellationAttempted = true;
        try {
          await discardPendingMigration();
        } catch (_) {
          mutationFailed = true;
        }
        try {
          await _channel.invokeMethod<void>('clear', ticket);
        } catch (_) {
          mutationFailed = true;
        }
        if (mutationFailed) throw const BiometricKeyCleanupException();
      });
    } catch (_) {
      failed = true;
    }
    if (!cancellationAttempted) {
      try {
        await discardPendingMigration();
      } catch (_) {
        failed = true;
      }
    }
    try {
      await BiometricKeyStorage.clear(_markerStorage);
    } catch (_) {
      failed = true;
    }
    if (failed) throw const BiometricKeyCleanupException();
  }

  @override
  Future<void> purgeLegacyRawKey() => _markerStorage.delete(
    key: BiometricKeyStorage.legacyRawKey,
    iOptions: BiometricKeyStorage.iosOptions,
    aOptions: BiometricKeyStorage.androidOptions,
  );

  BiometricAuthException _authError(PlatformException error) =>
      BiometricAuthException(switch (error.code) {
        'canceled' => BiometricAuthFailureReason.canceled,
        'failed' => BiometricAuthFailureReason.failed,
        _ => BiometricAuthFailureReason.unavailable,
      });
}
