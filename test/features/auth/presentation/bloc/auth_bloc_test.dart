import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_claw_vault/features/auth/data/models/auth_result_model.dart';
import 'package:mobile_claw_vault/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mobile_claw_vault/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_claw_vault/features/auth/presentation/bloc/auth_bloc.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = MockAuthRepository();
  });

  const authResult = AuthResultModel(
    accessToken: 'access-123',
    refreshToken: 'refresh-456',
    userId: 'user-789',
    isOnboarded: true,
  );

  group('AuthBloc', () {
    test('initial state is AuthInitial', () {
      final bloc = AuthBloc(authRepository: mockRepo);
      expect(bloc.state, isA<AuthInitial>());
      bloc.close();
    });

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] on successful Google login',
      build: () {
        when(() => mockRepo.loginWithGoogle())
            .thenAnswer((_) async => authResult);
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthLoginWithGoogle()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>()
            .having((s) => s.userId, 'userId', 'user-789')
            .having((s) => s.isOnboarded, 'isOnboarded', true),
      ],
      verify: (_) {
        verify(() => mockRepo.loginWithGoogle()).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] when Google login fails',
      build: () {
        when(() => mockRepo.loginWithGoogle())
            .thenThrow(Exception('Network error'));
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthLoginWithGoogle()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>().having(
          (s) => s.message,
          'message',
          contains('Network error'),
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthUnauthenticated] when user cancels Google sign-in',
      build: () {
        when(() => mockRepo.loginWithGoogle())
            .thenThrow(AuthCancelledException());
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthLoginWithGoogle()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthUnauthenticated] on logout',
      build: () {
        when(() => mockRepo.logout()).thenAnswer((_) async {});
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthLogoutRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>(),
      ],
      verify: (_) {
        verify(() => mockRepo.logout()).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthAuthenticated] when check finds stored session',
      build: () {
        when(() => mockRepo.isAuthenticated()).thenAnswer((_) async => true);
        when(() => mockRepo.getUserId()).thenAnswer((_) async => 'user-789');
        when(() => mockRepo.isOnboarded()).thenAnswer((_) async => true);
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [
        isA<AuthAuthenticated>()
            .having((s) => s.userId, 'userId', 'user-789')
            .having((s) => s.isOnboarded, 'isOnboarded', true),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthUnauthenticated] when check finds no stored session',
      build: () {
        when(() => mockRepo.isAuthenticated()).thenAnswer((_) async => false);
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [
        isA<AuthUnauthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthAuthenticated] on successful token refresh',
      build: () {
        when(() => mockRepo.refreshToken())
            .thenAnswer((_) async => authResult);
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthRefreshRequested()),
      expect: () => [
        isA<AuthAuthenticated>()
            .having((s) => s.userId, 'userId', 'user-789'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthUnauthenticated] when token refresh fails',
      build: () {
        when(() => mockRepo.refreshToken())
            .thenThrow(AuthNoRefreshTokenException());
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthRefreshRequested()),
      expect: () => [
        isA<AuthUnauthenticated>(),
      ],
    );
  });
}
