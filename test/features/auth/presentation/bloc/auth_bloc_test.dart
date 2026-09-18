import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/auth/data/models/auth_result_model.dart';
import 'package:mobile_palladin/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mobile_palladin/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository mockRepo;
  late VaultSessionStore vaultSessionStore;

  setUp(() {
    mockRepo = MockAuthRepository();
    vaultSessionStore = VaultSessionStore()..setMemberPrivateKey(Uint8List(32));
    // Default permissions / email stubs — most tests don't care about
    // the value but every successful auth path queries them. Override
    // per test when a specific bitmask or identity matters.
    when(() => mockRepo.getPermissions()).thenAnswer((_) async => 0);
    when(() => mockRepo.getUserId()).thenAnswer((_) async => 'user-789');
    when(() => mockRepo.isOnboarded()).thenAnswer((_) async => true);
    when(() => mockRepo.getEmail()).thenAnswer((_) async => null);
    when(() => mockRepo.isEmailVerified()).thenAnswer((_) async => true);
    when(() => mockRepo.getAuthProvider()).thenAnswer((_) async => null);
  });

  const authResult = AuthResultModel(
    accessToken: 'access-123',
    refreshToken: 'refresh-456',
    userId: 'user-789',
    isOnboarded: true,
  );

  group('AuthBloc', () {
    blocTest<AuthBloc, AuthState>(
      'new OAuth accounts still require setup',
      build: () {
        when(() => mockRepo.loginWithGoogle()).thenAnswer(
          (_) async => const AuthResultModel(
            accessToken: 'access',
            refreshToken: 'refresh',
            userId: 'user-789',
            isOnboarded: false,
            isNewUser: true,
          ),
        );
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthLoginWithGoogle()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>().having(
          (state) => state.isOnboarded,
          'setup required',
          false,
        ),
      ],
    );
    blocTest<AuthBloc, AuthState>(
      'password registration retains the email verification gate',
      build: () {
        when(() => mockRepo.isEmailVerified()).thenAnswer((_) async => false);
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(
        PasswordSessionEstablished(
          masterKey: Uint8List(32),
          privateKey: Uint8List(32),
        ),
      ),
      expect: () => [
        isA<AuthAuthenticated>().having(
          (state) => state.emailVerified,
          'verification required',
          false,
        ),
      ],
    );
    test('initial state is AuthInitial', () {
      final bloc = AuthBloc(authRepository: mockRepo);
      expect(bloc.state, isA<AuthInitial>());
      bloc.close();
    });

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] on successful Google login',
      build: () {
        when(
          () => mockRepo.loginWithGoogle(),
        ).thenAnswer((_) async => authResult);
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
        when(
          () => mockRepo.loginWithGoogle(),
        ).thenThrow(Exception('Network error'));
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthLoginWithGoogle()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>().having(
          (s) => s.error.toString(),
          'error',
          contains('Network error'),
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthUnauthenticated] when user cancels Google sign-in',
      build: () {
        when(
          () => mockRepo.loginWithGoogle(),
        ).thenThrow(AuthCancelledException());
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthLoginWithGoogle()),
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthUnauthenticated] on logout',
      build: () {
        when(() => mockRepo.logout()).thenAnswer((_) async {});
        return AuthBloc(
          authRepository: mockRepo,
          vaultSessionStore: vaultSessionStore,
        );
      },
      act: (bloc) => bloc.add(const AuthLogoutRequested()),
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
      verify: (_) {
        verify(() => mockRepo.logout()).called(1);
        expect(
          vaultSessionStore.copyMemberPrivateKey,
          throwsA(isA<StateError>()),
        );
      },
    );

    blocTest<AuthBloc, AuthState>(
      'keeps the authenticated session when local logout cleanup fails',
      build: () {
        when(() => mockRepo.logout()).thenThrow(Exception('wipe failed'));
        return AuthBloc(
          authRepository: mockRepo,
          vaultSessionStore: vaultSessionStore,
        );
      },
      seed: () => AuthAuthenticated(
        userId: 'user-789',
        isOnboarded: true,
        isVaultLocked: false,
        masterKey: Uint8List(32),
        privateKey: Uint8List(32),
      ),
      act: (bloc) => bloc.add(const AuthLogoutRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>().having(
          (state) => state.userId,
          'userId',
          'user-789',
        ),
      ],
      verify: (_) {
        expect(vaultSessionStore.copyMemberPrivateKey(), hasLength(32));
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
        return AuthBloc(
          authRepository: mockRepo,
          vaultSessionStore: vaultSessionStore,
        );
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [isA<AuthUnauthenticated>()],
      verify: (_) {
        expect(vaultSessionStore.copyMemberPrivateKey, throwsStateError);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthAuthenticated] on successful token refresh',
      build: () {
        when(() => mockRepo.refreshToken()).thenAnswer((_) async {});
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthRefreshRequested()),
      expect: () => [
        isA<AuthAuthenticated>().having((s) => s.userId, 'userId', 'user-789'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthUnauthenticated] when token refresh fails',
      build: () {
        when(
          () => mockRepo.refreshToken(),
        ).thenThrow(AuthNoRefreshTokenException());
        return AuthBloc(
          authRepository: mockRepo,
          vaultSessionStore: vaultSessionStore,
        );
      },
      act: (bloc) => bloc.add(const AuthRefreshRequested()),
      expect: () => [isA<AuthUnauthenticated>()],
      verify: (_) {
        expect(vaultSessionStore.copyMemberPrivateKey, throwsStateError);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'email verification skips a second refresh when the claim is current',
      build: () => AuthBloc(authRepository: mockRepo),
      seed: () => const AuthAuthenticated(
        userId: 'user-789',
        isOnboarded: true,
        emailVerified: false,
      ),
      act: (bloc) => bloc.add(const AuthEmailVerified()),
      expect: () => [
        isA<AuthAuthenticated>().having(
          (state) => state.emailVerified,
          'emailVerified',
          true,
        ),
      ],
      verify: (_) {
        verifyNever(() => mockRepo.refreshToken());
      },
    );

    blocTest<AuthBloc, AuthState>(
      'email verification refreshes a stale claim before continuing',
      build: () {
        when(() => mockRepo.isEmailVerified()).thenAnswer((_) async => false);
        when(() => mockRepo.refreshToken()).thenAnswer((_) async {});
        return AuthBloc(authRepository: mockRepo);
      },
      seed: () => const AuthAuthenticated(
        userId: 'user-789',
        isOnboarded: true,
        emailVerified: false,
      ),
      act: (bloc) => bloc.add(const AuthEmailVerified()),
      expect: () => [
        isA<AuthAuthenticated>().having(
          (state) => state.emailVerified,
          'emailVerified',
          true,
        ),
      ],
      verify: (_) {
        verify(() => mockRepo.refreshToken()).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'AuthAuthenticated starts with isVaultLocked=true after login',
      build: () {
        when(
          () => mockRepo.loginWithGoogle(),
        ).thenAnswer((_) async => authResult);
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const AuthLoginWithGoogle()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>()
            .having((s) => s.isVaultLocked, 'isVaultLocked', true)
            .having((s) => s.masterKey, 'masterKey', isNull)
            .having((s) => s.privateKey, 'privateKey', isNull),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'VaultUnlocked carries keys into AuthAuthenticated state',
      build: () => AuthBloc(authRepository: mockRepo),
      seed: () =>
          const AuthAuthenticated(userId: 'user-789', isOnboarded: true),
      act: (bloc) => bloc.add(
        VaultUnlocked(
          masterKey: Uint8List.fromList(List.filled(32, 0xAA)),
          privateKey: Uint8List.fromList(List.filled(32, 0xBB)),
        ),
      ),
      expect: () => [
        isA<AuthAuthenticated>()
            .having((s) => s.isVaultLocked, 'isVaultLocked', false)
            .having((s) => s.masterKey, 'masterKey', isNotNull)
            .having((s) => s.privateKey, 'privateKey', isNotNull),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'VaultUnlocked is ignored when not authenticated',
      build: () => AuthBloc(authRepository: mockRepo),
      seed: () => const AuthUnauthenticated(),
      act: (bloc) => bloc.add(
        VaultUnlocked(
          masterKey: Uint8List.fromList(List.filled(32, 0xAA)),
          privateKey: Uint8List.fromList(List.filled(32, 0xBB)),
        ),
      ),
      expect: () => const <AuthState>[],
    );

    blocTest<AuthBloc, AuthState>(
      'OnboardingCompleted with keys → unlocked AuthAuthenticated carrying them',
      build: () {
        when(() => mockRepo.getUserId()).thenAnswer((_) async => 'user-789');
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(
        OnboardingCompleted(
          masterKey: Uint8List.fromList(List.filled(32, 0xAA)),
          privateKey: Uint8List.fromList(List.filled(32, 0xBB)),
        ),
      ),
      expect: () => [
        isA<AuthAuthenticated>()
            .having((s) => s.userId, 'userId', 'user-789')
            .having((s) => s.isOnboarded, 'isOnboarded', true)
            .having((s) => s.isVaultLocked, 'isVaultLocked', false)
            .having((s) => s.masterKey, 'masterKey', isNotNull)
            .having((s) => s.privateKey, 'privateKey', isNotNull),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'OnboardingCompleted without keys → locked vault (never unlocked with null keys)',
      build: () {
        when(() => mockRepo.getUserId()).thenAnswer((_) async => 'user-789');
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const OnboardingCompleted()),
      expect: () => [
        isA<AuthAuthenticated>()
            .having((s) => s.isOnboarded, 'isOnboarded', true)
            .having((s) => s.isVaultLocked, 'isVaultLocked', true)
            .having((s) => s.masterKey, 'masterKey', isNull)
            .having((s) => s.privateKey, 'privateKey', isNull),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'OnboardingCompleted → unauthenticated when userId is missing',
      build: () {
        when(() => mockRepo.getUserId()).thenAnswer((_) async => null);
        return AuthBloc(authRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const OnboardingCompleted()),
      expect: () => [isA<AuthUnauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'VaultLockRequested clears keys and re-locks the vault',
      build: () => AuthBloc(authRepository: mockRepo),
      seed: () => AuthAuthenticated(
        userId: 'user-789',
        isOnboarded: true,
        isVaultLocked: false,
        masterKey: Uint8List.fromList(List.filled(32, 0xAA)),
        privateKey: Uint8List.fromList(List.filled(32, 0xBB)),
      ),
      act: (bloc) => bloc.add(const VaultLockRequested()),
      expect: () => [
        isA<AuthAuthenticated>()
            .having((s) => s.isVaultLocked, 'isVaultLocked', true)
            .having((s) => s.masterKey, 'masterKey', isNull)
            .having((s) => s.privateKey, 'privateKey', isNull),
      ],
    );
  });
}
