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
    defaultVaultProvisioner = _MockDefaultVaultProvisioner();
    // Legacy-key purge runs on every password unlock — default it to a no-op.
    when(() => keyStore.purgeLegacyRawKey()).thenAnswer((_) async {});
  });

  /// Default enrollment stubs: device supports biometric storage and nothing
  /// is enrolled yet, so the first password unlock enrolls the MK.
  void stubEnrollmentReady() {
    when(() => keyStore.isEnrolled()).thenAnswer((_) async => false);
    when(() => keyStore.canStore()).thenAnswer((_) async => true);
    when(() => keyStore.enroll(any(), any())).thenAnswer((_) async {});
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
      'unlock emits [Loading, Success] and enrolls MK on correct password',
      build: () {
        stubEnrollmentReady();
        stubPasswordUnlockSuccess();
        return buildCubit();
      },
      act: (cubit) =>
          cubit.unlock('Correct Horse Battery 9!', biometricCopy: copy),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockSuccess>()
            .having((s) => s.viaBiometrics, 'viaBiometrics', false)
            .having((s) => s.masterKey, 'masterKey', masterKey)
            .having((s) => s.privateKey, 'privateKey', privateKey),
      ],
      verify: (_) {
        verify(() => keyStore.enroll(masterKey, copy)).called(1);
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
      'unlock skips enrollment when MK is already enrolled',
      build: () {
        when(() => keyStore.isEnrolled()).thenAnswer((_) async => true);
        stubPasswordUnlockSuccess();
        return buildCubit();
      },
      act: (cubit) => cubit.unlock('pw', biometricCopy: copy),
      expect: () => [isA<UnlockLoading>(), isA<UnlockSuccess>()],
      verify: (_) {
        verifyNever(() => keyStore.enroll(any(), any()));
      },
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlock skips enrollment when device cannot store a biometric key',
      build: () {
        when(() => keyStore.isEnrolled()).thenAnswer((_) async => false);
        when(() => keyStore.canStore()).thenAnswer((_) async => false);
        stubPasswordUnlockSuccess();
        return buildCubit();
      },
      act: (cubit) => cubit.unlock('pw', biometricCopy: copy),
      expect: () => [isA<UnlockLoading>(), isA<UnlockSuccess>()],
      verify: (_) {
        verifyNever(() => keyStore.enroll(any(), any()));
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
      act: (cubit) => cubit.unlock('pw', biometricCopy: copy),
      expect: () => [isA<UnlockLoading>(), isA<UnlockSuccess>()],
      verify: (_) {
        // Purge must run before the canStore() guard bails out; enrollment
        // itself is correctly skipped on a non-biometric device.
        verify(() => keyStore.purgeLegacyRawKey()).called(1);
        verifyNever(() => keyStore.enroll(any(), any()));
      },
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlock still succeeds when biometric enrollment throws',
      build: () {
        when(() => keyStore.isEnrolled()).thenAnswer((_) async => false);
        when(() => keyStore.canStore()).thenAnswer((_) async => true);
        when(() => keyStore.enroll(any(), any())).thenThrow(
          const BiometricAuthException(BiometricAuthFailureReason.canceled),
        );
        stubPasswordUnlockSuccess();
        return buildCubit();
      },
      act: (cubit) => cubit.unlock('pw', biometricCopy: copy),
      expect: () => [isA<UnlockLoading>(), isA<UnlockSuccess>()],
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
      act: (cubit) => cubit.unlock('wrong', biometricCopy: copy),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockFailed>().having(
          (s) => s.error,
          'error',
          isA<WrongMasterPasswordException>(),
        ),
      ],
      verify: (_) {
        verifyNever(() => keyStore.enroll(any(), any()));
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
      act: (cubit) => cubit.unlock('pw', biometricCopy: copy),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockFailed>().having(
          (s) => s.error,
          'error',
          isA<SessionExpiredException>(),
        ),
      ],
      verify: (_) {
        verifyNever(() => keyStore.enroll(any(), any()));
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
