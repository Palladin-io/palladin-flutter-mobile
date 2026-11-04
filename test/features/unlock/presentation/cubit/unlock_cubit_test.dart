import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/storage/biometric_key_store.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/onboarding/data/services/default_vault_provisioner.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mobile_palladin/features/unlock/data/services/unlock_crypto_service.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';
import 'package:mobile_palladin/features/unlock/domain/unlock_exceptions.dart';
import 'package:mobile_palladin/features/unlock/presentation/cubit/unlock_cubit.dart';

class _MockAccountDatasource extends Mock implements AccountRemoteDatasource {}

class _MockCryptoService extends Mock implements UnlockCryptoService {}

class _MockKeyStore extends Mock implements BiometricKeyStore {}

class _MigratingKeyStore extends _MockKeyStore
    implements VerifiedBiometricKeyMigration {}

class _MockDefaultVaultProvisioner extends Mock
    implements DefaultVaultProvisioner {}

void main() {
  late _MockAccountDatasource datasource;
  late _MockCryptoService crypto;
  late _MockKeyStore keyStore;
  late _MockDefaultVaultProvisioner defaultVaultProvisioner;

  final masterKey = Uint8List.fromList(List.filled(32, 0xAA));
  final privateKey = Uint8List.fromList(List.filled(32, 0xBB));
  final accountResponse = const AccountResponse(
    userId: '00112233-4455-6677-8899-aabbccddeeff',
    salt: 'c2FsdC1pcy1zaXh0ZWVuISE=', // 16 bytes of arbitrary base64
    encryptedPrivateKey: 'ZW5jcnlwdGVk',
    kdf: IdentityKdfMetadata(
      securityVersion: 1,
      minimumSecurityVersion: 1,
      profileId: IdentityKdfProfile.id,
      kdfSalt: 'AAECAwQFBgcICQoLDA0ODw',
      credentialRevision: 1,
      privateKeyWrapRevision: 1,
    ),
  );
  const copy = BiometricPromptCopy(
    promptTitle: 'title',
    enrollTitle: 'enroll',
    accessTitle: 'access',
    cancelLabel: 'cancel',
  );

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(copy);
    registerFallbackValue(accountResponse.kdf!);
  });

  setUp(() {
    datasource = _MockAccountDatasource();
    crypto = _MockCryptoService();
    keyStore = _MockKeyStore();
    when(() => keyStore.generation).thenReturn(0);
    defaultVaultProvisioner = _MockDefaultVaultProvisioner();
    // Legacy-key purge runs on every password unlock — default it to a no-op.
    when(() => keyStore.purgeLegacyRawKey()).thenAnswer((_) async {});
  });

  /// Default enrollment stubs: device supports biometric storage and nothing
  /// is enrolled yet. Password unlock must not request enrollment.
  void stubEnrollmentReady() {
    when(() => keyStore.isEnrolled()).thenAnswer((_) async => false);
    when(() => keyStore.canStore()).thenAnswer((_) async => true);
    when(
      () => keyStore.enroll(
        any(),
        any(),
        expectedGeneration: any(named: 'expectedGeneration'),
      ),
    ).thenAnswer((_) async {});
  }

  void stubPasswordUnlockSuccess() {
    when(
      () => datasource.getAccount(),
    ).thenAnswer((_) async => accountResponse);
    when(
      () => crypto.deriveAndDecrypt(
        masterPassword: any(named: 'masterPassword'),
        accountId: any(named: 'accountId'),
        kdf: any(named: 'kdf'),
        encryptedPrivateKeyBase64: any(named: 'encryptedPrivateKeyBase64'),
      ),
    ).thenAnswer(
      (_) async => UnlockResult(masterKey: masterKey, privateKey: privateKey),
    );
  }

  UnlockCubit buildCubit() => UnlockCubit(
    datasource: datasource,
    cryptoService: crypto,
    keyStore: keyStore,
    defaultVaultProvisioner: defaultVaultProvisioner,
  );

  for (final closeCubit in [true, false]) {
    test(
      '${closeCubit ? 'disposed' : 'cleared'} unlock wipes keys after delayed KDF',
      () async {
        stubPasswordUnlockSuccess();
        stubEnrollmentReady();
        final entered = Completer<void>();
        final release = Completer<void>();
        final mk = Uint8List.fromList(List.filled(32, 42));
        final pk = Uint8List.fromList(List.filled(32, 43));
        when(
          () => crypto.deriveAndDecrypt(
            masterPassword: any(named: 'masterPassword'),
            accountId: any(named: 'accountId'),
            kdf: any(named: 'kdf'),
            encryptedPrivateKeyBase64: any(named: 'encryptedPrivateKeyBase64'),
          ),
        ).thenAnswer((_) async {
          entered.complete();
          await release.future;
          return UnlockResult(masterKey: mk, privateKey: pk);
        });
        final cubit = buildCubit();
        final unlocking = cubit.unlock('dummy');
        await entered.future;
        if (closeCubit) {
          await cubit.close();
        } else {
          when(() => keyStore.generation).thenReturn(1);
        }
        release.complete();
        await unlocking;
        verifyNever(
          () => keyStore.enroll(
            any(),
            any(),
            expectedGeneration: any(named: 'expectedGeneration'),
          ),
        );
        expect(mk, everyElement(0));
        expect(pk, everyElement(0));
        if (!closeCubit) await cubit.close();
      },
    );
  }
  for (final phase in ['read', 'account', 'decrypt']) {
    test(
      'biometric cleanup during $phase denies late success and wipes keys',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final recovered = Uint8List.fromList(List.filled(32, 41));
        final resultMK = Uint8List.fromList(List.filled(32, 42));
        final resultPK = Uint8List.fromList(List.filled(32, 43));
        Future<void> pause(String stage) async {
          if (stage == phase) {
            entered.complete();
            await release.future;
          }
        }

        when(() => keyStore.unlockKey(any())).thenAnswer((_) async {
          await pause('read');
          return recovered;
        });
        when(() => datasource.getAccount()).thenAnswer((_) async {
          await pause('account');
          return accountResponse;
        });
        when(
          () => crypto.decryptWithMasterKey(
            masterKey: any(named: 'masterKey'),
            encryptedPrivateKeyBase64: any(named: 'encryptedPrivateKeyBase64'),
          ),
        ).thenAnswer((_) async {
          await pause('decrypt');
          return UnlockResult(masterKey: resultMK, privateKey: resultPK);
        });
        final cubit = buildCubit();
        final operation = cubit.unlockWithBiometrics(copy: copy);
        await entered.future;
        when(() => keyStore.generation).thenReturn(1);
        release.complete();
        await operation;
        expect(cubit.state, isNot(isA<UnlockSuccess>()));
        expect(recovered, everyElement(0));
        if (phase == 'decrypt') {
          expect(resultMK, everyElement(0));
          expect(resultPK, everyElement(0));
        }
        await cubit.close();
      },
    );
  }
  for (final failure in ['none', 'unwrap', 'migration']) {
    test(
      'legacy biometric migration is committed only after verified unwrap: $failure',
      () async {
        final migrating = _MigratingKeyStore();
        keyStore = migrating;
        final events = <String>[];
        final recovered = Uint8List.fromList(List.filled(32, 21));
        final resultMK = Uint8List.fromList(List.filled(32, 22));
        final resultPK = Uint8List.fromList(List.filled(32, 23));
        when(() => migrating.generation).thenReturn(0);
        when(
          () => migrating.unlockKey(any()),
        ).thenAnswer((_) async => recovered);
        when(() => migrating.discardPendingMigration()).thenAnswer((_) async {
          events.add('discard');
        });
        when(
          () => migrating.commitVerifiedKey(
            any(),
            expectedGeneration: any(named: 'expectedGeneration'),
          ),
        ).thenAnswer((_) async {
          events.add('migrate');
          if (failure == 'migration') {
            throw const BiometricKeyCleanupException();
          }
        });
        when(
          () => datasource.getAccount(),
        ).thenAnswer((_) async => accountResponse);
        when(
          () => crypto.decryptWithMasterKey(
            masterKey: any(named: 'masterKey'),
            encryptedPrivateKeyBase64: any(named: 'encryptedPrivateKeyBase64'),
          ),
        ).thenAnswer((_) async {
          events.add('unwrap');
          if (failure == 'unwrap') throw const WrongMasterPasswordException();
          return UnlockResult(masterKey: resultMK, privateKey: resultPK);
        });
        final cubit = buildCubit();
        await cubit.unlockWithBiometrics(copy: copy);
        expect(
          events,
          failure == 'unwrap'
              ? ['unwrap', 'discard']
              : ['unwrap', 'migrate', 'discard'],
        );
        expect(
          cubit.state,
          failure == 'none' ? isA<UnlockSuccess>() : isA<UnlockFailed>(),
        );
        expect(recovered, everyElement(0));
        if (failure == 'migration') {
          expect(resultMK, everyElement(0));
          expect(resultPK, everyElement(0));
        }
        await cubit.close();
      },
    );
  }
  for (final outcome in [
    'success',
    'wrong-password',
    'stale-request',
    'capture-invalid',
  ]) {
    test(
      'password request authorization follows successful crypto only: $outcome',
      () async {
        final events = <String>[];
        final mk = Uint8List.fromList(List.filled(32, 31));
        final pk = Uint8List.fromList(List.filled(32, 32));
        when(() => datasource.getAccount()).thenAnswer((_) async {
          events.add('account');
          return accountResponse;
        });
        when(
          () => crypto.deriveAndDecrypt(
            masterPassword: any(named: 'masterPassword'),
            accountId: any(named: 'accountId'),
            kdf: any(named: 'kdf'),
            encryptedPrivateKeyBase64: any(named: 'encryptedPrivateKeyBase64'),
          ),
        ).thenAnswer((_) async {
          events.add('crypto');
          if (outcome == 'wrong-password') {
            throw const WrongMasterPasswordException();
          }
          return UnlockResult(masterKey: mk, privateKey: pk);
        });
        final cubit = UnlockCubit(
          datasource: datasource,
          cryptoService: crypto,
          keyStore: keyStore,
          defaultVaultProvisioner: defaultVaultProvisioner,
          captureRequestAuthorization: () {
            events.add('capture');
            if (outcome == 'capture-invalid') {
              throw StateError('Request ended');
            }
            return () async {
              events.add('authorize');
              if (outcome == 'stale-request') throw StateError('Request ended');
            };
          },
        );
        await cubit.unlock('synthetic');
        expect(
          events,
          outcome == 'capture-invalid'
              ? ['capture']
              : outcome == 'wrong-password'
              ? ['capture', 'account', 'crypto']
              : ['capture', 'account', 'crypto', 'authorize'],
        );
        expect(
          cubit.state,
          outcome == 'success' ? isA<UnlockSuccess>() : isA<UnlockFailed>(),
        );
        if (outcome == 'stale-request') {
          expect(mk, everyElement(0));
          expect(pk, everyElement(0));
        }
        await cubit.close();
      },
    );
  }
  group('UnlockCubit', () {
    test('initial state is UnlockInitial', () {
      final cubit = buildCubit();
      expect(cubit.state, isA<UnlockInitial>());
      cubit.close();
    });

    blocTest<UnlockCubit, UnlockState>(
      'password unlock fails before crypto when account setup is incomplete',
      build: () {
        when(
          () => datasource.getAccount(),
        ).thenAnswer((_) async => const AccountResponse(userId: 'account-id'));
        return buildCubit();
      },
      act: (cubit) => cubit.unlock('pw'),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockFailed>().having(
          (state) => state.error,
          'error',
          isA<UnsupportedIdentityKdfException>(),
        ),
      ],
      verify: (_) {
        verifyNever(
          () => crypto.deriveAndDecrypt(
            masterPassword: any(named: 'masterPassword'),
            accountId: any(named: 'accountId'),
            kdf: any(named: 'kdf'),
            encryptedPrivateKeyBase64: any(named: 'encryptedPrivateKeyBase64'),
          ),
        );
      },
    );

    blocTest<UnlockCubit, UnlockState>(
      'password unlock succeeds without starting biometric enrollment',
      build: () {
        stubEnrollmentReady();
        stubPasswordUnlockSuccess();
        return buildCubit();
      },
      act: (cubit) => cubit.unlock('Correct Horse Battery 9!'),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockSuccess>()
            .having((s) => s.viaBiometrics, 'viaBiometrics', false)
            .having((s) => s.masterKey, 'masterKey', masterKey)
            .having((s) => s.privateKey, 'privateKey', privateKey),
      ],
      verify: (_) {
        verifyNever(
          () => keyStore.enroll(
            any(),
            any(),
            expectedGeneration: any(named: 'expectedGeneration'),
          ),
        );
      },
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlock provisions a pending default vault before exposing keys',
      build: () {
        stubPasswordUnlockSuccess();
        when(
          () => defaultVaultProvisioner.isRequired,
        ).thenAnswer((_) async => true);
        when(
          () => defaultVaultProvisioner.ensureFromPrivateKey(
            privateKey: any(named: 'privateKey'),
            name: any(named: 'name'),
          ),
        ).thenAnswer((_) async {});
        return buildCubit();
      },
      act: (cubit) => cubit.unlock('pw', defaultVaultName: 'Personal'),
      expect: () => [isA<UnlockLoading>(), isA<UnlockSuccess>()],
      verify: (_) {
        verify(
          () => defaultVaultProvisioner.ensureFromPrivateKey(
            privateKey: privateKey,
            name: 'Personal',
          ),
        ).called(1);
      },
    );

    test(
      'unlock keeps a known pending vault retry and zeroes dropped keys',
      () async {
        final droppedMasterKey = Uint8List.fromList(List.filled(32, 0xCC));
        final droppedPrivateKey = Uint8List.fromList(List.filled(32, 0xDD));
        when(
          () => datasource.getAccount(),
        ).thenAnswer((_) async => accountResponse);
        when(
          () => crypto.deriveAndDecrypt(
            masterPassword: any(named: 'masterPassword'),
            accountId: any(named: 'accountId'),
            kdf: any(named: 'kdf'),
            encryptedPrivateKeyBase64: any(named: 'encryptedPrivateKeyBase64'),
          ),
        ).thenAnswer(
          (_) async => UnlockResult(
            masterKey: droppedMasterKey,
            privateKey: droppedPrivateKey,
          ),
        );
        when(
          () => defaultVaultProvisioner.isRequired,
        ).thenAnswer((_) async => true);
        when(
          () => defaultVaultProvisioner.ensureFromPrivateKey(
            privateKey: any(named: 'privateKey'),
            name: any(named: 'name'),
          ),
        ).thenThrow(Exception('backend unavailable'));
        final cubit = buildCubit();

        await cubit.unlock('pw', defaultVaultName: 'Personal');

        expect(cubit.state, isA<UnlockFailed>());
        expect(droppedMasterKey, everyElement(0));
        expect(droppedPrivateKey, everyElement(0));
        await cubit.close();
      },
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlock purges the legacy raw MK even when the device cannot store a '
      'biometric key during the upgrade path',
      build: () {
        when(() => keyStore.isEnrolled()).thenAnswer((_) async => false);
        when(() => keyStore.canStore()).thenAnswer((_) async => false);
        stubPasswordUnlockSuccess();
        return buildCubit();
      },
      act: (cubit) => cubit.unlock('pw'),
      expect: () => [isA<UnlockLoading>(), isA<UnlockSuccess>()],
      verify: (_) {
        verify(() => keyStore.purgeLegacyRawKey()).called(1);
        verifyNever(
          () => keyStore.enroll(
            any(),
            any(),
            expectedGeneration: any(named: 'expectedGeneration'),
          ),
        );
      },
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlock emits [Loading, Failed] on wrong master password',
      build: () {
        when(
          () => datasource.getAccount(),
        ).thenAnswer((_) async => accountResponse);
        when(
          () => crypto.deriveAndDecrypt(
            masterPassword: any(named: 'masterPassword'),
            accountId: any(named: 'accountId'),
            kdf: any(named: 'kdf'),
            encryptedPrivateKeyBase64: any(named: 'encryptedPrivateKeyBase64'),
          ),
        ).thenThrow(const WrongMasterPasswordException());
        return buildCubit();
      },
      act: (cubit) => cubit.unlock('wrong'),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockFailed>().having(
          (s) => s.error,
          'error',
          isA<WrongMasterPasswordException>(),
        ),
      ],
      verify: (_) {
        verifyNever(
          () => keyStore.enroll(
            any(),
            any(),
            expectedGeneration: any(named: 'expectedGeneration'),
          ),
        );
      },
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlock emits Failed(SessionExpiredException) on a 401 from getAccount',
      build: () {
        when(() => datasource.getAccount()).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/api/account'),
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/account'),
              statusCode: 401,
            ),
          ),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.unlock('pw'),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockFailed>().having(
          (s) => s.error,
          'error',
          isA<SessionExpiredException>(),
        ),
      ],
      verify: (_) {
        verifyNever(
          () => keyStore.enroll(
            any(),
            any(),
            expectedGeneration: any(named: 'expectedGeneration'),
          ),
        );
      },
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlock is a no-op on empty password',
      build: buildCubit,
      act: (cubit) => cubit.unlock(''),
      expect: () => const <UnlockState>[],
      verify: (_) {
        verifyNever(() => datasource.getAccount());
      },
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlockWithBiometrics emits Failed when no MK is enrolled',
      build: () {
        when(() => keyStore.unlockKey(any())).thenAnswer((_) async => null);
        return buildCubit();
      },
      act: (cubit) => cubit.unlockWithBiometrics(copy: copy),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockFailed>().having(
          (s) => s.error,
          'error',
          isA<BiometricKeyMissingException>(),
        ),
      ],
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlockWithBiometrics emits Failed when the OS auth is cancelled',
      build: () {
        when(() => keyStore.unlockKey(any())).thenThrow(
          const BiometricAuthException(BiometricAuthFailureReason.canceled),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.unlockWithBiometrics(copy: copy),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockFailed>().having(
          (s) => s.error,
          'error',
          isA<BiometricAuthFailedException>(),
        ),
      ],
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlockWithBiometrics maps an unavailable enclave to key-missing',
      build: () {
        when(() => keyStore.unlockKey(any())).thenThrow(
          const BiometricAuthException(BiometricAuthFailureReason.unavailable),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.unlockWithBiometrics(copy: copy),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockFailed>().having(
          (s) => s.error,
          'error',
          isA<BiometricKeyMissingException>(),
        ),
      ],
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlockWithBiometrics emits Success with viaBiometrics=true on happy path',
      build: () {
        when(
          () => keyStore.unlockKey(any()),
        ).thenAnswer((_) async => masterKey);
        when(
          () => datasource.getAccount(),
        ).thenAnswer((_) async => accountResponse);
        when(
          () => crypto.decryptWithMasterKey(
            masterKey: any(named: 'masterKey'),
            encryptedPrivateKeyBase64: any(named: 'encryptedPrivateKeyBase64'),
          ),
        ).thenAnswer(
          (_) async =>
              UnlockResult(masterKey: masterKey, privateKey: privateKey),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.unlockWithBiometrics(copy: copy),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockSuccess>()
            .having((s) => s.viaBiometrics, 'viaBiometrics', true)
            .having((s) => s.privateKey, 'privateKey', privateKey),
      ],
    );
  });
}
