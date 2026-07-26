import 'dart:convert';

import 'app_logger.dart';

/// Lightweight JWT claim reader.
///
/// We only need the payload — signature validation is the backend's
/// job — and only one or two fields at a time, so a dependency on a
/// full JWT library would be overkill.
abstract final class JwtClaims {
  /// Decodes a JWT's payload (the middle segment) into a JSON map.
  /// Returns an empty map on any failure (malformed token, bad base64,
  /// non-JSON payload). The function never throws so callers can use
  /// the result in null-safe expressions without extra guards.
  static Map<String, dynamic> decodePayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return const {};
      final normalised = base64.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalised));
      final payload = json.decode(decoded);
      if (payload is Map<String, dynamic>) return payload;
      return const {};
    } catch (e) {
      AppLogger.w('JwtClaims', 'Failed to decode JWT payload: $e');
      return const {};
    }
  }

  /// Reads the bitwise `permissions` claim emitted by the backend
  /// `TokenService` (see `JwtClaimNames.Permissions = "permissions"`).
  /// Defaults to `0` (Permission.None) when the claim is missing or
  /// not parseable as an int.
  static int permissionsFrom(String token) {
    final payload = decodePayload(token);
    final raw = payload['permissions'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  /// Reads the `email` claim emitted by the backend `TokenService`
  /// (see `JwtClaimNames.Email = "email"`). Returns `null` when the
  /// claim is missing or empty.
  static String? emailFrom(String token) {
    final payload = decodePayload(token);
    final raw = payload['email'];
    if (raw is String && raw.isNotEmpty) return raw;
    return null;
  }

  /// Reads the active tenant identifier used to bind Vault protocol AAD.
  static String? organizationIdFrom(String token) {
    final raw = decodePayload(token)['org_id'];
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  /// Reads the `email_verified` claim emitted by the backend
  /// `TokenService`. Defaults to `true` when the claim is missing so an
  /// OAuth session (always verified) or a token issued before the claim
  /// existed is never wedged behind the verification wall. Accepts both a
  /// JSON boolean and the string `"true"`/`"false"` encodings.
  static bool emailVerifiedFrom(String token) {
    final payload = decodePayload(token);
    final raw = payload['email_verified'];
    if (raw is bool) return raw;
    if (raw is String) return raw.toLowerCase() != 'false';
    return true;
  }
}
