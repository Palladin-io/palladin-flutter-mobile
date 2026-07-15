import '../../data/models/auth_result_model.dart';

/// Contract for authentication operations.
///
/// Abstract in the domain layer; implemented by [AuthRepositoryImpl]
/// in the data layer.
abstract class AuthRepository {
  /// Initiates Google Sign-In flow, exchanges the ID token with the
  /// backend, and persists the resulting JWT credentials.
  Future<AuthResultModel> loginWithGoogle();

  /// Refreshes the token pair while preserving stored session metadata.
  Future<void> refreshToken();

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

  /// Returns whether the current access token's `email_verified` claim is
  /// set. Defaults to `true` when no token is stored or the claim is
  /// missing (OAuth sessions are always verified) so a user is never
  /// wedged behind the verification wall by a missing claim.
  Future<bool> isEmailVerified();

  /// Returns how the current session was authenticated
  /// (`AuthProviderId.password` / `AuthProviderId.google`), or `null` when
  /// unknown. Persisted at login time (the JWT carries no provider claim)
  /// and used to gate password-only account actions.
  Future<String?> getAuthProvider();
}
