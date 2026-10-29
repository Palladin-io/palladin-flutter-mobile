/// Typed exceptions for the email + master-password auth flows.
///
/// Following the project convention, the data layer throws these typed
/// errors (never user-facing strings); the presentation layer maps them
/// to localized copy where `BuildContext` is available.
library;

/// Classifies network / protocol failures shared across the auth flows.
enum PasswordAuthServerErrorKind {
  serverNotResponding,
  cannotConnect,
  connectionFailed,
  invalidResponse,
}

/// Thrown for network / protocol failures on any password-auth endpoint.
class PasswordAuthServerException implements Exception {
  const PasswordAuthServerException(this.kind);

  final PasswordAuthServerErrorKind kind;

  @override
  String toString() => 'PasswordAuthServerException(${kind.name})';
}

/// Thrown by `POST /api/auth/register` when the email is already
/// registered (HTTP 409).
class EmailAlreadyRegisteredException implements Exception {
  const EmailAlreadyRegisteredException();

  @override
  String toString() => 'EmailAlreadyRegisteredException';
}

/// Thrown by `POST /api/auth/login` on an unknown email or a bad auth
/// hash (HTTP 401 — deliberately indistinguishable).
class InvalidCredentialsException implements Exception {
  const InvalidCredentialsException();

  @override
  String toString() => 'InvalidCredentialsException';
}

/// Thrown when the login attempt is rate-limited / the account is locked
/// after too many failures (HTTP 429).
class LoginRateLimitedException implements Exception {
  const LoginRateLimitedException({this.retryAfterSeconds});

  final int? retryAfterSeconds;

  @override
  String toString() => 'LoginRateLimitedException';
}

/// Thrown by `POST /api/auth/login/totp` when the TOTP code (or recovery
/// code) is wrong, or the challenge token has expired / been used.
class TotpInvalidException implements Exception {
  const TotpInvalidException();

  @override
  String toString() => 'TotpInvalidException';
}

/// Thrown by the TOTP enroll/confirm endpoints when the server rejects the
/// current auth credential derived from the entered password (HTTP 403).
class TotpCurrentCredentialException implements Exception {
  const TotpCurrentCredentialException();

  @override
  String toString() => 'TotpCurrentCredentialException';
}

/// Thrown by the TOTP endpoints for an account without a password login
/// credential (HTTP 404) — TOTP protects password sign-in only.
class TotpUnavailableException implements Exception {
  const TotpUnavailableException();

  @override
  String toString() => 'TotpUnavailableException';
}

/// Distinguishes the two terminal verification-token failures surfaced by
/// `POST /api/auth/verify-email`.
enum VerificationTokenErrorKind { expired, invalid }

/// Thrown by `POST /api/auth/verify-email` when the token is expired or
/// invalid. The backend distinguishes the two via the error keys
/// `errors.backend.verification-token-expired` / `...-invalid`.
class VerificationTokenException implements Exception {
  const VerificationTokenException(this.kind);

  final VerificationTokenErrorKind kind;

  @override
  String toString() => 'VerificationTokenException(${kind.name})';
}
