import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/storage/biometric_key_storage.dart';
import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/jwt_claims.dart';
import '../../../autofill/domain/autofill_cache_invalidator.dart';
import '../../domain/auth_provider_id.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/auth_result_model.dart';

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
    GoogleSignIn? googleSignIn,
  }) : _googleSignIn =
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
  final GoogleSignIn _googleSignIn;

  @override
  Future<AuthResultModel> loginWithGoogle() async {
    AppLogger.d('Auth', 'Starting Google Sign-In');
    final account = await _googleSignIn.signIn();
    if (account == null) {
      AppLogger.i('Auth', 'Sign-in cancelled by user');
      throw AuthCancelledException();
    }

    AppLogger.d('Auth', 'Google account: ${account.email}');
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
  Future<AuthResultModel> refreshToken() async {
    AppLogger.d('Auth', 'Attempting token refresh');
    final currentRefreshToken = await tokenStorage.refreshToken;
    if (currentRefreshToken == null || currentRefreshToken.isEmpty) {
      AppLogger.w('Auth', 'No refresh token available');
      throw AuthNoRefreshTokenException();
    }

    final AuthResultModel result;
    try {
      result = await remoteDatasource.refreshToken(currentRefreshToken);
    } on DioException catch (e, s) {
      AppLogger.e('Auth', 'Token refresh failed', error: e, stackTrace: s);
      throw AuthServerException(_classifyError(e));
    } on FormatException catch (e) {
      AppLogger.e('Auth', 'Invalid refresh response', error: e);
      throw AuthServerException(AuthServerErrorKind.invalidResponse);
    }

    await tokenStorage.saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      userId: result.userId,
      isOnboarded: result.isOnboarded,
    );

    AppLogger.i('Auth', 'Token refresh successful');
    return result;
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

    // Best-effort native AutoFill revocation, attempted first so its queued
    // clear runs before any in-flight replacement. The cache holds only
    // ciphertext encrypted with a dedicated key (never MK/VK) and is retried on
    // the AuthUnauthenticated transition, so a hard native failure (e.g. a
    // simulator without a provisioned credential provider) must never abort
    // logout and strand the user in a locked session. Time-boxed like the other
    // best-effort steps below.
    try {
      await autoFillCacheInvalidator.clear().timeout(const Duration(seconds: 4));
    } catch (e) {
      AppLogger.w('Auth', 'AutoFill revocation failed (best-effort): $e');
    }

    // Critical local security cleanup — must always run so backend/native
    // availability can never keep a valid local session alive.
    await tokenStorage.clearAll();
    await BiometricKeyStorage.clear(secureStorage);

    // Best-effort, time-boxed remote revoke + Google sign-out. Never let these
    // block logout (backend down, no APNs, simulator quirks, etc.).
    if (currentRefreshToken != null && currentRefreshToken.isNotEmpty) {
      try {
        await remoteDatasource
            .logout(currentRefreshToken)
            .timeout(const Duration(seconds: 4));
      } catch (e) {
        AppLogger.w('Auth', 'Backend logout failed (best-effort): $e');
      }
    }

    try {
      await _googleSignIn.signOut().timeout(const Duration(seconds: 4));
    } catch (e) {
      AppLogger.w('Auth', 'Google sign-out failed (best-effort): $e');
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
