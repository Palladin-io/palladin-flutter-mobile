import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/services/totp_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/totp_config.dart';

/// RFC 4648 base32 encoder — used only to derive the canonical base32
/// secret from the RFC 6238 ASCII seeds, so the test vectors stay
/// authoritative and we don't hand-type long base32 strings.
String _base32Encode(List<int> bytes) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bits = 0;
  final sb = StringBuffer();
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      sb.write(alphabet[(buffer >> bits) & 0x1f]);
    }
  }
  if (bits > 0) {
    sb.write(alphabet[(buffer << (5 - bits)) & 0x1f]);
  }
  return sb.toString();
}

void main() {
  const service = TotpService();

  // RFC 6238 Appendix B canonical seeds.
  final sha1Secret = _base32Encode('12345678901234567890'.codeUnits);
  final sha256Secret =
      _base32Encode('12345678901234567890123456789012'.codeUnits);
  final sha512Secret = _base32Encode(
    '1234567890123456789012345678901234567890123456789012345678901234'
        .codeUnits,
  );

  TotpCode codeAt(TotpConfig config, int unixSeconds) => service.generate(
        config,
        at: DateTime.fromMillisecondsSinceEpoch(
          unixSeconds * 1000,
          isUtc: true,
        ),
      );

  group('TotpService — RFC 6238 test vectors (8 digits, 30s)', () {
    // Time → expected 8-digit code per algorithm (RFC 6238 Appendix B).
    const vectors = <int, ({String sha1, String sha256, String sha512})>{
      59: (sha1: '94287082', sha256: '46119246', sha512: '90693936'),
      1111111109: (sha1: '07081804', sha256: '68084774', sha512: '25091201'),
      1111111111: (sha1: '14050471', sha256: '67062674', sha512: '99943326'),
      1234567890: (sha1: '89005924', sha256: '91819424', sha512: '93441116'),
      2000000000: (sha1: '69279037', sha256: '90698825', sha512: '38618901'),
      20000000000: (sha1: '65353130', sha256: '77737706', sha512: '47863826'),
    };

    for (final entry in vectors.entries) {
      final t = entry.key;
      test('T=$t SHA1', () {
        final config = TotpConfig(
          secret: sha1Secret,
          algorithm: TotpAlgorithm.sha1,
          digits: 8,
        );
        expect(codeAt(config, t).code, entry.value.sha1);
      });
      test('T=$t SHA256', () {
        final config = TotpConfig(
          secret: sha256Secret,
          algorithm: TotpAlgorithm.sha256,
          digits: 8,
        );
        expect(codeAt(config, t).code, entry.value.sha256);
      });
      test('T=$t SHA512', () {
        final config = TotpConfig(
          secret: sha512Secret,
          algorithm: TotpAlgorithm.sha512,
          digits: 8,
        );
        expect(codeAt(config, t).code, entry.value.sha512);
      });
    }
  });

  group('TotpService — code shape and window', () {
    test('6-digit default is the last 6 of the 8-digit vector', () {
      final config = TotpConfig(secret: sha1Secret);
      // At T=59 the 8-digit code is 94287082 → 6-digit is 287082.
      expect(codeAt(config, 59).code, '287082');
      expect(codeAt(config, 59).code.length, 6);
    });

    test('secondsRemaining counts down within a window', () {
      final config = TotpConfig(secret: sha1Secret);
      // 5 seconds into a 30s window → 25 remaining.
      expect(codeAt(config, 65).secondsRemaining, 25);
      // Boundary → full window remaining.
      expect(codeAt(config, 60).secondsRemaining, 30);
    });

    test('elapsedFraction is within [0,1]', () {
      final config = TotpConfig(secret: sha1Secret);
      final code = codeAt(config, 75);
      expect(code.elapsedFraction, greaterThanOrEqualTo(0));
      expect(code.elapsedFraction, lessThanOrEqualTo(1));
    });

    test('invalid base32 secret throws FormatException', () {
      const config = TotpConfig(secret: '0189!'); // 0,1,8,9,! not in alphabet
      expect(() => service.generate(config), throwsFormatException);
    });
  });

  group('TotpConfig parsing', () {
    test('parses a full otpauth URI', () {
      final config = TotpConfig.parseUri(
        'otpauth://totp/GitHub:alice@example.com'
        '?secret=$sha1Secret&issuer=GitHub&algorithm=SHA256&digits=8&period=60',
      );
      expect(config, isNotNull);
      expect(config!.secret, sha1Secret);
      expect(config.algorithm, TotpAlgorithm.sha256);
      expect(config.digits, 8);
      expect(config.period, 60);
      expect(config.issuer, 'GitHub');
      expect(config.account, 'alice@example.com');
    });

    test('applies RFC defaults for a minimal URI', () {
      final config =
          TotpConfig.parseUri('otpauth://totp/Acme?secret=$sha1Secret');
      expect(config, isNotNull);
      expect(config!.algorithm, TotpAlgorithm.sha1);
      expect(config.digits, 6);
      expect(config.period, 30);
    });

    test('rejects hotp and non-otpauth URIs', () {
      expect(TotpConfig.parseUri('otpauth://hotp/A?secret=$sha1Secret'), isNull);
      expect(TotpConfig.parseUri('https://example.com'), isNull);
      expect(TotpConfig.parseUri('otpauth://totp/A?secret=!!!'), isNull);
    });

    test('normalizes spaced/lowercase/padded secrets', () {
      final config = TotpConfig.fromSecret('gezd gnbv gy3t qojq');
      expect(config, isNotNull);
      expect(config!.secret, 'GEZDGNBVGY3TQOJQ');
    });

    test('fromSecret rejects invalid base32', () {
      expect(TotpConfig.fromSecret('not-base32-0189'), isNull);
    });
  });
}
