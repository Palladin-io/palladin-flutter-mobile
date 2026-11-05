import 'dart:typed_data';
import 'package:mobile_palladin/core/storage/account_secret_store.dart';
import 'package:mobile_palladin/core/storage/biometric_key_store.dart';
import 'package:mobile_palladin/features/auth/data/models/password_session_model.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/auth/data/datasources/password_auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/data/models/login_response.dart';
import 'package:mobile_palladin/features/auth/domain/password_auth_exceptions.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/login_cubit.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';
import 'package:mobile_palladin/features/unlock/data/services/unlock_crypto_service.dart';

class _MockPasswordAuthDatasource extends Mock
    implements PasswordAuthRemoteDatasource {}

class _MockIdentityKdfService extends Mock implements IdentityKdfService {}

class _MockAccountDatasource extends Mock implements AccountRemoteDatasource {}

class _MockUnlockCryptoService extends Mock implements UnlockCryptoService {}

class _MockTokenStorage extends Mock implements SecureTokenStorage {}

class _Keys extends Mock implements BiometricKeyStore {}

class _Secrets extends Mock implements AccountSecretStore {}

void main() {
  late _MockPasswordAuthDatasource datasource;
  late _MockIdentityKdfService identityKdfService;
  late _MockAccountDatasource accountDatasource;
  late _MockUnlockCryptoService unlockCryptoService;
  late _MockTokenStorage tokenStorage;
  late _Keys keys;
  late _Secrets secrets;

  const accountId = '00112233-4455-4677-8899-aabbccddeeff';
  const bootstrap = LoginKdfBootstrap(
    accountId: accountId,
    profileId: IdentityKdfProfileV2.id,
    securityVersion: IdentityKdfProfileV2.securityVersion,
    kdfSalt: 'AAECAwQFBgcICQoLDA0ODw',
    memoryKiB: IdentityKdfProfileV2.memoryKiB,
    iterations: IdentityKdfProfileV2.iterations,
    parallelism: IdentityKdfProfileV2.parallelism,
  );
  const legacyBootstrap = LoginKdfBootstrap(
    accountId: accountId,
    profileId: IdentityKdfProfile.id,
    securityVersion: IdentityKdfProfile.securityVersion,
    kdfSalt: 'AAECAwQFBgcICQoLDA0ODw',
    memoryKiB: IdentityKdfProfile.memoryKiB,
    iterations: IdentityKdfProfile.iterations,
    parallelism: IdentityKdfProfile.parallelism,
  );

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(IdentityKdfVersion.accountSecretV2);
    registerFallbackValue(
      const BiometricPromptCopy(
        promptTitle: "dummy",
        enrollTitle: "dummy",
        accessTitle: "dummy",
        cancelLabel: "dummy",
      ),
    );
  });

  setUp(() {
    datasource = _MockPasswordAuthDatasource();
    identityKdfService = _MockIdentityKdfService();
    accountDatasource = _MockAccountDatasource();
    unlockCryptoService = _MockUnlockCryptoService();
    tokenStorage = _MockTokenStorage();
    keys = _Keys();
    secrets = _Secrets();
    when(
      () => secrets.read(any()),
    ).thenAnswer((_) async => Uint8List.fromList(List.filled(32, 5)));
    when(() => secrets.write(any(), any())).thenAnswer((_) async {});
    when(() => keys.generation).thenReturn(0);
    when(() => keys.purgeLegacyRawKey()).thenAnswer((_) async {});
    when(() => keys.isEnrolled()).thenAnswer((_) async => false);
    when(() => keys.canStore()).thenAnswer((_) async => true);
    when(
      () => keys.enroll(
        any(),
        any(),
        expectedGeneration: any(named: "expectedGeneration"),
      ),
    ).thenAnswer((_) async {});

    when(
      () => datasource.fetchLoginKdf(any(), profileId: any(named: 'profileId')),
    ).thenAnswer((_) async => bootstrap);
    when(
      () => identityKdfService.derive(
        password: any(named: 'password'),
        accountId: any(named: 'accountId'),
        kdfSalt: any(named: 'kdfSalt'),
      ),
    ).thenAnswer(
      (_) async => IdentityKdfOutputs(
        authCredential: Uint8List(32),
        masterKey: Uint8List.fromList(List.filled(32, 7)),
      ),
    );
    when(
      () => identityKdfService.deriveV2(
        password: any(named: 'password'),
        accountId: any(named: 'accountId'),
        kdfSalt: any(named: 'kdfSalt'),
        accountSecret: any(named: 'accountSecret'),
      ),
    ).thenAnswer(
      (_) async => IdentityKdfOutputs(
        authCredential: Uint8List(32),
        masterKey: Uint8List.fromList(List.filled(32, 7)),
      ),
    );
    when(
      () => datasource.login(
        email: any(named: 'email'),
        authCredential: any(named: 'authCredential'),
        kdfVersion: any(named: 'kdfVersion'),
      ),
    ).thenAnswer(
      (_) async => const LoginTotpRequired(challengeToken: 'challenge-1'),
    );
    when(
      () => datasource.loginTotp(
        challengeToken: any(named: 'challengeToken'),
        code: any(named: 'code'),
      ),
    ).thenThrow(const LoginRateLimitedException(retryAfterSeconds: 60));
  });

  LoginCubit buildCubit() => LoginCubit(
    datasource: datasource,
    identityKdfService: identityKdfService,
    accountDatasource: accountDatasource,
    unlockCryptoService: unlockCryptoService,
    tokenStorage: tokenStorage,
    keyStore: keys,
    accountSecrets: secrets,
  );

  test(
    'password login completes without requesting biometric enrollment',
    () async {
      when(
        () => datasource.login(
          email: any(named: 'email'),
          authCredential: any(named: 'authCredential'),
          kdfVersion: any(named: 'kdfVersion'),
        ),
      ).thenAnswer(
        (_) async => const LoginSession(
          PasswordSessionModel(
            accessToken: 'dummy',
            refreshToken: 'dummy',
            userId: accountId,
            isOnboarded: true,
            emailVerified: true,
          ),
        ),
      );
      when(
        () => tokenStorage.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
          userId: any(named: 'userId'),
          isOnboarded: any(named: 'isOnboarded'),
        ),
      ).thenAnswer((_) async {});
      when(() => tokenStorage.setAuthProvider(any())).thenAnswer((_) async {});
      when(() => accountDatasource.getAccount()).thenAnswer(
        (_) async => const AccountResponse(
          userId: accountId,
          encryptedPrivateKey: 'dummy',
        ),
      );
      final mk = Uint8List.fromList(List.filled(32, 9));
      when(
        () => unlockCryptoService.decryptWithMasterKey(
          masterKey: any(named: 'masterKey'),
          encryptedPrivateKeyBase64: any(named: 'encryptedPrivateKeyBase64'),
        ),
      ).thenAnswer(
        (_) async => UnlockResult(masterKey: mk, privateKey: Uint8List(32)),
      );
      final cubit = buildCubit();
      addTearDown(() async {
        if (!cubit.isClosed) await cubit.close();
      });
      final loggingIn = cubit.login(
        email: 'member@example.com',
        password: 'dummy',
      );
      await loggingIn;
      expect(cubit.state, isA<LoginSuccess>());
      verifyNever(
        () => keys.enroll(
          any(),
          any(),
          expectedGeneration: any(named: 'expectedGeneration'),
        ),
      );
    },
  );
  blocTest<LoginCubit, LoginState>(
    'keeps the in-memory TOTP challenge retryable after a 429',
    build: buildCubit,
    act: (cubit) async {
      await cubit.login(email: 'member@example.com', password: 'password');
      await cubit.submitTotp('123456');
      await cubit.submitTotp('654321');
    },
    expect: () => [
      isA<LoginLoading>(),
      isA<LoginTotpChallenge>(),
      isA<LoginTotpVerifying>(),
      isA<LoginTotpChallenge>().having(
        (state) => state.error,
        'error',
        isA<LoginRateLimitedException>().having(
          (error) => error.retryAfterSeconds,
          'retryAfterSeconds',
          60,
        ),
      ),
      isA<LoginTotpVerifying>(),
      isA<LoginTotpChallenge>().having(
        (state) => state.error,
        'error',
        isA<LoginRateLimitedException>(),
      ),
    ],
    verify: (_) {
      verify(
        () => datasource.loginTotp(
          challengeToken: 'challenge-1',
          code: any(named: 'code'),
        ),
      ).called(2);
    },
  );

  test('unknown account still performs the KDF and backend login', () async {
    const pseudoAccountId = 'ffeeddcc-bbaa-4a99-8877-665544332211';
    when(() => secrets.read(any())).thenAnswer((_) async => null);
    when(
      () => datasource.fetchLoginKdf(any(), profileId: any(named: 'profileId')),
    ).thenAnswer(
      (_) async => const LoginKdfBootstrap(
        accountId: pseudoAccountId,
        profileId: IdentityKdfProfile.id,
        securityVersion: IdentityKdfProfile.securityVersion,
        kdfSalt: 'AAECAwQFBgcICQoLDA0ODw',
        memoryKiB: IdentityKdfProfile.memoryKiB,
        iterations: IdentityKdfProfile.iterations,
        parallelism: IdentityKdfProfile.parallelism,
      ),
    );
    when(
      () => datasource.login(
        email: any(named: 'email'),
        authCredential: any(named: 'authCredential'),
        kdfVersion: any(named: 'kdfVersion'),
      ),
    ).thenThrow(const InvalidCredentialsException());
    final cubit = buildCubit();
    addTearDown(cubit.close);

    await cubit.login(email: 'unknown@example.com', password: 'password');

    expect(
      cubit.state,
      isA<LoginFailure>().having(
        (state) => state.error,
        'error',
        isA<InvalidCredentialsException>(),
      ),
    );
    verify(
      () => identityKdfService.derive(
        password: 'password',
        accountId: pseudoAccountId,
        kdfSalt: any(named: 'kdfSalt'),
      ),
    ).called(1);
    verify(
      () => datasource.login(
        email: 'unknown@example.com',
        authCredential: any(named: 'authCredential'),
        kdfVersion: any(named: 'kdfVersion'),
      ),
    ).called(1);
  });

  void stubSession() {
    when(
      () => datasource.login(
        email: any(named: 'email'),
        authCredential: any(named: 'authCredential'),
        kdfVersion: any(named: 'kdfVersion'),
      ),
    ).thenAnswer(
      (_) async => const LoginSession(
        PasswordSessionModel(
          accessToken: 'dummy',
          refreshToken: 'dummy',
          userId: accountId,
          isOnboarded: true,
          emailVerified: true,
        ),
      ),
    );
    when(
      () => tokenStorage.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
        userId: any(named: 'userId'),
        isOnboarded: any(named: 'isOnboarded'),
      ),
    ).thenAnswer((_) async {});
    when(() => tokenStorage.setAuthProvider(any())).thenAnswer((_) async {});
    when(() => accountDatasource.getAccount()).thenAnswer(
      (_) async =>
          const AccountResponse(userId: accountId, encryptedPrivateKey: 'x'),
    );
    when(
      () => unlockCryptoService.decryptWithMasterKey(
        masterKey: any(named: 'masterKey'),
        encryptedPrivateKeyBase64: any(named: 'encryptedPrivateKeyBase64'),
      ),
    ).thenAnswer(
      (_) async =>
          UnlockResult(masterKey: Uint8List(32), privateKey: Uint8List(32)),
    );
  }

  test('a missing Secret Key pauses before any KDF or login', () async {
    when(() => secrets.read(accountId)).thenAnswer((_) async => null);
    final stored = <Uint8List>[];
    when(() => secrets.write(any(), any())).thenAnswer((call) async {
      stored.add(Uint8List.fromList(call.positionalArguments[1] as Uint8List));
    });
    stubSession();
    final cubit = buildCubit();
    addTearDown(cubit.close);

    await cubit.login(email: 'member@example.com', password: 'password');

    expect(
      cubit.state,
      isA<LoginSecretKeyRequired>().having(
        (state) => state.accountId,
        'accountId',
        accountId,
      ),
    );
    verifyNever(
      () => identityKdfService.deriveV2(
        password: any(named: 'password'),
        accountId: any(named: 'accountId'),
        kdfSalt: any(named: 'kdfSalt'),
        accountSecret: any(named: 'accountSecret'),
      ),
    );

    final received = Uint8List.fromList(List.filled(32, 3));
    await cubit.continueWithSecretKey(received);

    expect(cubit.state, isA<LoginSuccess>());
    expect(stored, [Uint8List.fromList(List.filled(32, 3))]);
    expect(received, everyElement(0));
  });

  test('a rejected received Secret Key is never stored', () async {
    when(() => secrets.read(accountId)).thenAnswer((_) async => null);
    when(
      () => datasource.login(
        email: any(named: 'email'),
        authCredential: any(named: 'authCredential'),
        kdfVersion: any(named: 'kdfVersion'),
      ),
    ).thenThrow(const InvalidCredentialsException());
    final cubit = buildCubit();
    addTearDown(cubit.close);

    await cubit.login(email: 'member@example.com', password: 'password');
    await cubit.continueWithSecretKey(Uint8List(32));

    expect(cubit.state, isA<LoginFailure>());
    verifyNever(() => secrets.write(any(), any()));
  });

  test(
    'a version-1 account signs in locked so unlock runs the upgrade',
    () async {
      when(
        () =>
            datasource.fetchLoginKdf(any(), profileId: any(named: 'profileId')),
      ).thenAnswer((_) async => legacyBootstrap);
      stubSession();
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.login(email: 'member@example.com', password: 'password');

      expect(cubit.state, isA<LoginSucceededLocked>());
      verify(
        () => datasource.login(
          email: 'member@example.com',
          authCredential: any(named: 'authCredential'),
          kdfVersion: IdentityKdfVersion.passwordV1,
        ),
      ).called(1);
      verifyNever(() => accountDatasource.getAccount());
    },
  );
}
