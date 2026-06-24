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
    salt: 'c2FsdC1pcy1zaXh0ZWVuISE=',
    encryptedPrivateKey: 'ZW5jcnlwdGVk',
    recoverySalt: 'cmVjb3Zlcnktc2FsdC0xNiE=',
    encryptedPrivateKeyByRecovery: 'cmVjLWVuY3J5cHRlZA==',
  );

  final accountWithoutRecovery = const AccountResponse(
    salt: 'c2FsdC1pcy1zaXh0ZWVuISE=',
    encryptedPrivateKey: 'ZW5jcnlwdGVk',
  );

  final fakeRequest = RecoverAccountRequest(
    newSalt: Uint8List(16),
    newEncryptedPrivateKey: Uint8List(48),
    newRecoverySalt: Uint8List(16),
    newEncryptedPrivateKeyByRecovery: Uint8List(48),
  );

  final fakeResult = RecoveryResult(
    request: fakeRequest,
    newRecoveryMnemonic: List<String>.generate(24, (i) => 'word${i + 1}'),
  );

  setUpAll(() {
    registerFallbackValue(fakeRequest);
  });

  setUp(() {
    datasource = _MockDatasource();
    crypto = _MockCrypto();
  });

  RecoveryCubit buildCubit() => RecoveryCubit(
        datasource: datasource,
        cryptoService: crypto,
      );

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
        when(() => datasource.getAccount())
            .thenAnswer((_) async => accountWithRecovery);
        when(() => crypto.validateRecoveryMnemonic(
              recoveryMnemonic: any(named: 'recoveryMnemonic'),
              recoverySaltBase64: any(named: 'recoverySaltBase64'),
              encryptedPrivateKeyByRecoveryBase64:
                  any(named: 'encryptedPrivateKeyByRecoveryBase64'),
            )).thenAnswer((_) async {});
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
        when(() => datasource.getAccount())
            .thenAnswer((_) async => accountWithRecovery);
        when(() => crypto.validateRecoveryMnemonic(
              recoveryMnemonic: any(named: 'recoveryMnemonic'),
              recoverySaltBase64: any(named: 'recoverySaltBase64'),
              encryptedPrivateKeyByRecoveryBase64:
                  any(named: 'encryptedPrivateKeyByRecoveryBase64'),
            )).thenThrow(const WrongRecoveryKeyException());
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
        when(() => datasource.getAccount())
            .thenAnswer((_) async => accountWithoutRecovery);
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
        verifyNever(() => crypto.validateRecoveryMnemonic(
              recoveryMnemonic: any(named: 'recoveryMnemonic'),
              recoverySaltBase64: any(named: 'recoverySaltBase64'),
              encryptedPrivateKeyByRecoveryBase64:
                  any(named: 'encryptedPrivateKeyByRecoveryBase64'),
            ));
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
      'completeRecovery runs full pipeline and emits Completed on success',
      build: () {
        when(() => datasource.getAccount())
            .thenAnswer((_) async => accountWithRecovery);
        when(() => crypto.validateRecoveryMnemonic(
              recoveryMnemonic: any(named: 'recoveryMnemonic'),
              recoverySaltBase64: any(named: 'recoverySaltBase64'),
              encryptedPrivateKeyByRecoveryBase64:
                  any(named: 'encryptedPrivateKeyByRecoveryBase64'),
            )).thenAnswer((_) async {});
        when(() => crypto.recoverAccount(
              recoveryMnemonic: any(named: 'recoveryMnemonic'),
              newPassword: any(named: 'newPassword'),
              recoverySaltBase64: any(named: 'recoverySaltBase64'),
              encryptedPrivateKeyByRecoveryBase64:
                  any(named: 'encryptedPrivateKeyByRecoveryBase64'),
            )).thenAnswer((_) async => fakeResult);
        when(() => datasource.recoverAccount(any())).thenAnswer(
          (_) async => Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/account/recovery'),
            statusCode: 204,
          ),
        );
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.validateAndProceed(validMnemonic);
        await cubit.completeRecovery('newMasterPassword!');
      },
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
        verify(() => datasource.recoverAccount(any())).called(1);
      },
    );

    blocTest<RecoveryCubit, RecoveryState>(
      'completeRecovery surfaces server error on PUT failure',
      build: () {
        when(() => datasource.getAccount())
            .thenAnswer((_) async => accountWithRecovery);
        when(() => crypto.validateRecoveryMnemonic(
              recoveryMnemonic: any(named: 'recoveryMnemonic'),
              recoverySaltBase64: any(named: 'recoverySaltBase64'),
              encryptedPrivateKeyByRecoveryBase64:
                  any(named: 'encryptedPrivateKeyByRecoveryBase64'),
            )).thenAnswer((_) async {});
        when(() => crypto.recoverAccount(
              recoveryMnemonic: any(named: 'recoveryMnemonic'),
              newPassword: any(named: 'newPassword'),
              recoverySaltBase64: any(named: 'recoverySaltBase64'),
              encryptedPrivateKeyByRecoveryBase64:
                  any(named: 'encryptedPrivateKeyByRecoveryBase64'),
            )).thenAnswer((_) async => fakeResult);
        when(() => datasource.recoverAccount(any())).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/api/account/recovery'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/account/recovery'),
              statusCode: 500,
            ),
          ),
        );
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.validateAndProceed(validMnemonic);
        await cubit.completeRecovery('newMasterPassword!');
      },
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
    );
  });
}
