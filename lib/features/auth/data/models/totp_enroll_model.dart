/// DTO returned by `POST /api/auth/totp/enroll`.
///
/// The account is not yet protected by TOTP — the user must scan / enter
/// [secret] into an authenticator app and confirm a generated code via
/// `POST /api/auth/totp/confirm` before it is enabled.
class TotpEnrollModel {
  const TotpEnrollModel({required this.secret, required this.otpauthUri});

  /// Base32 shared secret, shown for manual authenticator entry.
  final String secret;

  /// `otpauth://totp/…` URI encoded into the QR the user scans.
  final String otpauthUri;

  factory TotpEnrollModel.fromJson(Map<String, dynamic> json) {
    return TotpEnrollModel(
      secret: json['secret'] as String,
      otpauthUri: json['otpauthUri'] as String,
    );
  }
}
