import '../../domain/entities/totp_config.dart';

/// Published GrantPayload V2 source boundary, before encryption to the runtime.
/// This is an independently versioned secret contract, not API response state.
abstract final class GrantTotpSource {
  static const _keys = {'source', 'secret', 'algorithm', 'digits', 'period'};

  /// Converts stored Member configuration, omitting display-only labels.
  /// Unsupported parameters never silently fall back to another algorithm.
  static Map<String, Object?> fromMemberValue(Object value) {
    final Map config;
    if (value is String) {
      final uri = Uri.tryParse(value.trim());
      if (uri == null ||
          uri.scheme != 'otpauth' ||
          uri.host != 'totp' ||
          uri.queryParametersAll.values.any((values) => values.length != 1)) {
        throw const FormatException('Invalid Grant TOTP configuration');
      }
      config = uri.queryParameters;
    } else if (value is Map) {
      config = value;
    } else {
      throw const FormatException('Invalid Grant TOTP configuration');
    }
    final secret = config['secret'];
    final algorithm = config['algorithm'] ?? 'SHA1';
    if (secret is! String || algorithm is! String) {
      throw const FormatException('Invalid Grant TOTP configuration');
    }
    final source = <String, Object?>{
      'source': 'totp',
      'secret': TotpConfig.normalizeSecret(secret),
      'algorithm': algorithm.toUpperCase(),
      'digits': _integer(config['digits'], 6),
      'period': _integer(config['period'], 30),
    };
    validate(source);
    return source;
  }

  /// Rejects sources outside the exact public V2 registry. Does not normalize
  /// protocol values: wire encodings must already be canonical.
  static void validate(Object? value) {
    if (value is! Map ||
        value.length != _keys.length ||
        !value.keys.every(_keys.contains) ||
        value['source'] != 'totp' ||
        !const {'SHA1', 'SHA256', 'SHA512'}.contains(value['algorithm']) ||
        value['digits'] is! int ||
        !const {6, 8}.contains(value['digits']) ||
        value['period'] is! int ||
        (value['period'] as int) < 15 ||
        (value['period'] as int) > 120) {
      throw const FormatException('Invalid Grant TOTP source');
    }
    final secret = value['secret'];
    if (secret is! String ||
        secret.length < 26 ||
        secret.length > 1024 ||
        !RegExp(r'^[A-Z2-7]+$').hasMatch(secret) ||
        !const {0, 2, 4, 5, 7}.contains(secret.length % 8)) {
      throw const FormatException('Invalid Grant TOTP source');
    }
    // RFC 4648: unused bits of the final symbol must be zero. Length above
    // ensures at least 128 decoded bits; no decoded seed buffer is needed.
    final unused = (secret.length * 5) % 8;
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    if ((alphabet.indexOf(secret[secret.length - 1]) & ((1 << unused) - 1)) !=
        0) {
      throw const FormatException('Invalid Grant TOTP source');
    }
  }

  static int _integer(Object? value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is String && RegExp(r'^\d+$').hasMatch(value)) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw const FormatException('Invalid Grant TOTP parameter');
  }
}
