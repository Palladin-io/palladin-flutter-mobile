import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/auth/data/datasources/password_auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/data/models/auth_result_model.dart';
import 'package:mobile_palladin/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/verify_email_cubit.dart';

class MockPasswordAuthRemoteDatasource extends Mock
    implements PasswordAuthRemoteDatasource {}

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockPasswordAuthRemoteDatasource datasource;
  late MockAuthRepository authRepository;

  const refreshedSession = AuthResultModel(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    userId: 'user-id',
    isOnboarded: true,
  );

  setUp(() {
    datasource = MockPasswordAuthRemoteDatasource();
    authRepository = MockAuthRepository();
  });

  VerifyEmailCubit buildCubit() =>
      VerifyEmailCubit(datasource: datasource, authRepository: authRepository);

  group('checkAgain', () {
    blocTest<VerifyEmailCubit, VerifyEmailState>(
      'emits checking then verified when the refreshed claim is true',
      build: () {
        when(
          () => authRepository.refreshToken(),
        ).thenAnswer((_) async => refreshedSession);
        when(
          () => authRepository.isEmailVerified(),
        ).thenAnswer((_) async => true);
        return buildCubit();
      },
      act: (cubit) => cubit.checkAgain(),
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
    );

    blocTest<VerifyEmailCubit, VerifyEmailState>(
      'emits checking then pending when verification is incomplete',
      build: () {
        when(
          () => authRepository.refreshToken(),
        ).thenAnswer((_) async => refreshedSession);
        when(
          () => authRepository.isEmailVerified(),
        ).thenAnswer((_) async => false);
        return buildCubit();
      },
      act: (cubit) => cubit.checkAgain(),
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
    );

    blocTest<VerifyEmailCubit, VerifyEmailState>(
      'emits checking then error without changing the auth session on failure',
      build: () {
        when(
          () => authRepository.refreshToken(),
        ).thenThrow(Exception('network unavailable'));
        return buildCubit();
      },
      act: (cubit) => cubit.checkAgain(),
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
