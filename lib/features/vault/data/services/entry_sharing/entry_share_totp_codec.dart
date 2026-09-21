import '../../../domain/entities/entry_share_copy.dart';

/// Unlike the legacy form parser, never repairs unsupported algorithms/values.
final class EntryShareTotpCodec {
  const EntryShareTotpCodec();

  Map<String, Object?> decode(String value) {
    try {
      return Map.unmodifiable(_decode(value));
    } catch (_) {
      throw const EntryShareCopyInputException(
        EntryShareCopyInputError.invalidTotp,
      );
    }
  }

  Map<String, Object?> _decode(String value) {
    const invalid = EntryShareCopyInputException(
      EntryShareCopyInputError.invalidTotp,
    );
    if (RegExp(r'^[A-Z2-7]+$').hasMatch(value)) {
      return {'secret': value, 'algorithm': 'SHA1', 'digits': 6, 'period': 30};
    }
    if (!value.startsWith('otpauth://totp/')) throw invalid;
    final uri = Uri.parse(value);
    if (uri.scheme != 'otpauth' ||
        uri.host != 'totp' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment ||
        uri.pathSegments.length > 1) {
      throw invalid;
    }
    final query = uri.queryParametersAll;
    if (query.keys.any(
          (key) => !{
            'secret',
            'algorithm',
            'digits',
            'period',
            'issuer',
          }.contains(key),
        ) ||
        query.values.any((values) => values.length != 1)) {
      throw invalid;
    }
    final secret = query['secret']?.single;
    final algorithm = query['algorithm']?.single ?? 'SHA1';
    final digits = query['digits']?.single ?? '6';
    final period = query['period']?.single ?? '30';
    final parsedPeriod = int.tryParse(period);
    if (secret == null ||
        !RegExp(r'^[A-Z2-7]+$').hasMatch(secret) ||
        !{'SHA1', 'SHA256', 'SHA512'}.contains(algorithm) ||
        !{'6', '8'}.contains(digits) ||
        parsedPeriod == null ||
        parsedPeriod.toString() != period ||
        parsedPeriod < 15 ||
        parsedPeriod > 120) {
      throw invalid;
    }
    // pathSegments are decoded once by Uri; decoding again changes '%25…' data.
    final label = uri.pathSegments.isEmpty ? '' : uri.pathSegments.single;
    final queryIssuer = query['issuer']?.single;
    String? issuer = queryIssuer;
    String account = label;
    if (queryIssuer != null && queryIssuer.isNotEmpty) {
      if (label.startsWith('$queryIssuer:')) {
        account = label.substring(queryIssuer.length + 1);
      } else if (label.contains(':')) {
        throw invalid;
      }
    } else if (queryIssuer == null && label.contains(':')) {
      final separator = label.indexOf(':');
      issuer = label.substring(0, separator);
      account = label.substring(separator + 1);
    }
    return {
      'secret': secret,
      'algorithm': algorithm,
      'digits': int.parse(digits),
      'period': parsedPeriod,
      'issuer': ?issuer,
      'account': account,
    };
  }
}
