import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../utils/app_logger.dart';

/// Pins the leaf SPKI SHA-256 against [pins]; empty [pins] disables pinning.
class CertificatePinningService {
  const CertificatePinningService(this.pins);

  /// Base64-encoded SHA-256 SPKI pins. Empty ⇒ pinning disabled.
  final List<String> pins;

  bool get isEnabled => pins.isNotEmpty;

  /// Accepts the leaf only if its SPKI hash is pinned; fails closed on a null
  /// or unparseable cert. No pins ⇒ always accepts.
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

  /// Base64 SHA-256 of the certificate's SPKI.
  static String spkiSha256Base64(Uint8List der) {
    final spki = _subjectPublicKeyInfo(der);
    return base64.encode(sha256.convert(spki).bytes);
  }

  /// Extracts the DER SubjectPublicKeyInfo from an X.509 cert via a minimal
  /// ASN.1 walk (skip version, serial, signature, issuer, validity, subject).
  static Uint8List _subjectPublicKeyInfo(Uint8List der) {
    final certificate = _readElement(der, 0);
    if (certificate.tag != 0x30) {
      throw const FormatException('Certificate is not a SEQUENCE');
    }
    final tbs = _readElement(der, certificate.contentStart);
    var offset = tbs.contentStart;

    final first = _readElement(der, offset);
    if (first.tag == 0xA0) offset = first.end;

    for (var i = 0; i < 5; i++) {
      offset = _readElement(der, offset).end;
    }

    final spki = _readElement(der, offset);
    if (spki.tag != 0x30) {
      throw const FormatException('SubjectPublicKeyInfo is not a SEQUENCE');
    }
    return Uint8List.sublistView(der, spki.start, spki.end);
  }

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
