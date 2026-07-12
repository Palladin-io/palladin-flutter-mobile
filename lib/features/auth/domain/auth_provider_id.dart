/// Identifiers for how the current session was authenticated.
///
/// Persisted locally at login/registration time (the backend JWT does not
/// carry a provider claim) so account-security surfaces — e.g. "Change
/// master password" and "Two-factor authentication" — can be gated to
/// password accounts, which are the only accounts that have an `authHash`
/// / TOTP login credential.
abstract final class AuthProviderId {
  /// Email + master-password account (has an `authHash` and can enrol TOTP).
  static const String password = 'password';

  /// Google OAuth account (no password-login credential).
  static const String google = 'google';
}
