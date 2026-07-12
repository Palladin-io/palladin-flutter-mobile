import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/data/models/login_response.dart';
import 'package:mobile_palladin/features/auth/data/models/password_session_model.dart';

void main() {
  group('LoginResponse.fromJson', () {
    test('parses a full session when totpRequired is absent', () {
      final response = LoginResponse.fromJson({
        'accessToken': 'a',
        'refreshToken': 'r',
        'userId': 'u1',
        'isOnboarded': true,
        'emailVerified': false,
      });
      expect(response, isA<LoginSession>());
      final session = (response as LoginSession).session;
      expect(session.userId, 'u1');
      expect(session.emailVerified, isFalse);
    });

    test('parses a TOTP challenge when totpRequired is true', () {
      final response = LoginResponse.fromJson({
        'totpRequired': true,
        'challengeToken': 'chal-123',
      });
      expect(response, isA<LoginTotpRequired>());
      expect((response as LoginTotpRequired).challengeToken, 'chal-123');
    });
  });

  group('PasswordSessionModel.fromJson', () {
    test('defaults emailVerified/isOnboarded to true when absent', () {
      final session = PasswordSessionModel.fromJson({
        'accessToken': 'a',
        'refreshToken': 'r',
        'userId': 'u1',
      });
      expect(session.emailVerified, isTrue);
      expect(session.isOnboarded, isTrue);
    });

    test('honours an explicit emailVerified=false', () {
      final session = PasswordSessionModel.fromJson({
        'accessToken': 'a',
        'refreshToken': 'r',
        'userId': 'u1',
        'isOnboarded': true,
        'emailVerified': false,
      });
      expect(session.emailVerified, isFalse);
    });
  });
}
