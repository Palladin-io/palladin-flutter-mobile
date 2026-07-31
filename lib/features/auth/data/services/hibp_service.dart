import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';

/// Checks a candidate password against the Have I Been Pwned "Pwned
/// Passwords" corpus using the **k-anonymity** range API.
///
/// Zero-knowledge boundary: the password never leaves the device. We
/// SHA-1 it locally and send only the **first 5 hex characters** of the
/// digest to `api.pwnedpasswords.com/range/{prefix}`; the service
/// returns every suffix seen for that prefix and we match the remaining
/// 35 characters locally. HIBP therefore never learns which password (or
/// even which full hash) was checked.
///
/// This is a best-effort UX guard, not a security gate — a network
/// failure returns [HibpResult.unknown] and the caller must never block
/// registration on it. The password and its full hash are never logged.
class HibpService {
  HibpService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
              // Opt into HIBP's padding so response sizes don't leak the
              // prefix's hit count to a network observer.
              headers: const {'Add-Padding': 'true'},
              responseType: ResponseType.plain,
            ),
          );

  final Dio _dio;

  static const _baseUrl = 'https://api.pwnedpasswords.com';

  /// Returns whether [password] appears in a known breach corpus.
  ///
  /// Never throws — on any failure returns [HibpResult.unknown] so the
  /// caller can proceed without a breach signal.
  Future<HibpResult> check(String password) async {
    if (password.isEmpty) return HibpResult.unknown;

    final digest = sha1.convert(utf8.encode(password)).toString().toUpperCase();
    final prefix = digest.substring(0, 5);
    final suffix = digest.substring(5);

    try {
      final response = await _dio.get<String>('/range/$prefix');
      final body = response.data;
      if (body == null || body.isEmpty) return HibpResult.notFound;
      return _containsSuffix(body, suffix)
          ? HibpResult.pwned
          : HibpResult.notFound;
    } catch (e) {
      // Log only the failure type — never the password or its hash.
      AppLogger.w('Hibp', 'Breach check skipped: ${e.runtimeType}');
      return HibpResult.unknown;
    }
  }

  /// Scans the `SUFFIX:COUNT` lines for an exact [suffix] match. HIBP's
  /// padded rows carry a count of `0`, which we treat as "not present".
  bool _containsSuffix(String body, String suffix) {
    for (final line in body.split('\n')) {
      final sep = line.indexOf(':');
      if (sep <= 0) continue;
      if (line.substring(0, sep).trim().toUpperCase() != suffix) continue;
      final count = int.tryParse(line.substring(sep + 1).trim()) ?? 0;
      return count > 0;
    }
    return false;
  }
}

/// Outcome of a [HibpService.check].
enum HibpResult {
  /// The password was found in a breach corpus — warn the user.
  pwned,

  /// The password was not found in the corpus.
  notFound,

  /// The check could not be completed (network/timeout) — no signal.
  unknown,
}
