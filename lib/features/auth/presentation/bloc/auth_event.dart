/// Base class for all authentication events.
sealed class AuthEvent {
  const AuthEvent();
}

/// Triggers the Google OAuth sign-in flow.
final class AuthLoginWithGoogle extends AuthEvent {
  const AuthLoginWithGoogle();
}

/// Requests a token refresh using stored credentials.
final class AuthRefreshRequested extends AuthEvent {
  const AuthRefreshRequested();
}

/// Logs out the current user and clears stored credentials.
final class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

/// Checks whether the user is already authenticated from a previous
/// session (e.g. on app startup).
final class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}
