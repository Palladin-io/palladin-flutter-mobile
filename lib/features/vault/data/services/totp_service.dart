import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/entities/totp_config.dart';

/// A generated TOTP code and how long the current time-step has left.
class TotpCode {
  const TotpCode({
    required this.code,
    required this.secondsRemaining,
    required this.period,
  });

  /// Zero-padded numeric code (length == config digits).
  final String code;

  /// Whole seconds until the current window rolls over.
  final int secondsRemaining;

  /// The window length the code was generated for.
  final int period;

  /// Fraction of the current window already elapsed, `0.0`–`1.0`. Drives
  /// the countdown ring.
  double get elapsedFraction =>
      period <= 0 ? 0 : (period - secondsRemaining) / period;
}

/// Computes RFC 6238 time-based one-time passwords on-device.
///
/// Pure and stateless — the secret is decoded, used to seed an HMAC, and
/// never retained. Kept out of widgets (spec §2) so the algorithm has a
/// single tested home. Uses the `crypto` package for HMAC-SHA1/256/512 and
/// a local RFC 4648 base32 decoder (no extra dependency).
class TotpService {
  const TotpService();

  /// Generates the code for [config] at [at] (defaults to now).
  ///
  /// Throws [FormatException] when the secret is not valid base32.
  TotpCode generate(TotpConfig config, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final unixSeconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final period = config.period > 0 ? config.period : 30;
    final counter = unixSeconds ~/ period;

    final key = decodeBase32(config.secret);
    final digest = _hmac(config.algorithm, key, _counterBytes(counter));

    // Dynamic truncation (RFC 4226 §5.3).
    final offset = digest[digest.length - 1] & 0x0f;
    final binary = ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);

    final digits = config.digits > 0 ? config.digits : 6;
    final modulo = _pow10(digits);
    final code = (binary % modulo).toString().padLeft(digits, '0');

    final secondsRemaining = period - (unixSeconds % period);
    return TotpCode(
      code: code,
      secondsRemaining: secondsRemaining,
      period: period,
    );
  }

  List<int> _hmac(TotpAlgorithm algorithm, List<int> key, List<int> message) {
    final hash = switch (algorithm) {
      TotpAlgorithm.sha1 => sha1,
      TotpAlgorithm.sha256 => sha256,
      TotpAlgorithm.sha512 => sha512,
    };
    return Hmac(hash, key).convert(message).bytes;
  }

  Uint8List _counterBytes(int counter) {
    final bytes = Uint8List(8);
    var value = counter;
    for (var i = 7; i >= 0; i--) {
      bytes[i] = value & 0xff;
      value >>= 8;
    }
    return bytes;
  }

  int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  /// Decodes an RFC 4648 base32 string (already normalized — uppercase, no
  /// padding). Throws [FormatException] on any non-alphabet character.
  static Uint8List decodeBase32(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final output = <int>[];
    var buffer = 0;
    var bitsLeft = 0;
    for (final char in input.codeUnits) {
      final value = alphabet.indexOf(String.fromCharCode(char));
      if (value < 0) {
        throw const FormatException('Invalid base32 character in TOTP secret');
      }
      buffer = (buffer << 5) | value;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        output.add((buffer >> bitsLeft) & 0xff);
      }
    }
    return Uint8List.fromList(output);
  }
}
