import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/auth/data/datasources/password_auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/verify_email_cubit.dart';
import 'package:mobile_palladin/features/onboarding/data/services/default_vault_provisioner.dart';

class MockPasswordAuthRemoteDatasource extends Mock
    implements PasswordAuthRemoteDatasource {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockDefaultVaultProvisioner extends Mock
    implements DefaultVaultProvisioner {}

void main() {
  late MockPasswordAuthRemoteDatasource datasource;
  late MockAuthRepository authRepository;
  late MockDefaultVaultProvisioner defaultVaultProvisioner;
  final privateKey = Uint8List.fromList(List.filled(32, 7));

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    datasource = MockPasswordAuthRemoteDatasource();
    authRepository = MockAuthRepository();
    defaultVaultProvisioner = MockDefaultVaultProvisioner();
  });

  VerifyEmailCubit buildCubit() => VerifyEmailCubit(
    datasource: datasource,
    authRepository: authRepository,
    defaultVaultProvisioner: defaultVaultProvisioner,
  );

  group('checkAgain', () {
    blocTest<VerifyEmailCubit, VerifyEmailState>(
      'emits checking then verified when the refreshed claim is true',
      build: () {
        when(() => authRepository.refreshToken()).thenAnswer((_) async {});
        when(
          () => authRepository.isEmailVerified(),
        ).thenAnswer((_) async => true);
        when(
          () => defaultVaultProvisioner.ensureFromPrivateKey(
            privateKey: any(named: 'privateKey'),
            name: any(named: 'name'),
          ),
        ).thenAnswer((_) async {});
        return buildCubit();
      },
      act: (cubit) => cubit.checkAgain(
        privateKey: privateKey,
        defaultVaultName: 'Personal',
      ),
      expect: () => [
        isA<VerifyEmailState>().having(
          (state) => state.check,
          'check',
          VerificationCheckStatus.checking,
        ),
        isA<VerifyEmailState>().having(
          (state) => state.check,
          'check',
          VerificationCheckStatus.verified,
        ),
      ],
      verify: (_) {
        verify(
          () => defaultVaultProvisioner.ensureFromPrivateKey(
            privateKey: privateKey,
            name: 'Personal',
          ),
        ).called(1);
      },
    );

    blocTest<VerifyEmailCubit, VerifyEmailState>(
      'emits checking then pending when verification is incomplete',
      build: () {
        when(() => authRepository.refreshToken()).thenAnswer((_) async {});
        when(
          () => authRepository.isEmailVerified(),
        ).thenAnswer((_) async => false);
        return buildCubit();
      },
      act: (cubit) => cubit.checkAgain(
        privateKey: privateKey,
        defaultVaultName: 'Personal',
      ),
      expect: () => [
        isA<VerifyEmailState>().having(
          (state) => state.check,
          'check',
          VerificationCheckStatus.checking,
        ),
        isA<VerifyEmailState>().having(
          (state) => state.check,
          'check',
          VerificationCheckStatus.pending,
        ),
      ],
      verify: (_) {
        verifyNever(
          () => defaultVaultProvisioner.ensureFromPrivateKey(
            privateKey: any(named: 'privateKey'),
            name: any(named: 'name'),
          ),
        );
      },
    );

    blocTest<VerifyEmailCubit, VerifyEmailState>(
      'emits checking then error without changing the auth session on failure',
      build: () {
        when(
          () => authRepository.refreshToken(),
        ).thenThrow(Exception('network unavailable'));
        return buildCubit();
      },
      act: (cubit) => cubit.checkAgain(
        privateKey: privateKey,
        defaultVaultName: 'Personal',
      ),
      expect: () => [
        isA<VerifyEmailState>().having(
          (state) => state.check,
          'check',
          VerificationCheckStatus.checking,
        ),
        isA<VerifyEmailState>().having(
          (state) => state.check,
          'check',
          VerificationCheckStatus.error,
        ),
      ],
      verify: (_) {
        verifyNever(() => authRepository.isEmailVerified());
      },
    );
  });
}
