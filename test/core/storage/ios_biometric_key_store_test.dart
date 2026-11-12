import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/storage/biometric_key_store.dart';
import 'package:mobile_palladin/core/storage/ios_biometric_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.palladin.mobile/shared-biometric-unlock');
  const copy = BiometricPromptCopy(
    promptTitle: 'Unlock',
    enrollTitle: 'Enable',
    accessTitle: 'Access',
    cancelLabel: 'Cancel',
  );
  const ticket = <String, Object>{
    'profileBinding': 'synthetic-binding',
    'sessionId': 'session',
    'sourceEpoch': 4,
  };
  late List<String> events;
  late Future<Object?> Function(MethodCall) handler;
  late IOSBiometricKeyStore store;
  late bool inMutation;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    events = [];
    inMutation = false;
    handler = (_) async => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          events.add(call.method);
          if (['enroll', 'clear', 'commitMigration'].contains(call.method)) {
            expect(
              inMutation,
              isTrue,
              reason: 'Mutation escaped native source quarantine',
            );
          }
          return handler(call);
        });
    store = IOSBiometricKeyStore(
      markerStorage: const FlutterSecureStorage(),
      sourceTicket: () async => ticket,
      withMutation: <T>(operation) async {
        inMutation = true;
        try {
          return await operation(ticket);
        } finally {
          inMutation = false;
        }
      },
    );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'enrollment sends copied bytes and independent ticket under quarantine',
    () async {
      final mk = Uint8List.fromList(List.filled(32, 31));
      handler = (call) async {
        expect(call.arguments['masterKey'], orderedEquals(mk));
        expect(call.arguments['profileBinding'], ticket['profileBinding']);
        expect(call.arguments['sessionId'], ticket['sessionId']);
        expect(call.arguments['sourceEpoch'], 4);
        expect(call.arguments['reason'], 'Enable');
        return null;
      };
      await store.enroll(mk, copy, expectedGeneration: 0);
      expect(mk, everyElement(31));
      expect(events, ['enroll']);
    },
  );

  test(
    'only proven pre-write cancellation reaches source owner as no-change',
    () async {
      Object? ownerFailure;
      final guarded = IOSBiometricKeyStore(
        markerStorage: const FlutterSecureStorage(),
        sourceTicket: () async => ticket,
        withMutation: <T>(op) async {
          inMutation = true;
          try {
            return await op(ticket);
          } catch (error) {
            ownerFailure = error;
            rethrow;
          } finally {
            inMutation = false;
          }
        },
      );
      handler = (_) async =>
          throw PlatformException(code: 'canceled_no_changes');
      await expectLater(
        guarded.enroll(Uint8List(32), copy, expectedGeneration: 0),
        throwsA(isA<BiometricAuthException>()),
      );
      expect(ownerFailure, isA<BiometricMutationCanceledWithoutChanges>());
      handler = (_) async => throw PlatformException(code: 'canceled');
      await expectLater(
        guarded.enroll(Uint8List(32), copy, expectedGeneration: 0),
        throwsA(isA<BiometricAuthException>()),
      );
      expect(
        ownerFailure,
        isNot(isA<BiometricMutationCanceledWithoutChanges>()),
      );
    },
  );

  test('stale enrollment is rejected without native mutation', () async {
    await store.clear();
    events.clear();
    await expectLater(
      store.enroll(Uint8List(32), copy, expectedGeneration: 0),
      throwsA(isA<BiometricAuthException>()),
    );
    expect(events, isEmpty);
  });

  test('legacy unlock waits for verified unwrap before migration', () async {
    handler = (call) async => call.method == 'unlockKey'
        ? {
            'masterKey': Uint8List.fromList(List.filled(32, 11)),
            'migrationId': 'opaque-migration',
          }
        : null;
    final mk = await store.unlockKey(copy);
    expect(events, ['unlockKey']);
    await store.commitVerifiedKey(mk!, expectedGeneration: 0);
    expect(events, ['unlockKey', 'commitMigration']);
    await store.commitVerifiedKey(mk, expectedGeneration: 0);
    expect(events.where((e) => e == 'commitMigration').length, 1);
  });

  test('failed account unwrap discards migration without enrollment', () async {
    handler = (call) async => call.method == 'unlockKey'
        ? {'masterKey': Uint8List(32), 'migrationId': 'pending'}
        : null;
    await store.unlockKey(copy);
    await store.discardPendingMigration();
    expect(events, ['unlockKey', 'cancelMigration']);
  });

  test('clear while native unlock is pending denies late result', () async {
    final entered = Completer<void>();
    final release = Completer<Object?>();
    handler = (call) async {
      if (call.method == 'unlockKey') {
        entered.complete();
        return release.future;
      }
      return null;
    };
    final unlocking = store.unlockKey(copy);
    final expectation = expectLater(
      unlocking,
      throwsA(isA<BiometricAuthException>()),
    );
    await entered.future;
    await store.clear();
    release.complete({
      'masterKey': Uint8List.fromList(List.filled(32, 55)),
      'migrationId': 'late',
    });
    await expectation;
    expect(events, contains('cancelMigration'));
    expect(events, isNot(contains('commitMigration')));
  });

  test(
    'failed migration cancellation cannot skip protected key deletion',
    () async {
      handler = (call) async {
        if (call.method == 'unlockKey') {
          return {'masterKey': Uint8List(32), 'migrationId': 'pending'};
        }
        if (call.method == 'cancelMigration') {
          throw PlatformException(code: 'failed');
        }
        return null;
      };
      await store.unlockKey(copy);
      await expectLater(
        store.clear(),
        throwsA(isA<BiometricKeyCleanupException>()),
      );
      expect(events, contains('clear'));
    },
  );

  test(
    'clear captures old source owner before awaiting migration cancellation',
    () async {
      var current = ticket;
      final cancellationStarted = Completer<void>();
      final release = Completer<void>();
      final scoped = IOSBiometricKeyStore(
        markerStorage: const FlutterSecureStorage(),
        sourceTicket: () async => current,
        withMutation: <T>(op) async {
          final captured = current;
          inMutation = true;
          try {
            return await op(captured);
          } finally {
            inMutation = false;
          }
        },
      );
      handler = (call) async {
        if (call.method == 'unlockKey') {
          return {'masterKey': Uint8List(32), 'migrationId': 'pending'};
        }
        if (call.method == 'cancelMigration') {
          cancellationStarted.complete();
          await release.future;
        }
        if (call.method == 'clear') {
          expect(call.arguments['sessionId'], 'session');
        }
        return null;
      };
      await scoped.unlockKey(copy);
      final clearing = scoped.clear();
      await cancellationStarted.future;
      current = {...ticket, 'sessionId': 'new-account-session'};
      release.complete();
      await clearing;
    },
  );

  test('native cancellation is typed and never retried', () async {
    handler = (_) async => throw PlatformException(code: 'canceled');
    await expectLater(
      store.unlockKey(copy),
      throwsA(
        isA<BiometricAuthException>().having(
          (e) => e.reason,
          'reason',
          BiometricAuthFailureReason.canceled,
        ),
      ),
    );
    expect(events, ['unlockKey']);
  });

  test('native cleanup failure remains observable', () async {
    handler = (_) async => throw PlatformException(code: 'cleanup_failed');
    await expectLater(
      store.clear(),
      throwsA(isA<BiometricKeyCleanupException>()),
    );
    expect(store.generation, 1);
  });

  test(
    'malformed native response does not masquerade as no enrollment',
    () async {
      handler = (_) async => {'masterKey': 'not-typed-bytes'};
      await expectLater(
        store.unlockKey(copy),
        throwsA(isA<BiometricAuthException>()),
      );
    },
  );

  test(
    'bound request cancellation never opens a second biometric prompt',
    () async {
      final bound = IOSBiometricKeyStore(
        markerStorage: const FlutterSecureStorage(),
        sourceTicket: () async => ticket,
        withMutation: <T>(op) => op(ticket),
        activeRequestUnlock: () => (_) async {
          throw const BiometricAuthException(
            BiometricAuthFailureReason.canceled,
          );
        },
      );
      await expectLater(
        bound.unlockKey(copy),
        throwsA(isA<BiometricAuthException>()),
      );
      expect(events, isEmpty);
    },
  );

  test('malformed native key cannot enter unlocked session', () async {
    handler = (_) async => {'masterKey': Uint8List(31)};
    await expectLater(
      store.unlockKey(copy),
      throwsA(isA<BiometricAuthException>()),
    );
  });
}
