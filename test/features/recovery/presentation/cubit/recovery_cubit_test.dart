import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/recovery/data/datasources/recovery_remote_datasource.dart';
import 'package:mobile_palladin/features/recovery/data/models/recover_account_request.dart';
import 'package:mobile_palladin/features/recovery/data/services/recovery_crypto_service.dart';
import 'package:mobile_palladin/features/recovery/domain/recovery_exceptions.dart';
import 'package:mobile_palladin/features/recovery/presentation/cubit/recovery_cubit.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';

class _MockDatasource extends Mock implements RecoveryRemoteDatasource {}

class _MockCrypto extends Mock implements RecoveryCryptoService {}

void main() {
  late _MockDatasource datasource;
  late _MockCrypto crypto;

  const validMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon abandon abandon abandon art';

  final accountWithRecovery = const AccountResponse(
    userId: '00112233-4455-6677-8899-aabbccddeeff',
    salt: 'c2FsdC1pcy1zaXh0ZWVuISE=',
    encryptedPrivateKey: 'ZW5jcnlwdGVk',
    kdf: IdentityKdfMetadata(
      securityVersion: 1,
      minimumSecurityVersion: 1,
      profileId: 'identity-argon2id-password-v1',
      kdfSalt: 'AAECAwQFBgcICQoLDA0ODw',
      credentialRevision: 1,
      privateKeyWrapRevision: 1,
    ),
    recoverySalt: 'cmVjb3Zlcnktc2FsdC0xNiE=',
    encryptedPrivateKeyByRecovery: 'cmVjLWVuY3J5cHRlZA==',
  );

  final accountWithoutRecovery = const AccountResponse(
    userId: '00112233-4455-6677-8899-aabbccddeeff',
    salt: 'c2FsdC1pcy1zaXh0ZWVuISE=',
    encryptedPrivateKey: 'ZW5jcnlwdGVk',
  );

  const sessionUserId = '0b9e1b6c-5f3a-4d2e-9c41-7a8b6d5e4f30';
  const sealedChallenge = 'sealed-challenge';

  RecoverAccountRequest buildRequest() => RecoverAccountRequest(
    baseCredentialRevision: 1,
    basePrivateKeyWrapRevision: 1,
    newKdfSalt: Uint8List(16),
    newEncryptedPrivateKey: Uint8List(48),
    newRecoverySalt: Uint8List(16),
    newEncryptedPrivateKeyByRecovery: Uint8List(48),
    recoveryProof: Uint8List.fromList(List.filled(32, 7)),
  );

  late RecoveryResult fakeResult;

  setUpAll(() {
    registerFallbackValue(buildRequest());
  });

  setUp(() {
    datasource = _MockDatasource();
    crypto = _MockCrypto();
    fakeResult = RecoveryResult(
      request: buildRequest(),
      newRecoveryMnemonic: List<String>.generate(24, (i) => 'word${i + 1}'),
    );
  });

  RecoveryCubit buildCubit() => RecoveryCubit(
    datasource: datasource,
    cryptoService: crypto,
    sessionUserId: () async => sessionUserId,
  );

  void stubPipeline() {
    when(
      () => datasource.getAccount(),
    ).thenAnswer((_) async => accountWithRecovery);
    when(
      () => crypto.validateRecoveryMnemonic(
        recoveryMnemonic: any(named: 'recoveryMnemonic'),
        recoverySaltBase64: any(named: 'recoverySaltBase64'),
        encryptedPrivateKeyByRecoveryBase64: any(
          named: 'encryptedPrivateKeyByRecoveryBase64',
        ),
      ),
    ).thenAnswer((_) async {});
    when(
      () => datasource.createRecoveryChallenge(),
    ).thenAnswer((_) async => sealedChallenge);
    when(
      () => crypto.recoverAccount(
        recoveryMnemonic: any(named: 'recoveryMnemonic'),
        newPassword: any(named: 'newPassword'),
        recoverySaltBase64: any(named: 'recoverySaltBase64'),
        encryptedPrivateKeyByRecoveryBase64: any(
          named: 'encryptedPrivateKeyByRecoveryBase64',
        ),
        accountId: any(named: 'accountId'),
        sessionUserId: any(named: 'sessionUserId'),
        sealedChallenge: any(named: 'sealedChallenge'),
        baseCredentialRevision: any(named: 'baseCredentialRevision'),
        basePrivateKeyWrapRevision: any(named: 'basePrivateKeyWrapRevision'),
      ),
    ).thenAnswer((_) async => fakeResult);
  }

  Future<void> recover(RecoveryCubit cubit) async {
    await cubit.validateAndProceed(validMnemonic);
    await cubit.completeRecovery('newMasterPassword!');
  }

  group('RecoveryCubit', () {
    test('initial state is RecoveryInitial', () {
      final cubit = buildCubit();
      expect(cubit.state, isA<RecoveryInitial>());
      cubit.close();
    });

    blocTest<RecoveryCubit, RecoveryState>(
      'validateAndProceed is a no-op on empty input',
      build: buildCubit,
      act: (cubit) => cubit.validateAndProceed('   '),
      expect: () => const <RecoveryState>[],
      verify: (_) {
        verifyNever(() => datasource.getAccount());
      },
    );

    blocTest<RecoveryCubit, RecoveryState>(
      'validateAndProceed emits Loading then KeyValidated on success',
      build: () {
        when(
          () => datasource.getAccount(),
        ).thenAnswer((_) async => accountWithRecovery);
        when(
          () => crypto.validateRecoveryMnemonic(
            recoveryMnemonic: any(named: 'recoveryMnemonic'),
            recoverySaltBase64: any(named: 'recoverySaltBase64'),
            encryptedPrivateKeyByRecoveryBase64: any(
              named: 'encryptedPrivateKeyByRecoveryBase64',
            ),
          ),
        ).thenAnswer((_) async {});
        return buildCubit();
      },
      act: (cubit) => cubit.validateAndProceed(validMnemonic),
      expect: () => [
        isA<RecoveryLoading>(),
        isA<RecoveryKeyValidated>().having(
          (s) => s.validatedMnemonic,
          'validatedMnemonic',
          validMnemonic,
        ),
      ],
    );

    blocTest<RecoveryCubit, RecoveryState>(
      'validateAndProceed emits Failed(WrongRecoveryKey) on crypto failure',
      build: () {
        when(
          () => datasource.getAccount(),
        ).thenAnswer((_) async => accountWithRecovery);
        when(
          () => crypto.validateRecoveryMnemonic(
            recoveryMnemonic: any(named: 'recoveryMnemonic'),
            recoverySaltBase64: any(named: 'recoverySaltBase64'),
            encryptedPrivateKeyByRecoveryBase64: any(
              named: 'encryptedPrivateKeyByRecoveryBase64',
            ),
          ),
        ).thenThrow(const WrongRecoveryKeyException());
        return buildCubit();
      },
      act: (cubit) => cubit.validateAndProceed(validMnemonic),
      expect: () => [
        isA<RecoveryLoading>(),
        isA<RecoveryFailed>().having(
          (s) => s.error,
          'error',
          isA<WrongRecoveryKeyException>(),
        ),
      ],
    );

    blocTest<RecoveryCubit, RecoveryState>(
      'validateAndProceed emits Failed(MaterialMissing) when account lacks recovery fields',
      build: () {
        when(
          () => datasource.getAccount(),
        ).thenAnswer((_) async => accountWithoutRecovery);
        return buildCubit();
      },
      act: (cubit) => cubit.validateAndProceed(validMnemonic),
      expect: () => [
        isA<RecoveryLoading>(),
        isA<RecoveryFailed>().having(
          (s) => s.error,
          'error',
          isA<RecoveryMaterialMissingException>(),
        ),
      ],
      verify: (_) {
        verifyNever(
          () => crypto.validateRecoveryMnemonic(
            recoveryMnemonic: any(named: 'recoveryMnemonic'),
            recoverySaltBase64: any(named: 'recoverySaltBase64'),
            encryptedPrivateKeyByRecoveryBase64: any(
              named: 'encryptedPrivateKeyByRecoveryBase64',
            ),
          ),
        );
      },
    );

    blocTest<RecoveryCubit, RecoveryState>(
      'validateAndProceed wraps DioException into RecoveryServerException',
      build: () {
        when(() => datasource.getAccount()).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/api/account'),
            type: DioExceptionType.connectionTimeout,
          ),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.validateAndProceed(validMnemonic),
      expect: () => [
        isA<RecoveryLoading>(),
        isA<RecoveryFailed>().having(
          (s) => s.error,
          'error',
          isA<RecoveryServerException>().having(
            (e) => e.kind,
            'kind',
            RecoveryServerErrorKind.serverNotResponding,
          ),
        ),
      ],
    );

    blocTest<RecoveryCubit, RecoveryState>(
      'completeRecovery is a no-op when state is not KeyValidated',
      build: buildCubit,
      act: (cubit) => cubit.completeRecovery('newPassword'),
      expect: () => const <RecoveryState>[],
      verify: (_) {
        verifyNever(() => datasource.getAccount());
      },
    );

    blocTest<RecoveryCubit, RecoveryState>(
      'completeRecovery proves key possession with a fresh session-bound challenge',
      build: () {
        stubPipeline();
        when(() => datasource.recoverAccount(any())).thenAnswer(
          (_) async => Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/account/recovery'),
            statusCode: 204,
          ),
        );
        return buildCubit();
      },
      act: recover,
      expect: () => [
        isA<RecoveryLoading>(),
        isA<RecoveryKeyValidated>(),
        isA<RecoveryLoading>(),
        isA<RecoveryCompleted>().having(
          (s) => s.newRecoveryMnemonic.length,
          'newRecoveryMnemonic.length',
          24,
        ),
      ],
      verify: (_) {
        verify(() => datasource.createRecoveryChallenge()).called(1);
        verify(
          () => crypto.recoverAccount(
            recoveryMnemonic: any(named: 'recoveryMnemonic'),
            newPassword: any(named: 'newPassword'),
            recoverySaltBase64: any(named: 'recoverySaltBase64'),
            encryptedPrivateKeyByRecoveryBase64: any(
              named: 'encryptedPrivateKeyByRecoveryBase64',
            ),
            accountId: accountWithRecovery.userId,
            sessionUserId: sessionUserId,
            sealedChallenge: sealedChallenge,
            baseCredentialRevision: any(named: 'baseCredentialRevision'),
            basePrivateKeyWrapRevision: any(
              named: 'basePrivateKeyWrapRevision',
            ),
          ),
        ).called(1);
        verify(() => datasource.recoverAccount(any())).called(1);
        expect(fakeResult.request.recoveryProof, everyElement(0));
      },
    );

    blocTest<RecoveryCubit, RecoveryState>(
      'completeRecovery maps a rejected recovery proof and wipes it',
      build: () {
        stubPipeline();
        when(() => datasource.recoverAccount(any())).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/api/account/recovery'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/account/recovery'),
              statusCode: 403,
              data: {'message': 'errors.backend.recovery-proof-invalid'},
            ),
          ),
        );
        return buildCubit();
      },
      act: recover,
      expect: () => [
        isA<RecoveryLoading>(),
        isA<RecoveryKeyValidated>(),
        isA<RecoveryLoading>(),
        isA<RecoveryFailed>().having(
          (s) => s.error,
          'error',
          isA<RecoveryServerException>().having(
            (e) => e.kind,
            'kind',
            RecoveryServerErrorKind.recoveryProofInvalid,
          ),
        ),
      ],
      verify: (_) {
        expect(fakeResult.request.recoveryProof, everyElement(0));
      },
    );

    blocTest<RecoveryCubit, RecoveryState>(
      'completeRecovery never uploads after a rejected challenge',
      build: () {
        stubPipeline();
        when(
          () => crypto.recoverAccount(
            recoveryMnemonic: any(named: 'recoveryMnemonic'),
            newPassword: any(named: 'newPassword'),
            recoverySaltBase64: any(named: 'recoverySaltBase64'),
            encryptedPrivateKeyByRecoveryBase64: any(
              named: 'encryptedPrivateKeyByRecoveryBase64',
            ),
            accountId: any(named: 'accountId'),
            sessionUserId: any(named: 'sessionUserId'),
            sealedChallenge: any(named: 'sealedChallenge'),
            baseCredentialRevision: any(named: 'baseCredentialRevision'),
            basePrivateKeyWrapRevision: any(
              named: 'basePrivateKeyWrapRevision',
            ),
          ),
        ).thenThrow(const RecoveryChallengeException());
        return buildCubit();
      },
      act: recover,
      expect: () => [
        isA<RecoveryLoading>(),
        isA<RecoveryKeyValidated>(),
        isA<RecoveryLoading>(),
        isA<RecoveryFailed>().having(
          (s) => s.error,
          'error',
          isA<RecoveryServerException>().having(
            (e) => e.kind,
            'kind',
            RecoveryServerErrorKind.invalidResponse,
          ),
        ),
      ],
      verify: (_) {
        verifyNever(() => datasource.recoverAccount(any()));
      },
    );

    blocTest<RecoveryCubit, RecoveryState>(
      'completeRecovery reports an account without a public key as missing material',
      build: () {
        stubPipeline();
        when(() => datasource.createRecoveryChallenge()).thenThrow(
          DioException(
            requestOptions: RequestOptions(
              path: '/api/account/recovery/challenge',
            ),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(
                path: '/api/account/recovery/challenge',
              ),
              statusCode: 404,
            ),
          ),
        );
        return buildCubit();
      },
      act: recover,
      expect: () => [
        isA<RecoveryLoading>(),
        isA<RecoveryKeyValidated>(),
        isA<RecoveryLoading>(),
        isA<RecoveryFailed>().having(
          (s) => s.error,
          'error',
          isA<RecoveryMaterialMissingException>(),
        ),
      ],
      verify: (_) {
        verifyNever(() => datasource.recoverAccount(any()));
      },
    );
  });
}
