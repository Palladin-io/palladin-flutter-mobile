import '../../data/models/auth_result_model.dart';

/// Contract for authentication operations.
///
/// Abstract in the domain layer; implemented by [AuthRepositoryImpl]
/// in the data layer.
abstract class AuthRepository {
  /// Initiates Google Sign-In flow, exchanges the ID token with the
  /// backend, and persists the resulting JWT credentials.
  Future<AuthResultModel> loginWithGoogle();

  /// Attempts to refresh the current session using the stored refresh
  /// token.
  Future<AuthResultModel> refreshToken();

  /// Logs out the current user — invalidates the refresh token on the
  /// backend and clears local storage.
  Future<void> logout();

  /// Returns `true` if a valid access token is stored locally.
  ///
  /// Note: this only checks local storage presence, not token validity.
  Future<bool> isAuthenticated();

  /// Returns the stored user ID, or `null` if not authenticated.
  Future<String?> getUserId();

  /// Returns whether the user has completed onboarding.
  Future<bool> isOnboarded();
}
