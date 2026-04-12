import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_claw_vault/core/storage/secure_token_storage.dart';
import 'package:mobile_claw_vault/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:mobile_claw_vault/features/auth/data/models/auth_result_model.dart';
import 'package:mobile_claw_vault/features/auth/data/repositories/auth_repository_impl.dart';

class MockAuthRemoteDatasource extends Mock implements AuthRemoteDatasource {}

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class MockGoogleSignInAuthentication extends Mock
    implements GoogleSignInAuthentication {}

void main() {
  late MockAuthRemoteDatasource mockDatasource;
  late MockSecureTokenStorage mockStorage;
  late MockGoogleSignIn mockGoogleSignIn;
  late AuthRepositoryImpl repository;

  const authResult = AuthResultModel(
    accessToken: 'access-123',
    refreshToken: 'refresh-456',
    userId: 'user-789',
    isOnboarded: true,
  );

  setUp(() {
    mockDatasource = MockAuthRemoteDatasource();
    mockStorage = MockSecureTokenStorage();
    mockGoogleSignIn = MockGoogleSignIn();
    repository = AuthRepositoryImpl(
      remoteDatasource: mockDatasource,
      tokenStorage: mockStorage,
      googleServerClientId: 'test-server-client-id',
      googleSignIn: mockGoogleSignIn,
    );
  });

  group('loginWithGoogle', () {
    test('calls datasource and stores tokens on success', () async {
      final mockAccount = MockGoogleSignInAccount();
      final mockAuth = MockGoogleSignInAuthentication();

      when(() => mockGoogleSignIn.signIn())
          .thenAnswer((_) async => mockAccount);
      when(() => mockAccount.email).thenReturn('test@example.com');
      when(() => mockAccount.authentication)
          .thenAnswer((_) async => mockAuth);
      when(() => mockAuth.idToken).thenReturn('google-id-token');
      when(() => mockDatasource.oauthGoogle('google-id-token'))
          .thenAnswer((_) async => authResult);
      when(() => mockStorage.saveTokens(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
            userId: any(named: 'userId'),
            isOnboarded: any(named: 'isOnboarded'),
          )).thenAnswer((_) async {});

      final result = await repository.loginWithGoogle();

      expect(result.accessToken, 'access-123');
      expect(result.userId, 'user-789');

      verify(() => mockDatasource.oauthGoogle('google-id-token')).called(1);
      verify(() => mockStorage.saveTokens(
            accessToken: 'access-123',
            refreshToken: 'refresh-456',
            userId: 'user-789',
            isOnboarded: true,
          )).called(1);
    });

    test('throws AuthCancelledException when user cancels', () async {
      when(() => mockGoogleSignIn.signIn()).thenAnswer((_) async => null);

      expect(
        () => repository.loginWithGoogle(),
        throwsA(isA<AuthCancelledException>()),
      );
    });

    test('throws AuthNoIdTokenException when no ID token', () async {
      final mockAccount = MockGoogleSignInAccount();
      final mockAuth = MockGoogleSignInAuthentication();

      when(() => mockGoogleSignIn.signIn())
          .thenAnswer((_) async => mockAccount);
      when(() => mockAccount.email).thenReturn('test@example.com');
      when(() => mockAccount.authentication)
          .thenAnswer((_) async => mockAuth);
      when(() => mockAuth.idToken).thenReturn(null);

      expect(
        () => repository.loginWithGoogle(),
        throwsA(isA<AuthNoIdTokenException>()),
      );
    });
  });

  group('logout', () {
    test('clears storage and signs out of Google', () async {
      when(() => mockStorage.refreshToken)
          .thenAnswer((_) async => 'refresh-456');
      when(() => mockDatasource.logout('refresh-456'))
          .thenAnswer((_) async {});
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
      when(() => mockStorage.clearAll()).thenAnswer((_) async {});

      await repository.logout();

      verify(() => mockDatasource.logout('refresh-456')).called(1);
      verify(() => mockGoogleSignIn.signOut()).called(1);
      verify(() => mockStorage.clearAll()).called(1);
    });

    test('clears storage even if backend logout fails', () async {
      when(() => mockStorage.refreshToken)
          .thenAnswer((_) async => 'refresh-456');
      when(() => mockDatasource.logout('refresh-456'))
          .thenThrow(Exception('Network error'));
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
      when(() => mockStorage.clearAll()).thenAnswer((_) async {});

      await repository.logout();

      verify(() => mockStorage.clearAll()).called(1);
    });
  });

  group('isAuthenticated', () {
    test('returns true when access token exists', () async {
      when(() => mockStorage.accessToken)
          .thenAnswer((_) async => 'access-123');

      expect(await repository.isAuthenticated(), isTrue);
    });

    test('returns false when access token is null', () async {
      when(() => mockStorage.accessToken).thenAnswer((_) async => null);

      expect(await repository.isAuthenticated(), isFalse);
    });

    test('returns false when access token is empty', () async {
      when(() => mockStorage.accessToken).thenAnswer((_) async => '');

      expect(await repository.isAuthenticated(), isFalse);
    });
  });

  group('refreshToken', () {
    test('calls datasource and stores new tokens', () async {
      when(() => mockStorage.refreshToken)
          .thenAnswer((_) async => 'old-refresh');
      when(() => mockDatasource.refreshToken('old-refresh'))
          .thenAnswer((_) async => authResult);
      when(() => mockStorage.saveTokens(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
            userId: any(named: 'userId'),
            isOnboarded: any(named: 'isOnboarded'),
          )).thenAnswer((_) async {});

      final result = await repository.refreshToken();

      expect(result.accessToken, 'access-123');
      verify(() => mockDatasource.refreshToken('old-refresh')).called(1);
      verify(() => mockStorage.saveTokens(
            accessToken: 'access-123',
            refreshToken: 'refresh-456',
            userId: 'user-789',
            isOnboarded: true,
          )).called(1);
    });

    test('throws when no refresh token stored', () async {
      when(() => mockStorage.refreshToken).thenAnswer((_) async => null);

      expect(
        () => repository.refreshToken(),
        throwsA(isA<AuthNoRefreshTokenException>()),
      );
    });
  });
}
