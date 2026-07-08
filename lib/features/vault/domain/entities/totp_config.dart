/// HMAC algorithm backing a TOTP field. Wire values are the uppercase
/// tokens used inside `otpauth://` URIs and the encrypted blob.
enum TotpAlgorithm {
  sha1,
  sha256,
  sha512;

  /// Wire token (`SHA1` / `SHA256` / `SHA512`).
  String get wireName => switch (this) {
        TotpAlgorithm.sha1 => 'SHA1',
        TotpAlgorithm.sha256 => 'SHA256',
        TotpAlgorithm.sha512 => 'SHA512',
      };

  /// Parses an algorithm token (case-insensitive). Falls back to
  /// [TotpAlgorithm.sha1] — the RFC 6238 default — for missing or unknown
  /// input so an authenticator that omits the parameter still works.
  static TotpAlgorithm fromName(String? raw) => switch (raw?.toUpperCase()) {
        'SHA256' => TotpAlgorithm.sha256,
        'SHA512' => TotpAlgorithm.sha512,
        _ => TotpAlgorithm.sha1,
      };
}

/// Parsed configuration for a time-based one-time-password field.
///
/// Stored inside the encrypted blob as the `value` of a `totp` custom
/// field — never the raw `otpauth://` URI, so we don't re-parse it on
/// every render. Lives in plaintext only in memory after decryption.
class TotpConfig {
  const TotpConfig({
    required this.secret,
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.issuer,
    this.account,
  });

  /// Shared secret, base32-encoded (RFC 4648, no padding). Treated as a
  /// secret — never logged.
  final String secret;

  final TotpAlgorithm algorithm;

  /// Number of digits in the generated code (6 or 8 in practice).
  final int digits;

  /// Length of the time step in seconds.
  final int period;

  /// Optional issuer label (`GitHub`), used only for display.
  final String? issuer;

  /// Optional account label (`user@example.com`), used only for display.
  final String? account;

  TotpConfig copyWith({
    String? secret,
    TotpAlgorithm? algorithm,
    int? digits,
    int? period,
    String? issuer,
    String? account,
  }) =>
      TotpConfig(
        secret: secret ?? this.secret,
        algorithm: algorithm ?? this.algorithm,
        digits: digits ?? this.digits,
        period: period ?? this.period,
        issuer: issuer ?? this.issuer,
        account: account ?? this.account,
      );

  Map<String, dynamic> toJson() => {
        'secret': secret,
        'algorithm': algorithm.wireName,
        'digits': digits,
        'period': period,
        if (issuer != null && issuer!.isNotEmpty) 'issuer': issuer,
        if (account != null && account!.isNotEmpty) 'account': account,
      };

  factory TotpConfig.fromJson(Map<String, dynamic> json) => TotpConfig(
        secret: normalizeSecret((json['secret'] as String?) ?? ''),
        algorithm: TotpAlgorithm.fromName(json['algorithm'] as String?),
        digits: _asPositiveInt(json['digits'], fallback: 6),
        period: _asPositiveInt(json['period'], fallback: 30),
        issuer: (json['issuer'] as String?)?.trim(),
        account: (json['account'] as String?)?.trim(),
      );

  /// Builds a config from a raw base32 [secret] using RFC 6238 defaults
  /// (SHA1 / 6 digits / 30 s). Returns null when the secret is not valid
  /// base32.
  static TotpConfig? fromSecret(
    String secret, {
    String? issuer,
    String? account,
  }) {
    final normalized = normalizeSecret(secret);
    if (!isValidBase32(normalized)) return null;
    return TotpConfig(
      secret: normalized,
      issuer: issuer?.trim(),
      account: account?.trim(),
    );
  }

  /// Parses an `otpauth://totp/...` URI into a [TotpConfig].
  ///
  /// Returns null when the URI is not a TOTP otpauth URI or is missing a
  /// valid base32 secret. `hotp` (counter-based) URIs are rejected — this
  /// app only supports time-based codes.
  static TotpConfig? parseUri(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    if (uri.scheme.toLowerCase() != 'otpauth') return null;
    if (uri.host.toLowerCase() != 'totp') return null;

    final secretParam = uri.queryParameters['secret'];
    if (secretParam == null) return null;
    final normalized = normalizeSecret(secretParam);
    if (!isValidBase32(normalized)) return null;

    // Label path is `/issuerPrefix:account` (issuer prefix optional).
    final label = uri.pathSegments.isNotEmpty
        ? Uri.decodeComponent(uri.pathSegments.first)
        : '';
    String? labelIssuer;
    String? account;
    if (label.isNotEmpty) {
      final sep = label.indexOf(':');
      if (sep >= 0) {
        labelIssuer = label.substring(0, sep).trim();
        account = label.substring(sep + 1).trim();
      } else {
        account = label.trim();
      }
    }

    final issuerParam = uri.queryParameters['issuer']?.trim();
    return TotpConfig(
      secret: normalized,
      algorithm: TotpAlgorithm.fromName(uri.queryParameters['algorithm']),
      digits: _asPositiveInt(uri.queryParameters['digits'], fallback: 6),
      period: _asPositiveInt(uri.queryParameters['period'], fallback: 30),
      issuer: (issuerParam != null && issuerParam.isNotEmpty)
          ? issuerParam
          : (labelIssuer != null && labelIssuer.isNotEmpty
              ? labelIssuer
              : null),
      account: (account != null && account.isNotEmpty) ? account : null,
    );
  }

  /// Uppercases and strips spaces and `=` padding from a base32 secret so
  /// pasted / scanned values normalize to a single canonical form.
  static String normalizeSecret(String raw) =>
      raw.replaceAll(RegExp(r'[\s=]'), '').toUpperCase();

  /// True when [value] contains only RFC 4648 base32 characters (A–Z, 2–7)
  /// and is non-empty. Expects an already-[normalizeSecret]d string.
  static bool isValidBase32(String value) =>
      value.isNotEmpty && RegExp(r'^[A-Z2-7]+$').hasMatch(value);

  static int _asPositiveInt(Object? raw, {required int fallback}) {
    if (raw is int && raw > 0) return raw;
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed > 0) return parsed;
    }
    return fallback;
  }
}
