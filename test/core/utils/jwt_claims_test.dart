import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mobile_palladin/core/utils/jwt_claims.dart';

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
  test('malformed token diagnostics never log payload excerpts', () {
    const sentinel = 'synthetic-secret-must-not-be-logged';
    final messages = <String>[];
    void capture(LogEvent event) => messages.add(event.message.toString());
    Logger.addLogListener(capture);
    try {
      final payload = base64Url.encode(
        utf8.encode('{"token":"$sentinel" invalid-json'),
      );
      expect(JwtClaims.decodePayload('header.$payload.signature'), isEmpty);
      expect(messages.join(), contains('Failed to decode JWT payload'));
      expect(messages.join(), isNot(contains(sentinel)));
      expect(messages.join(), isNot(contains(payload)));
    } finally {
      Logger.removeLogListener(capture);
    }
  });
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

  group('JwtClaims.emailVerifiedFrom', () {
    test('reads a boolean email_verified claim', () {
      expect(
        JwtClaims.emailVerifiedFrom(_makeJwt({'email_verified': true})),
        isTrue,
      );
      expect(
        JwtClaims.emailVerifiedFrom(_makeJwt({'email_verified': false})),
        isFalse,
      );
    });

    test('reads a string email_verified claim', () {
      expect(
        JwtClaims.emailVerifiedFrom(_makeJwt({'email_verified': 'false'})),
        isFalse,
      );
      expect(
        JwtClaims.emailVerifiedFrom(_makeJwt({'email_verified': 'true'})),
        isTrue,
      );
    });

    test('defaults to true when the claim is missing or the token is bad', () {
      // A missing claim must never wedge a user behind the verify wall.
      expect(JwtClaims.emailVerifiedFrom(_makeJwt({'sub': 'u1'})), isTrue);
      expect(JwtClaims.emailVerifiedFrom('not-a-jwt'), isTrue);
    });
  });

  group('JwtClaims.organizationIdFrom', () {
    test('reads the existing org_id issuer claim', () {
      expect(
        JwtClaims.organizationIdFrom(_makeJwt({'org_id': 'org-legacy'})),
        'org-legacy',
      );
    });

    test('also reads organization_id during coordinated migration', () {
      expect(
        JwtClaims.organizationIdFrom(
          _makeJwt({'organization_id': 'org-current'}),
        ),
        'org-current',
      );
    });
  });
}
