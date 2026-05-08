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

  /// Returns the bitwise permissions claim from the current access
  /// token, or `0` (Permission.None) when no token is stored or the
  /// claim is missing. Read-only — the source of truth lives on the
  /// backend and is reissued on every token refresh.
  Future<int> getPermissions();

  /// Returns the user's email from the current access token's `email`
  /// claim, or `null` when no token is stored or the claim is missing.
  /// Read-only — used for display in account chrome (settings drawer
  /// header).
  Future<String?> getEmail();
}
