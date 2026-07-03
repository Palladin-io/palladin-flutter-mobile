import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../utils/app_logger.dart';

/// TLS SPKI certificate pinning (CVT-213).
///
/// Enforced through Dio's `IOHttpClientAdapter.validateCertificate`, which
/// runs AFTER the system/CA chain has already been validated and evaluates the
/// leaf certificate. We additionally require the leaf's SubjectPublicKeyInfo
/// (SPKI) SHA-256 to match one of the configured [pins].
///
/// Pinning the SPKI (not the whole certificate) means a routine certificate
/// renewal that keeps the same key pair does NOT break pinning — only a key
/// rotation does, which is why a backup pin is mandatory (see [EnvConfig]).
///
/// When [pins] is empty the check is a NO-OP (system trust only): the prod
/// certificate is not issued yet, and local/staging dev must keep working.
class CertificatePinningService {
  const CertificatePinningService(this.pins);

  /// Base64-encoded SHA-256 SPKI pins. Empty ⇒ pinning disabled.
  final List<String> pins;

  bool get isEnabled => pins.isNotEmpty;

  /// Returns whether [certificate] is acceptable under the pin set.
  ///
  /// - No pins configured ⇒ always `true` (no-op).
  /// - Pins configured ⇒ `true` only if the leaf SPKI hash is pinned. FAILS
  ///   CLOSED: a null cert or an SPKI we cannot parse is rejected.
  bool validateLeaf(X509Certificate? certificate, String host) {
    if (pins.isEmpty) return true;
    if (certificate == null) {
      AppLogger.w('Pinning', 'No leaf certificate for $host');
      return false;
    }
    try {
      final pin = spkiSha256Base64(certificate.der);
      final ok = pins.contains(pin);
      if (!ok) AppLogger.w('Pinning', 'Pin mismatch for $host');
      return ok;
    } catch (e) {
      AppLogger.w('Pinning', 'SPKI extraction failed for $host: ${e.runtimeType}');
      return false;
    }
  }

  /// Computes the base64 SHA-256 of the certificate's SPKI, in the same form
  /// as `openssl ... | openssl dgst -sha256 -binary | openssl enc -base64`.
  static String spkiSha256Base64(Uint8List der) {
    final spki = _subjectPublicKeyInfo(der);
    return base64.encode(sha256.convert(spki).bytes);
  }

  /// Extracts the DER-encoded SubjectPublicKeyInfo element from an X.509
  /// certificate via a minimal ASN.1 walk.
  ///
  /// Certificate ::= SEQUENCE { tbsCertificate SEQUENCE {...}, ... }
  /// TBSCertificate ::= SEQUENCE {
  ///   [0] version OPTIONAL, serialNumber, signature, issuer, validity,
  ///   subject, subjectPublicKeyInfo, ... }
  static Uint8List _subjectPublicKeyInfo(Uint8List der) {
    final certificate = _readElement(der, 0); // outer SEQUENCE
    if (certificate.tag != 0x30) {
      throw const FormatException('Certificate is not a SEQUENCE');
    }
    final tbs = _readElement(der, certificate.contentStart); // tbsCertificate
    var offset = tbs.contentStart;

    // Skip the optional explicit [0] version (context tag 0xA0).
    final first = _readElement(der, offset);
    if (first.tag == 0xA0) offset = first.end;

    // Skip serialNumber, signature, issuer, validity, subject (5 elements);
    // subjectPublicKeyInfo is next.
    for (var i = 0; i < 5; i++) {
      offset = _readElement(der, offset).end;
    }

    final spki = _readElement(der, offset);
    if (spki.tag != 0x30) {
      throw const FormatException('SubjectPublicKeyInfo is not a SEQUENCE');
    }
    return Uint8List.sublistView(der, spki.start, spki.end);
  }

  /// Reads one ASN.1 DER TLV element starting at [start].
  static _Asn1Element _readElement(Uint8List der, int start) {
    if (start + 1 >= der.length) {
      throw const FormatException('Truncated ASN.1 element');
    }
    final tag = der[start];
    final lengthByte = der[start + 1];
    int contentStart;
    int length;
    if (lengthByte < 0x80) {
      length = lengthByte;
      contentStart = start + 2;
    } else {
      final numBytes = lengthByte & 0x7f;
      if (numBytes == 0 || numBytes > 4 || start + 2 + numBytes > der.length) {
        throw const FormatException('Invalid ASN.1 length');
      }
      length = 0;
      for (var i = 0; i < numBytes; i++) {
        length = (length << 8) | der[start + 2 + i];
      }
      contentStart = start + 2 + numBytes;
    }
    final end = contentStart + length;
    if (end > der.length) {
      throw const FormatException('ASN.1 length exceeds buffer');
    }
    return _Asn1Element(tag: tag, start: start, contentStart: contentStart, end: end);
  }
}

class _Asn1Element {
  const _Asn1Element({
    required this.tag,
    required this.start,
    required this.contentStart,
    required this.end,
  });

  final int tag;
  final int start;
  final int contentStart;
  final int end;
}
