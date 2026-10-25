import 'package:mocktail/mocktail.dart';
import 'dart:async';
import 'package:mobile_palladin/core/storage/biometric_key_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/storage/biometric_key_storage.dart';
import 'package:mobile_palladin/core/storage/biometric_storage_key_store.dart';

class FailingMarkerStorage extends Mock implements FlutterSecureStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.palladin.mobile/biometric-key-cleanup');
  late bool protectedKeyPresent;
  late bool failDeletion;
  late BiometricStorageKeyStore store;

  setUp(() {
    protectedKeyPresent = true;
    failDeletion = false;
    FlutterSecureStorage.setMockInitialValues({
      BiometricKeyStorage.enrolledMarkerKey: '1',
      BiometricKeyStorage.legacyRawKey: 'dummy-legacy-key',
    });
    store = BiometricStorageKeyStore(
      markerStorage: const FlutterSecureStorage(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'deleteKey');
          expect(call.arguments, isNull);
          if (failDeletion) throw PlatformException(code: 'cleanup_failed');
          protectedKeyPresent = false;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('an unlock started before clear cannot enroll afterward', () async {
    final generation = store.generation;
    await store.clear();
    await store.enroll(
      Uint8List(32),
      const BiometricPromptCopy(
        promptTitle: 'dummy',
        enrollTitle: 'dummy',
        accessTitle: 'dummy',
        cancelLabel: 'dummy',
      ),
      expectedGeneration: generation,
    );
    expect(protectedKeyPresent, isFalse);
    expect(await store.isEnrolled(), isFalse);
  });

  test(
    'clear removes protected material and marker, including repeated clear',
    () async {
      await store.clear();
      expect(protectedKeyPresent, isFalse);
      expect(await store.isEnrolled(), isFalse);
      expect(
        await const FlutterSecureStorage().read(
          key: BiometricKeyStorage.legacyRawKey,
        ),
        isNull,
      );
      await store.clear();
      expect(protectedKeyPresent, isFalse);
    },
  );

  test(
    'clear still removes orphaned protected material without marker',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      await store.clear();
      expect(protectedKeyPresent, isFalse);
    },
  );

  test(
    'deletion failure is reported while biometric availability is revoked',
    () async {
      failDeletion = true;
      await expectLater(store.clear(), throwsA(isA<Exception>()));
      expect(protectedKeyPresent, isTrue);
      expect(await store.isEnrolled(), isFalse);
      failDeletion = false;
      await store.clear();
      expect(protectedKeyPresent, isFalse);
    },
  );
  test(
    'clear waits for in-flight enrollment so it cannot recreate deleted material',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('biometric_storage'), (
            call,
          ) async {
            if (call.method == 'init') return true;
            if (call.method == 'write') {
              started.complete();
              await finish.future;
              protectedKeyPresent = true;
              return true;
            }
            throw StateError('Unexpected operation');
          });
      const copy = BiometricPromptCopy(
        promptTitle: 'Test',
        enrollTitle: 'Test',
        accessTitle: 'Test',
        cancelLabel: 'Cancel',
      );
      final enrollment = store.enroll(
        Uint8List(32),
        copy,
        expectedGeneration: store.generation,
      );
      await started.future;
      final cleanup = store.clear();
      await Future<void>.delayed(Duration.zero);
      finish.complete();
      await enrollment;
      await cleanup;
      expect(protectedKeyPresent, isFalse);
      expect(await store.isEnrolled(), isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('biometric_storage'),
            null,
          );
    },
  );

  test(
    'legacy key deletion failure is not reported as a successful clear',
    () async {
      final storage = FailingMarkerStorage();
      when(
        () => storage.delete(
          key: any(named: 'key'),
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        ),
      ).thenThrow(PlatformException(code: 'storage_unavailable'));
      final failingStore = BiometricStorageKeyStore(markerStorage: storage);
      await expectLater(
        failingStore.clear(),
        throwsA(isA<BiometricKeyCleanupException>()),
      );
      expect(protectedKeyPresent, isFalse);
    },
  );
  test(
    'a fresh enrollment works after deletion without weakening biometric options',
    () async {
      String? protectedValue;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('biometric_storage'),
        (call) async {
          final args = call.arguments as Map;
          switch (call.method) {
            case 'init':
              final options = args['options'] as Map;
              expect(options['authenticationRequired'], isTrue);
              expect(options['authenticationValidityDurationSeconds'], -1);
              expect(options['androidBiometricOnly'], isTrue);
              expect(options['darwinBiometricOnly'], isTrue);
              return true;
            case 'write':
              protectedValue = args['content'] as String;
              return true;
            case 'read':
              return protectedValue;
          }
          throw StateError('Unexpected operation');
        },
      );
      messenger.setMockMethodCallHandler(channel, (_) async {
        protectedValue = null;
        return null;
      });
      const copy = BiometricPromptCopy(
        promptTitle: 'Test',
        enrollTitle: 'Test',
        accessTitle: 'Test',
        cancelLabel: 'Cancel',
      );
      await store.enroll(
        Uint8List.fromList(List.filled(32, 1)),
        copy,
        expectedGeneration: store.generation,
      );
      expect(await store.unlockKey(copy), everyElement(1));
      await store.clear();
      expect(protectedValue, isNull);
      expect(await store.unlockKey(copy), isNull);
      await store.enroll(
        Uint8List.fromList(List.filled(32, 2)),
        copy,
        expectedGeneration: store.generation,
      );
      expect(await store.unlockKey(copy), everyElement(2));
      messenger.setMockMethodCallHandler(
        const MethodChannel('biometric_storage'),
        null,
      );
    },
  );
}
