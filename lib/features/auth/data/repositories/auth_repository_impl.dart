import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/storage/secure_token_storage.dart';
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
    GoogleSignIn? googleSignIn,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: ['email']);

  final AuthRemoteDatasource remoteDatasource;
  final SecureTokenStorage tokenStorage;
  final GoogleSignIn _googleSignIn;

  @override
  Future<AuthResultModel> loginWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw AuthCancelledException();
    }

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw AuthNoIdTokenException();
    }

    final result = await remoteDatasource.oauthGoogle(idToken);

    await tokenStorage.saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      userId: result.userId,
      isOnboarded: result.isOnboarded,
    );

    return result;
  }

  @override
  Future<AuthResultModel> refreshToken() async {
    final currentRefreshToken = await tokenStorage.refreshToken;
    if (currentRefreshToken == null || currentRefreshToken.isEmpty) {
      throw AuthNoRefreshTokenException();
    }

    final result = await remoteDatasource.refreshToken(currentRefreshToken);

    await tokenStorage.saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      userId: result.userId,
      isOnboarded: result.isOnboarded,
    );

    return result;
  }

  @override
  Future<void> logout() async {
    final currentRefreshToken = await tokenStorage.refreshToken;
    if (currentRefreshToken != null && currentRefreshToken.isNotEmpty) {
      try {
        await remoteDatasource.logout(currentRefreshToken);
      } catch (_) {
        // Best-effort backend logout — always clear local storage
      }
    }

    await _googleSignIn.signOut();
    await tokenStorage.clearAll();
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
