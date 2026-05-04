import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/core/utils/jwt_claims.dart';

/// Builds a syntactically valid JWT (header.payload.signature) carrying
/// the given claims. We never validate the signature — the backend does
/// — so an empty signature segment is fine for the unit tests.
String _makeJwt(Map<String, Object?> payload) {
  String encode(Map<String, Object?> map) {
    final raw = utf8.encode(json.encode(map));
    return base64Url.encode(raw).replaceAll('=', '');
  }

  final header = encode({'alg': 'HS256', 'typ': 'JWT'});
  final body = encode(payload);
  return '$header.$body.'; // empty signature
}

void main() {
  group('JwtClaims.permissionsFrom', () {
    test('returns the integer permissions claim', () {
      // 256 = PERMISSION_MULTIPLE_VAULTS in the cross-platform contract.
      final token = _makeJwt({'permissions': '256'});

      expect(JwtClaims.permissionsFrom(token), 256);
    });

    test('accepts a numeric (non-string) permissions claim', () {
      final token = _makeJwt({'permissions': 7});

      expect(JwtClaims.permissionsFrom(token), 7);
    });

    test('returns 0 when the claim is missing', () {
      final token = _makeJwt({'sub': 'user-1'});

      expect(JwtClaims.permissionsFrom(token), 0);
    });

    test('returns 0 when the token is malformed', () {
      expect(JwtClaims.permissionsFrom('not-a-jwt'), 0);
      expect(JwtClaims.permissionsFrom(''), 0);
      expect(JwtClaims.permissionsFrom('only.two'), 0);
    });

    test('returns 0 when the payload is non-numeric', () {
      final token = _makeJwt({'permissions': 'not-a-number'});

      expect(JwtClaims.permissionsFrom(token), 0);
    });
  });
}
