/// DTO returned by the backend after a successful OAuth exchange.
///
/// Maps the camelCase JSON from the .NET API to typed Dart fields.
class AuthResultModel {
  const AuthResultModel({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.isOnboarded,
    this.isNewUser = false,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final bool isOnboarded;
  final bool isNewUser;

  factory AuthResultModel.fromJson(Map<String, dynamic> json) {
    return AuthResultModel(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      userId: json['userId'] as String,
      isOnboarded: json['isOnboarded'] as bool,
      isNewUser: json['isNewUser'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'userId': userId,
      'isOnboarded': isOnboarded,
      'isNewUser': isNewUser,
    };
  }
}
