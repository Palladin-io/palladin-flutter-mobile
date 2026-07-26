import 'dart:convert';
import 'dart:typed_data';

import 'package:unorm_dart/unorm_dart.dart' as unicode;

/// Strict byte encoders used by the frozen Vault protocol 2 contract.
abstract final class VaultProtocolBytes {
  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final RegExp _hex = RegExp(r'^[0-9a-f]*$');
  static final RegExp _base64Url = RegExp(r'^[A-Za-z0-9_-]*$');

  static Uint8List concat(Iterable<Uint8List> parts) {
    final length = parts.fold<int>(0, (total, part) => total + part.length);
    final result = Uint8List(length);
    var offset = 0;
    for (final part in parts) {
      result.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return result;
  }

  static Uint8List u16(int value) {
    if (value < 0 || value > 0xffff) {
      throw const FormatException('u16 out of range');
    }
    return Uint8List(2)..buffer.asByteData().setUint16(0, value);
  }

  static Uint8List u32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw const FormatException('u32 out of range');
    }
    return Uint8List(4)..buffer.asByteData().setUint32(0, value);
  }

  static Uint8List u64(Object value) {
    final text = value.toString();
    final parsed = BigInt.tryParse(text);
    final maximum = (BigInt.one << 64) - BigInt.one;
    if (parsed == null || parsed < BigInt.zero || parsed > maximum) {
      throw const FormatException('u64 out of range');
    }
    if (text != parsed.toString()) {
      throw const FormatException('u64 must be canonical decimal');
    }
    final result = Uint8List(8);
    var remaining = parsed;
    for (var index = 7; index >= 0; index -= 1) {
      result[index] = (remaining & BigInt.from(0xff)).toInt();
      remaining >>= 8;
    }
    return result;
  }

  static Uint8List uuid(String value) {
    if (!_uuid.hasMatch(value)) {
      throw const FormatException(
        'UUID must be canonical lowercase RFC 4122 text',
      );
    }
    return hex(value.replaceAll('-', ''));
  }

  static Uint8List hex(String value) {
    if (value.length.isOdd || !_hex.hasMatch(value)) {
      throw const FormatException('invalid lowercase hex');
    }
    final bytes = Uint8List(value.length ~/ 2);
    for (var index = 0; index < value.length; index += 2) {
      bytes[index ~/ 2] = int.parse(
        value.substring(index, index + 2),
        radix: 16,
      );
    }
    return bytes;
  }

  static String hexEncode(Uint8List value) =>
      value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List base64UrlDecode(String value, {int? maximumBytes}) {
    if (!_base64Url.hasMatch(value) || value.contains('=')) {
      throw const FormatException('invalid unpadded base64url');
    }
    if (maximumBytes != null && value.length > ((maximumBytes * 4 + 2) ~/ 3)) {
      throw const FormatException('base64url payload exceeds limit');
    }
    Uint8List decoded;
    try {
      decoded = base64Url.decode(base64Url.normalize(value));
    } on FormatException {
      throw const FormatException('invalid unpadded base64url');
    }
    if (maximumBytes != null && decoded.length > maximumBytes) {
      throw const FormatException('decoded payload exceeds limit');
    }
    if (base64UrlEncode(decoded) != value) {
      throw const FormatException('non-canonical base64url');
    }
    return decoded;
  }

  static String base64UrlEncode(Uint8List value) =>
      base64Url.encode(value).replaceAll('=', '');

  static Uint8List utf8Encode(String value) {
    if (value.contains('\u0000') || unicode.nfc(value) != value) {
      throw const FormatException('string must be NFC without NUL');
    }
    for (var index = 0; index < value.length; index += 1) {
      final unit = value.codeUnitAt(index);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (index + 1 >= value.length) {
          throw const FormatException('string contains unpaired surrogate');
        }
        final next = value.codeUnitAt(index + 1);
        if (next < 0xdc00 || next > 0xdfff) {
          throw const FormatException('string contains unpaired surrogate');
        }
        index += 1;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('string contains unpaired surrogate');
      }
    }
    return Uint8List.fromList(utf8.encode(value));
  }

  static bool constantTimeEquals(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
