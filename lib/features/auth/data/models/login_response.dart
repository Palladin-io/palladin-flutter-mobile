import 'password_session_model.dart';

/// Result of `POST /api/auth/login`.
///
/// The endpoint returns one of two shapes:
///   * `{ totpRequired: true, challengeToken }` — the account has TOTP
///     enabled, so no tokens are issued yet; the client must complete the
///     [LoginTotpRequired] challenge.
///   * a full session (`accessToken`, `refreshToken`, …) — modelled as
///     [LoginSession].
sealed class LoginResponse {
  const LoginResponse();

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    if (json['totpRequired'] == true) {
      return LoginTotpRequired(
        challengeToken: json['challengeToken'] as String,
      );
    }
    return LoginSession(PasswordSessionModel.fromJson(json));
  }
}

/// A full authenticated session was issued (no TOTP on the account).
final class LoginSession extends LoginResponse {
  const LoginSession(this.session);

  final PasswordSessionModel session;
}

/// The account has TOTP enabled — the client must POST the 6-digit code
/// (or a recovery code) with [challengeToken] to `POST /api/auth/login/totp`.
final class LoginTotpRequired extends LoginResponse {
  const LoginTotpRequired({required this.challengeToken});

  /// Short-lived, single-use token binding the challenge to this login
  /// attempt. Held in memory only.
  final String challengeToken;
}
