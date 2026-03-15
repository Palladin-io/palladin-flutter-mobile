/// Base class for all authentication states.
sealed class AuthState {
  const AuthState();
}

/// Initial state before any auth check has been performed.
final class AuthInitial extends AuthState {
  const AuthInitial();
}

/// An authentication operation is in progress.
final class AuthLoading extends AuthState {
  const AuthLoading();
}

/// The user is authenticated and has valid credentials.
final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({
    required this.userId,
    required this.isOnboarded,
  });

  final String userId;
  final bool isOnboarded;
}

/// The user is not authenticated (no valid tokens).
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// An authentication operation failed.
final class AuthError extends AuthState {
  const AuthError(this.message);

  final String message;
}
