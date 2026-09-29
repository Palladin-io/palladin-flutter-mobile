import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/storage/biometric_key_storage.dart';
import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/jwt_claims.dart';
import '../../../autofill/domain/autofill_cache_invalidator.dart';
import '../../../autofill/data/generated_password_history_bridge.dart';
import '../../domain/auth_provider_id.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/auth_result_model.dart';
import '../models/refresh_token_result_model.dart';

/// Concrete implementation of [AuthRepository].
///
/// Orchestrates Google Sign-In, backend token exchange, and secure
/// local storage of JWT credentials.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required this.remoteDatasource,
    required this.tokenStorage,
    required this.secureStorage,
    required this.autoFillCacheInvalidator,
    required String googleServerClientId,
    this.currentEntryCacheInvalidator,
    GeneratedPasswordHistoryBridge? generatedPasswordHistory,
    GoogleSignIn? googleSignIn,
    this.operationTimeout = const Duration(seconds: 4),
  }) : _generatedPasswordHistory =
           generatedPasswordHistory ?? GeneratedPasswordHistoryBridge(),
       _googleConfigured = googleServerClientId.trim().isNotEmpty,
       _googleSignIn =
           googleSignIn ??
           GoogleSignIn(
             scopes: ['email'],
             // serverClientId ensures the ID token audience matches the backend's
             // web OAuth client ID, enabling server-side token validation.
             serverClientId: googleServerClientId.isEmpty
                 ? null
                 : googleServerClientId,
           );

  final AuthRemoteDatasource remoteDatasource;
  final SecureTokenStorage tokenStorage;
  final FlutterSecureStorage secureStorage;
  final AutoFillCacheInvalidator autoFillCacheInvalidator;
  final GeneratedPasswordHistoryBridge _generatedPasswordHistory;
  final GoogleSignIn _googleSignIn;
  final bool _googleConfigured;
  final Duration operationTimeout;
  final CurrentEntryCacheInvalidator? currentEntryCacheInvalidator;

  @override
  Future<AuthResultModel> loginWithGoogle() async {
    // Never fall back to a client ID embedded in the Firebase platform config.
    if (!_googleConfigured) throw const AuthGoogleConfigurationException();
    AppLogger.d('Auth', 'Starting Google Sign-In');
    final account = await _googleSignIn.signIn();
    if (account == null) {
      AppLogger.i('Auth', 'Sign-in cancelled by user');
      throw AuthCancelledException();
    }

    final auth = await account.authentication;
    final idToken = auth.idToken;
    AppLogger.d('Auth', 'Got auth tokens, idToken present: ${idToken != null}');
    if (idToken == null) {
      throw AuthNoIdTokenException();
    }

    final AuthResultModel result;
    try {
      AppLogger.d('Auth', 'Exchanging token with backend');
      result = await remoteDatasource.oauthGoogle(idToken);
    } on DioException catch (e, s) {
      AppLogger.e('Auth', 'Backend exchange failed', error: e, stackTrace: s);
      throw AuthServerException(_classifyError(e));
    } on FormatException catch (e) {
      AppLogger.e('Auth', 'Invalid backend response', error: e);
      throw AuthServerException(AuthServerErrorKind.invalidResponse);
    }

    await tokenStorage.saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      userId: result.userId,
      isOnboarded: result.isOnboarded,
    );
    // Mark this session as Google-authenticated so password-only account
    // actions (change master password, TOTP) stay hidden for OAuth users.
    await tokenStorage.setAuthProvider(AuthProviderId.google);

    AppLogger.i('Auth', 'Login successful, userId: ${result.userId}');
    return result;
  }

  @override
  Future<void> refreshToken() async {
    AppLogger.d('Auth', 'Attempting token refresh');
    final currentRefreshToken = await tokenStorage.refreshToken;
    if (currentRefreshToken == null || currentRefreshToken.isEmpty) {
      AppLogger.w('Auth', 'No refresh token available');
      throw AuthNoRefreshTokenException();
    }

    final RefreshTokenResultModel result;
    try {
      result = await remoteDatasource.refreshToken(currentRefreshToken);
    } on DioException catch (e, s) {
      AppLogger.e('Auth', 'Token refresh failed', error: e, stackTrace: s);
      throw AuthServerException(_classifyError(e));
    } on FormatException catch (e) {
      AppLogger.e('Auth', 'Invalid refresh response', error: e);
      throw AuthServerException(AuthServerErrorKind.invalidResponse);
    }

    await tokenStorage.updateTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );

    AppLogger.i('Auth', 'Token refresh successful');
  }

  /// Maps a [DioException] to a typed [AuthServerErrorKind].
  AuthServerErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return AuthServerErrorKind.serverNotResponding;
    }

    if (e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return AuthServerErrorKind.cannotConnect;
    }

    return AuthServerErrorKind.connectionFailed;
  }

  @override
  Future<void> logout() async {
    AppLogger.d('Auth', 'Starting logout');
    final currentRefreshToken = await tokenStorage.refreshToken;

    // The generated-password session is independent of the disposable Vault
    // cache. Its deny must be acknowledged before logout can clear auth state.
    try {
      await _generatedPasswordHistory.revokeAllSessions().timeout(
        operationTimeout,
      );
    } on MissingPluginException {
      // Unsupported test hosts and iOS simulators have no native provider.
    }

    // Native revocation returns only after the durable deny fence commits.
    // If that commit cannot be confirmed, a synchronous cache clear is the
    // fallback deny boundary; logout must not be reported without either one.
    try {
      await autoFillCacheInvalidator.revokeAccess().timeout(operationTimeout);
    } catch (e) {
      AppLogger.w(
        'Auth',
        'AutoFill revocation was not confirmed: ${e.runtimeType}',
      );
      await autoFillCacheInvalidator.clear().timeout(operationTimeout);
    }
    try {
      await currentEntryCacheInvalidator?.clearCurrentEntryCache().timeout(
        operationTimeout,
      );
    } catch (e) {
      // Runtime access is revoked independently by the Vault service before
      // durable deletion. A wedged database must not preserve authentication.
      AppLogger.w(
        'Auth',
        'Current Entry cache cleanup failed (access quarantined): '
            '${e.runtimeType}',
      );
    }

    // Removing provider identities is best-effort. Access is already revoked
    // above, so stale identity metadata cannot release cached credentials.
    try {
      await autoFillCacheInvalidator.clear().timeout(operationTimeout);
    } catch (e) {
      AppLogger.w(
        'Auth',
        'AutoFill identity cleanup failed (best-effort): ${e.runtimeType}',
      );
    }

    // Critical local security cleanup — must always run so backend/native
    // availability can never keep a valid local session alive.
    try {
      await tokenStorage.clearAll();
    } finally {
      await BiometricKeyStorage.clear(secureStorage);
    }

    // Best-effort, time-boxed remote revoke + Google sign-out. Never let these
    // block logout (backend down, no APNs, simulator quirks, etc.).
    if (currentRefreshToken != null && currentRefreshToken.isNotEmpty) {
      try {
        await remoteDatasource
            .logout(currentRefreshToken)
            .timeout(operationTimeout);
      } catch (e) {
        AppLogger.w(
          'Auth',
          'Backend logout failed (best-effort): ${e.runtimeType}',
        );
      }
    }

    try {
      await _googleSignIn.signOut().timeout(operationTimeout);
    } catch (e) {
      AppLogger.w(
        'Auth',
        'Google sign-out failed (best-effort): ${e.runtimeType}',
      );
    }
    AppLogger.i('Auth', 'Logout complete, tokens cleared');
  }

  @override
  Future<bool> isAuthenticated() async {
    final token = await tokenStorage.accessToken;
    return token != null && token.isNotEmpty;
  }

  @override
  Future<String?> getUserId() => tokenStorage.userId;

  @override
  Future<String?> getOrganizationId() async {
    final token = await tokenStorage.accessToken;
    if (token == null || token.isEmpty) return null;
    return JwtClaims.organizationIdFrom(token);
  }

  @override
  Future<bool> isOnboarded() => tokenStorage.isOnboarded;

  @override
  Future<int> getPermissions() async {
    final token = await tokenStorage.accessToken;
    if (token == null || token.isEmpty) return 0;
    return JwtClaims.permissionsFrom(token);
  }

  @override
  Future<String?> getEmail() async {
    final token = await tokenStorage.accessToken;
    if (token == null || token.isEmpty) return null;
    return JwtClaims.emailFrom(token);
  }

  @override
  Future<bool> isEmailVerified() async {
    final token = await tokenStorage.accessToken;
    if (token == null || token.isEmpty) return true;
    return JwtClaims.emailVerifiedFrom(token);
  }

  @override
  Future<String?> getAuthProvider() => tokenStorage.authProvider;
}

/// Thrown when the user cancels the Google Sign-In dialog.
class AuthCancelledException implements Exception {
  @override
  String toString() => 'Sign in was cancelled';
}

/// Thrown when Google Sign-In succeeds but no ID token is returned.
class AuthNoIdTokenException implements Exception {
  @override
  String toString() => 'Failed to obtain ID token from Google';
}

/// Thrown when a token refresh is attempted without a stored refresh token.
class AuthNoRefreshTokenException implements Exception {
  @override
  String toString() => 'No refresh token available';
}

/// Thrown when the backend returns an error or is unreachable.
///
/// Carries a typed [kind] so the presentation layer can resolve the
/// appropriate localized message via [AppLocalizations].
class AuthServerException implements Exception {
  const AuthServerException(this.kind);

  final AuthServerErrorKind kind;

  @override
  String toString() => 'AuthServerException(${kind.name})';
}

/// Classifies server/network errors so the UI can map them to
/// localized strings without embedding user-facing text in the data layer.
enum AuthServerErrorKind {
  serverNotResponding,
  cannotConnect,
  connectionFailed,
  invalidResponse,
}

class AuthGoogleConfigurationException implements Exception {
  const AuthGoogleConfigurationException();
}
