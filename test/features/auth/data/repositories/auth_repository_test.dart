import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/data/models/auth_result_model.dart';
import 'package:mobile_palladin/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mobile_palladin/features/auth/domain/auth_provider_id.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_cache_invalidator.dart';

class MockAuthRemoteDatasource extends Mock implements AuthRemoteDatasource {}

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class MockGoogleSignInAuthentication extends Mock
    implements GoogleSignInAuthentication {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockAutoFillCacheInvalidator extends Mock
    implements AutoFillCacheInvalidator {}

void main() {
  late MockAuthRemoteDatasource mockDatasource;
  late MockSecureTokenStorage mockStorage;
  late MockGoogleSignIn mockGoogleSignIn;
  late MockFlutterSecureStorage mockSecureStorage;
  late MockAutoFillCacheInvalidator mockAutoFillCacheInvalidator;
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
    mockSecureStorage = MockFlutterSecureStorage();
    mockAutoFillCacheInvalidator = MockAutoFillCacheInvalidator();
    when(
      () => mockAutoFillCacheInvalidator.revokeAccess(),
    ).thenAnswer((_) async {});
    when(() => mockAutoFillCacheInvalidator.clear()).thenAnswer((_) async {});
    when(
      () => mockSecureStorage.delete(
        key: any(named: 'key'),
        iOptions: any(named: 'iOptions'),
        aOptions: any(named: 'aOptions'),
      ),
    ).thenAnswer((_) async {});
    repository = AuthRepositoryImpl(
      remoteDatasource: mockDatasource,
      tokenStorage: mockStorage,
      secureStorage: mockSecureStorage,
      autoFillCacheInvalidator: mockAutoFillCacheInvalidator,
      googleServerClientId: 'test-server-client-id',
      googleSignIn: mockGoogleSignIn,
      operationTimeout: const Duration(milliseconds: 20),
    );
  });

  group('loginWithGoogle', () {
    test('calls datasource and stores tokens on success', () async {
      final mockAccount = MockGoogleSignInAccount();
      final mockAuth = MockGoogleSignInAuthentication();

      when(
        () => mockGoogleSignIn.signIn(),
      ).thenAnswer((_) async => mockAccount);
      when(() => mockAccount.email).thenReturn('test@example.com');
      when(() => mockAccount.authentication).thenAnswer((_) async => mockAuth);
      when(() => mockAuth.idToken).thenReturn('google-id-token');
      when(
        () => mockDatasource.oauthGoogle('google-id-token'),
      ).thenAnswer((_) async => authResult);
      when(
        () => mockStorage.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
          userId: any(named: 'userId'),
          isOnboarded: any(named: 'isOnboarded'),
        ),
      ).thenAnswer((_) async {});
      when(() => mockStorage.setAuthProvider(any())).thenAnswer((_) async {});

      final result = await repository.loginWithGoogle();

      expect(result.accessToken, 'access-123');
      expect(result.userId, 'user-789');

      verify(() => mockDatasource.oauthGoogle('google-id-token')).called(1);
      verify(
        () => mockStorage.saveTokens(
          accessToken: 'access-123',
          refreshToken: 'refresh-456',
          userId: 'user-789',
          isOnboarded: true,
        ),
      ).called(1);
      // The OAuth-gating safety valve depends on this marker being written —
      // without it, password-only account actions would leak to Google users.
      verify(
        () => mockStorage.setAuthProvider(AuthProviderId.google),
      ).called(1);
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

      when(
        () => mockGoogleSignIn.signIn(),
      ).thenAnswer((_) async => mockAccount);
      when(() => mockAccount.email).thenReturn('test@example.com');
      when(() => mockAccount.authentication).thenAnswer((_) async => mockAuth);
      when(() => mockAuth.idToken).thenReturn(null);

      expect(
        () => repository.loginWithGoogle(),
        throwsA(isA<AuthNoIdTokenException>()),
      );
    });
  });

  group('logout', () {
    test('clears storage and signs out of Google', () async {
      when(
        () => mockStorage.refreshToken,
      ).thenAnswer((_) async => 'refresh-456');
      when(() => mockDatasource.logout('refresh-456')).thenAnswer((_) async {});
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
      when(() => mockStorage.clearAll()).thenAnswer((_) async {});

      await repository.logout();

      verify(() => mockDatasource.logout('refresh-456')).called(1);
      verify(() => mockGoogleSignIn.signOut()).called(1);
      verify(() => mockStorage.clearAll()).called(1);
      verify(() => mockAutoFillCacheInvalidator.revokeAccess()).called(1);
      verify(() => mockAutoFillCacheInvalidator.clear()).called(1);
    });

    test('clears storage even if backend logout fails', () async {
      when(
        () => mockStorage.refreshToken,
      ).thenAnswer((_) async => 'refresh-456');
      when(
        () => mockDatasource.logout('refresh-456'),
      ).thenThrow(Exception('Network error'));
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
      when(() => mockStorage.clearAll()).thenAnswer((_) async {});

      await repository.logout();

      verify(() => mockStorage.clearAll()).called(1);
    });

    test('attempts AutoFill revocation before clearing auth storage', () async {
      final clearStarted = Completer<void>();
      final allowClear = Completer<void>();
      when(() => mockStorage.refreshToken).thenAnswer((_) async => null);
      when(() => mockAutoFillCacheInvalidator.revokeAccess()).thenAnswer((
        _,
      ) async {
        clearStarted.complete();
        await allowClear.future;
      });
      when(() => mockStorage.clearAll()).thenAnswer((_) async {});
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async => null);

      final logout = repository.logout();
      await clearStarted.future;

      verifyNever(() => mockStorage.clearAll());
      allowClear.complete();
      await logout;

      verify(() => mockStorage.clearAll()).called(1);
    });

    test(
      'still clears auth storage when AutoFill identity cleanup hangs',
      () async {
        when(() => mockStorage.refreshToken).thenAnswer((_) async => null);
        final identityCleanup = Completer<void>();
        when(
          () => mockAutoFillCacheInvalidator.clear(),
        ).thenAnswer((_) => identityCleanup.future);
        when(() => mockStorage.clearAll()).thenAnswer((_) async {});
        when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async => null);

        // Access revocation already succeeded, so a provider-identity callback
        // that never returns must not strand the authenticated session.
        await repository.logout();

        verify(() => mockAutoFillCacheInvalidator.revokeAccess()).called(1);
        verify(() => mockStorage.clearAll()).called(1);
      },
    );

    test(
      'keeps the session active when AutoFill access revocation fails',
      () async {
        when(() => mockStorage.refreshToken).thenAnswer((_) async => null);
        when(
          () => mockAutoFillCacheInvalidator.revokeAccess(),
        ).thenThrow(Exception('native key revocation failed'));

        await expectLater(repository.logout(), throwsException);

        verifyNever(() => mockStorage.clearAll());
        verifyNever(() => mockAutoFillCacheInvalidator.clear());
      },
    );
  });

  group('isAuthenticated', () {
    test('returns true when access token exists', () async {
      when(() => mockStorage.accessToken).thenAnswer((_) async => 'access-123');

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
      when(
        () => mockStorage.refreshToken,
      ).thenAnswer((_) async => 'old-refresh');
      when(
        () => mockDatasource.refreshToken('old-refresh'),
      ).thenAnswer((_) async => authResult);
      when(
        () => mockStorage.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
          userId: any(named: 'userId'),
          isOnboarded: any(named: 'isOnboarded'),
        ),
      ).thenAnswer((_) async {});

      final result = await repository.refreshToken();

      expect(result.accessToken, 'access-123');
      verify(() => mockDatasource.refreshToken('old-refresh')).called(1);
      verify(
        () => mockStorage.saveTokens(
          accessToken: 'access-123',
          refreshToken: 'refresh-456',
          userId: 'user-789',
          isOnboarded: true,
        ),
      ).called(1);
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
