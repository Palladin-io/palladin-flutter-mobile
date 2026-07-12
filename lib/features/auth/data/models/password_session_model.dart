/// DTO returned by `POST /api/auth/register`, a non-TOTP
/// `POST /api/auth/login`, and `POST /api/auth/login/totp`.
///
/// Mirrors [AuthResultModel] (OAuth) plus the [emailVerified] flag that
/// gates a freshly-registered password account into the "verify your
/// email" state before it can use the vault.
class PasswordSessionModel {
  const PasswordSessionModel({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.isOnboarded,
    required this.emailVerified,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final bool isOnboarded;
  final bool emailVerified;

  factory PasswordSessionModel.fromJson(Map<String, dynamic> json) {
    return PasswordSessionModel(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      userId: json['userId'] as String,
      isOnboarded: json['isOnboarded'] as bool? ?? true,
      // Absent on older backends → treat as verified so the user is never
      // wedged behind a verification wall the server can't clear.
      emailVerified: json['emailVerified'] as bool? ?? true,
    );
  }
}
