/// DTO returned by `POST /api/auth/refresh`.
///
/// Refresh responses intentionally contain only the rotated token pair. User
/// metadata remains in secure storage and must not be parsed from this response
/// as though it were a full login result.
class RefreshTokenResultModel {
  const RefreshTokenResultModel({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  factory RefreshTokenResultModel.fromJson(Map<String, dynamic> json) {
    return RefreshTokenResultModel(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
  }
}
