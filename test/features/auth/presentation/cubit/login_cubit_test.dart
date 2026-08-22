import 'dart:typed_data';

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

void main() {
  late _MockPasswordAuthDatasource datasource;
  late _MockIdentityKdfService identityKdfService;
  late _MockAccountDatasource accountDatasource;
  late _MockUnlockCryptoService unlockCryptoService;
  late _MockTokenStorage tokenStorage;

  const accountId = '00112233-4455-4677-8899-aabbccddeeff';
  const bootstrap = LoginKdfBootstrap(
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
  });

  setUp(() {
    datasource = _MockPasswordAuthDatasource();
    identityKdfService = _MockIdentityKdfService();
    accountDatasource = _MockAccountDatasource();
    unlockCryptoService = _MockUnlockCryptoService();
    tokenStorage = _MockTokenStorage();

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
      () => datasource.login(
        email: any(named: 'email'),
        authCredential: any(named: 'authCredential'),
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
    when(
      () => datasource.fetchLoginKdf(any(), profileId: any(named: 'profileId')),
    ).thenAnswer(
      (_) async => const LoginKdfBootstrap(
        accountId: null,
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
        accountId: '00000000-0000-4000-8000-000000000000',
        kdfSalt: any(named: 'kdfSalt'),
      ),
    ).called(1);
    verify(
      () => datasource.login(
        email: 'unknown@example.com',
        authCredential: any(named: 'authCredential'),
      ),
    ).called(1);
  });
}
