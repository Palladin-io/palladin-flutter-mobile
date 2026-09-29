import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/core/storage/biometric_key_storage.dart';
import 'package:mobile_palladin/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/data/models/auth_result_model.dart';
import 'package:mobile_palladin/features/auth/data/models/refresh_token_result_model.dart';
import 'package:mobile_palladin/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mobile_palladin/features/auth/domain/auth_provider_id.dart';
import 'package:mobile_palladin/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_cache_invalidator.dart';
import 'package:mobile_palladin/features/autofill/data/generated_password_history_bridge.dart';

class MockAuthRemoteDatasource extends Mock implements AuthRemoteDatasource {}

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class MockGoogleSignInAuthentication extends Mock
    implements GoogleSignInAuthentication {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockAutoFillCacheInvalidator extends Mock
    implements AutoFillCacheInvalidator {}

class MockGeneratedPasswordHistoryBridge extends Mock
    implements GeneratedPasswordHistoryBridge {}

class MockCurrentEntryCacheInvalidator extends Mock
    implements CurrentEntryCacheInvalidator {}

void main() {
  late MockAuthRemoteDatasource mockDatasource;
  late MockSecureTokenStorage mockStorage;
  late MockGoogleSignIn mockGoogleSignIn;
  late MockFlutterSecureStorage mockSecureStorage;
  late MockAutoFillCacheInvalidator mockAutoFillCacheInvalidator;
  late MockGeneratedPasswordHistoryBridge mockGeneratedHistory;
  late MockCurrentEntryCacheInvalidator mockCurrentEntryCacheInvalidator;
  late AuthRepositoryImpl repository;

  const authResult = AuthResultModel(
    accessToken: 'access-123',
    refreshToken: 'refresh-456',
    userId: 'user-789',
    isOnboarded: true,
  );
  const refreshResult = RefreshTokenResultModel(
    accessToken: 'access-123',
    refreshToken: 'refresh-456',
  );

  setUp(() {
    mockDatasource = MockAuthRemoteDatasource();
    mockStorage = MockSecureTokenStorage();
    mockGoogleSignIn = MockGoogleSignIn();
    mockSecureStorage = MockFlutterSecureStorage();
    mockAutoFillCacheInvalidator = MockAutoFillCacheInvalidator();
    mockGeneratedHistory = MockGeneratedPasswordHistoryBridge();
    when(
      () => mockGeneratedHistory.revokeAllSessions(),
    ).thenAnswer((_) async {});
    mockCurrentEntryCacheInvalidator = MockCurrentEntryCacheInvalidator();
    when(
      () => mockAutoFillCacheInvalidator.revokeAccess(),
    ).thenAnswer((_) async {});
    when(() => mockAutoFillCacheInvalidator.clear()).thenAnswer((_) async {});
    when(
      () => mockCurrentEntryCacheInvalidator.clearCurrentEntryCache(),
    ).thenAnswer((_) async {});
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
      generatedPasswordHistory: mockGeneratedHistory,
      currentEntryCacheInvalidator: mockCurrentEntryCacheInvalidator,
      googleServerClientId: 'test-server-client-id',
      googleSignIn: mockGoogleSignIn,
      operationTimeout: const Duration(milliseconds: 20),
    );
  });

  group('loginWithGoogle', () {
    test(
      'missing configuration never invokes the platform or backend',
      () async {
        final unconfigured = AuthRepositoryImpl(
          remoteDatasource: mockDatasource,
          tokenStorage: mockStorage,
          secureStorage: mockSecureStorage,
          autoFillCacheInvalidator: mockAutoFillCacheInvalidator,
          googleServerClientId: '',
          googleSignIn: mockGoogleSignIn,
        );
        await expectLater(
          unconfigured.loginWithGoogle(),
          throwsA(isA<AuthGoogleConfigurationException>()),
        );
        verifyZeroInteractions(mockGoogleSignIn);
        verifyZeroInteractions(mockDatasource);
        verifyZeroInteractions(mockStorage);
      },
    );

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
      verify(() => mockGeneratedHistory.revokeAllSessions()).called(1);
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

    test(
      'clears tokens and biometric marker when Entry cache cleanup fails',
      () async {
        when(() => mockStorage.refreshToken).thenAnswer((_) async => null);
        when(
          () => mockCurrentEntryCacheInvalidator.clearCurrentEntryCache(),
        ).thenThrow(StateError('simulated database failure'));
        when(() => mockStorage.clearAll()).thenAnswer((_) async {});
        when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async => null);

        await repository.logout();

        verify(() => mockStorage.clearAll()).called(1);
        verify(
          () => mockSecureStorage.delete(
            key: BiometricKeyStorage.legacyRawKey,
            iOptions: any(named: 'iOptions'),
            aOptions: any(named: 'aOptions'),
          ),
        ).called(1);
        verify(
          () => mockSecureStorage.delete(
            key: BiometricKeyStorage.enrolledMarkerKey,
            iOptions: any(named: 'iOptions'),
            aOptions: any(named: 'aOptions'),
          ),
        ).called(1);
      },
    );

    test('clears tokens when Entry cache cleanup times out', () async {
      when(() => mockStorage.refreshToken).thenAnswer((_) async => null);
      final cleanup = Completer<void>();
      when(
        () => mockCurrentEntryCacheInvalidator.clearCurrentEntryCache(),
      ).thenAnswer((_) => cleanup.future);
      when(() => mockStorage.clearAll()).thenAnswer((_) async {});
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async => null);

      await repository.logout();

      verify(() => mockStorage.clearAll()).called(1);
      cleanup.complete();
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
      'clears auth and biometric material when AutoFill revocation fails',
      () async {
        when(() => mockStorage.refreshToken).thenAnswer((_) async => null);
        when(
          () => mockAutoFillCacheInvalidator.revokeAccess(),
        ).thenThrow(Exception('native key revocation failed'));
        when(() => mockStorage.clearAll()).thenAnswer((_) async {});
        when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async => null);

        await repository.logout();

        verify(() => mockStorage.clearAll()).called(1);
        // First call proves the fallback deny; the second is best-effort
        // physical/provider-identity cleanup after the deny is confirmed.
        verify(() => mockAutoFillCacheInvalidator.clear()).called(2);
        verify(
          () => mockSecureStorage.delete(
            key: BiometricKeyStorage.enrolledMarkerKey,
            iOptions: any(named: 'iOptions'),
            aOptions: any(named: 'aOptions'),
          ),
        ).called(1);
      },
    );

    test('clears auth when AutoFill revocation times out', () async {
      when(() => mockStorage.refreshToken).thenAnswer((_) async => null);
      final revocation = Completer<void>();
      when(
        () => mockAutoFillCacheInvalidator.revokeAccess(),
      ).thenAnswer((_) => revocation.future);
      when(() => mockStorage.clearAll()).thenAnswer((_) async {});
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async => null);

      await repository.logout();

      verify(() => mockStorage.clearAll()).called(1);
      revocation.complete();
    });

    test('keeps auth when neither native deny boundary is confirmed', () async {
      when(() => mockStorage.refreshToken).thenAnswer((_) async => null);
      when(
        () => mockAutoFillCacheInvalidator.revokeAccess(),
      ).thenThrow(StateError('fence'));
      when(
        () => mockAutoFillCacheInvalidator.clear(),
      ).thenThrow(StateError('clear'));

      await expectLater(repository.logout(), throwsStateError);

      verifyNever(() => mockStorage.clearAll());
    });

    test('keeps auth when generated-password session deny fails', () async {
      when(() => mockStorage.refreshToken).thenAnswer((_) async => null);
      when(
        () => mockGeneratedHistory.revokeAllSessions(),
      ).thenThrow(StateError('history deny failed'));

      await expectLater(repository.logout(), throwsStateError);

      verifyNever(() => mockAutoFillCacheInvalidator.revokeAccess());
      verifyNever(() => mockStorage.clearAll());
    });

    test('attempts biometric cleanup when token deletion fails', () async {
      when(() => mockStorage.refreshToken).thenAnswer((_) async => null);
      when(() => mockStorage.clearAll()).thenThrow(StateError('storage'));

      await expectLater(repository.logout(), throwsStateError);

      verify(
        () => mockSecureStorage.delete(
          key: BiometricKeyStorage.enrolledMarkerKey,
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        ),
      ).called(1);
    });
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
      ).thenAnswer((_) async => refreshResult);
      when(
        () => mockStorage.updateTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenAnswer((_) async {});

      await repository.refreshToken();

      verify(() => mockDatasource.refreshToken('old-refresh')).called(1);
      verify(
        () => mockStorage.updateTokens(
          accessToken: 'access-123',
          refreshToken: 'refresh-456',
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
