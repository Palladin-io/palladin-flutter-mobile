import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mobile_palladin/features/unlock/data/services/unlock_crypto_service.dart';
import 'package:mobile_palladin/features/unlock/domain/unlock_exceptions.dart';
import 'package:mobile_palladin/features/unlock/presentation/cubit/unlock_cubit.dart';

class _MockAccountDatasource extends Mock implements AccountRemoteDatasource {}

class _MockCryptoService extends Mock implements UnlockCryptoService {}

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

class _MockLocalAuth extends Mock implements LocalAuthentication {}

void main() {
  late _MockAccountDatasource datasource;
  late _MockCryptoService crypto;
  late _MockSecureStorage storage;
  late _MockLocalAuth auth;

  final masterKey = Uint8List.fromList(List.filled(32, 0xAA));
  final privateKey = Uint8List.fromList(List.filled(32, 0xBB));
  final accountResponse = const AccountResponse(
    salt: 'c2FsdC1pcy1zaXh0ZWVuISE=', // 16 bytes of arbitrary base64
    encryptedPrivateKey: 'ZW5jcnlwdGVk',
  );

  setUpAll(() {
    registerFallbackValue(const IOSOptions());
    registerFallbackValue(const AndroidOptions());
    registerFallbackValue(const AuthenticationOptions());
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    datasource = _MockAccountDatasource();
    crypto = _MockCryptoService();
    storage = _MockSecureStorage();
    auth = _MockLocalAuth();
  });

  /// Stub `secureStorage.write` with a success response. Kept per-test
  /// because mocktail's `any(named: ...)` matchers leak across `when`
  /// blocks if declared in a shared setUp.
  void stubStorageWriteSuccess() {
    when(() => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        )).thenAnswer((_) async {});
  }

  UnlockCubit buildCubit() => UnlockCubit(
        datasource: datasource,
        cryptoService: crypto,
        secureStorage: storage,
        localAuth: auth,
      );

  group('UnlockCubit', () {
    test('initial state is UnlockInitial', () {
      final cubit = buildCubit();
      expect(cubit.state, isA<UnlockInitial>());
      cubit.close();
    });

    blocTest<UnlockCubit, UnlockState>(
      'unlock emits [Loading, Success] and stashes MK on correct password',
      build: () {
        stubStorageWriteSuccess();
        when(() => datasource.getAccount())
            .thenAnswer((_) async => accountResponse);
        when(() => crypto.deriveAndDecrypt(
              masterPassword: any(named: 'masterPassword'),
              saltBase64: any(named: 'saltBase64'),
              encryptedPrivateKeyBase64:
                  any(named: 'encryptedPrivateKeyBase64'),
            )).thenAnswer((_) async => UnlockResult(
              masterKey: masterKey,
              privateKey: privateKey,
            ));
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
        verify(() => storage.write(
              key: 'vault_mk',
              value: base64.encode(masterKey),
              iOptions: any(named: 'iOptions'),
              aOptions: any(named: 'aOptions'),
            )).called(1);
      },
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlock still succeeds when MK persistence fails',
      build: () {
        when(() => datasource.getAccount())
            .thenAnswer((_) async => accountResponse);
        when(() => crypto.deriveAndDecrypt(
              masterPassword: any(named: 'masterPassword'),
              saltBase64: any(named: 'saltBase64'),
              encryptedPrivateKeyBase64:
                  any(named: 'encryptedPrivateKeyBase64'),
            )).thenAnswer((_) async => UnlockResult(
              masterKey: masterKey,
              privateKey: privateKey,
            ));
        when(() => storage.write(
              key: any(named: 'key'),
              value: any(named: 'value'),
              iOptions: any(named: 'iOptions'),
              aOptions: any(named: 'aOptions'),
            )).thenThrow(Exception('keychain unavailable'));
        return buildCubit();
      },
      act: (cubit) => cubit.unlock('pw'),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockSuccess>(),
      ],
    );

    blocTest<UnlockCubit, UnlockState>(
      'unlock emits [Loading, Failed] on wrong master password',
      build: () {
        when(() => datasource.getAccount())
            .thenAnswer((_) async => accountResponse);
        when(() => crypto.deriveAndDecrypt(
              masterPassword: any(named: 'masterPassword'),
              saltBase64: any(named: 'saltBase64'),
              encryptedPrivateKeyBase64:
                  any(named: 'encryptedPrivateKeyBase64'),
            )).thenThrow(const WrongMasterPasswordException());
        return buildCubit();
      },
      act: (cubit) => cubit.unlock('wrong'),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockFailed>()
            .having((s) => s.error, 'error', isA<WrongMasterPasswordException>()),
      ],
      verify: (_) {
        verifyNever(() => storage.write(
              key: any(named: 'key'),
              value: any(named: 'value'),
              iOptions: any(named: 'iOptions'),
              aOptions: any(named: 'aOptions'),
            ));
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
      'unlockWithBiometrics emits Failed when no MK is stashed',
      build: () {
        when(() => storage.containsKey(
              key: any(named: 'key'),
              iOptions: any(named: 'iOptions'),
              aOptions: any(named: 'aOptions'),
            )).thenAnswer((_) async => false);
        return buildCubit();
      },
      act: (cubit) =>
          cubit.unlockWithBiometrics(localizedReason: 'reason'),
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
      'unlockWithBiometrics emits Failed when OS auth refuses',
      build: () {
        when(() => storage.containsKey(
              key: any(named: 'key'),
              iOptions: any(named: 'iOptions'),
              aOptions: any(named: 'aOptions'),
            )).thenAnswer((_) async => true);
        when(() => auth.authenticate(
              localizedReason: any(named: 'localizedReason'),
              options: any(named: 'options'),
            )).thenAnswer((_) async => false);
        return buildCubit();
      },
      act: (cubit) =>
          cubit.unlockWithBiometrics(localizedReason: 'reason'),
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
      'unlockWithBiometrics emits Success with viaBiometrics=true on happy path',
      build: () {
        when(() => storage.containsKey(
              key: any(named: 'key'),
              iOptions: any(named: 'iOptions'),
              aOptions: any(named: 'aOptions'),
            )).thenAnswer((_) async => true);
        when(() => storage.read(
              key: any(named: 'key'),
              iOptions: any(named: 'iOptions'),
              aOptions: any(named: 'aOptions'),
            )).thenAnswer((_) async => base64.encode(masterKey));
        when(() => auth.authenticate(
              localizedReason: any(named: 'localizedReason'),
              options: any(named: 'options'),
            )).thenAnswer((_) async => true);
        when(() => datasource.getAccount())
            .thenAnswer((_) async => accountResponse);
        when(() => crypto.decryptWithMasterKey(
              masterKey: any(named: 'masterKey'),
              encryptedPrivateKeyBase64:
                  any(named: 'encryptedPrivateKeyBase64'),
            )).thenAnswer((_) async => UnlockResult(
              masterKey: masterKey,
              privateKey: privateKey,
            ));
        return buildCubit();
      },
      act: (cubit) =>
          cubit.unlockWithBiometrics(localizedReason: 'reason'),
      expect: () => [
        isA<UnlockLoading>(),
        isA<UnlockSuccess>()
            .having((s) => s.viaBiometrics, 'viaBiometrics', true)
            .having((s) => s.privateKey, 'privateKey', privateKey),
      ],
    );
  });
}
