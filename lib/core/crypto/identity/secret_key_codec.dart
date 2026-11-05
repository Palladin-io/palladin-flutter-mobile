import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Typed Secret Key input failures from `identity-kdf/v3`.
enum SecretKeyFormatError { malformed, checksumMismatch, accountMismatch }

class SecretKeyFormatException implements Exception {
  const SecretKeyFormatException(this.error);
  final SecretKeyFormatError error;
}

/// `PSK2` display string and Emergency Kit QR encodings of the Account Secret.
abstract final class SecretKeyCodec {
  static const accountSecretBytes = 32;
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const _kitPrefix = 'palladin-kit:v1:';

  /// `PSK2-` + nine groups of six Crockford base32 symbols.
  static String format(String accountId, Uint8List accountSecret) {
    _requireSecret(accountSecret);
    var value = BigInt.zero;
    for (final byte in accountSecret) {
      value = (value << 8) | BigInt.from(byte);
    }
    value <<= 4;
    final body = StringBuffer();
    for (var index = 51; index >= 0; index--) {
      body.write(_alphabet[((value >> (index * 5)) & BigInt.from(31)).toInt()]);
    }
    final symbols = '$body${_checksum(accountId, accountSecret)}';
    final groups = [
      for (var i = 0; i < symbols.length; i += 6) symbols.substring(i, i + 6),
    ];
    return 'PSK2-${groups.join('-')}';
  }

  /// Parses user input bound to the account being unlocked; never derives
  /// from malformed input.
  static Uint8List parse(String accountId, String display) {
    final normalized = display
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    if (!normalized.startsWith('PSK2')) {
      throw const SecretKeyFormatException(SecretKeyFormatError.malformed);
    }
    final symbols = normalized.substring(4);
    if (symbols.length != 54 ||
        symbols.split('').any((symbol) => !_alphabet.contains(symbol))) {
      throw const SecretKeyFormatException(SecretKeyFormatError.malformed);
    }
    var value = BigInt.zero;
    for (final symbol in symbols.substring(0, 52).split('')) {
      value = (value << 5) | BigInt.from(_alphabet.indexOf(symbol));
    }
    if (value & BigInt.from(0xf) != BigInt.zero) {
      throw const SecretKeyFormatException(SecretKeyFormatError.malformed);
    }
    value >>= 4;
    final secret = Uint8List(accountSecretBytes);
    for (var index = accountSecretBytes - 1; index >= 0; index--) {
      secret[index] = (value & BigInt.from(0xff)).toInt();
      value >>= 8;
    }
    if (_checksum(accountId, secret) != symbols.substring(52)) {
      secret.fillRange(0, secret.length, 0);
      throw const SecretKeyFormatException(
        SecretKeyFormatError.checksumMismatch,
      );
    }
    return secret;
  }

  /// `palladin-kit:v1:` QR payload printed in the Emergency Kit.
  static String emergencyKitQr(String accountId, Uint8List accountSecret) {
    _requireSecret(accountSecret);
    return '$_kitPrefix${_b64(_uuidBytes(accountId))}.${_b64(accountSecret)}';
  }

  /// Parses a scanned kit QR for exactly [expectedAccountId].
  static Uint8List parseEmergencyKitQr(String expectedAccountId, String raw) {
    if (!raw.startsWith(_kitPrefix)) {
      throw const SecretKeyFormatException(SecretKeyFormatError.malformed);
    }
    final parts = raw.substring(_kitPrefix.length).split('.');
    if (parts.length != 2) {
      throw const SecretKeyFormatException(SecretKeyFormatError.malformed);
    }
    final accountId = _decodeCanonical(parts[0], 16);
    final secret = _decodeCanonical(parts[1], accountSecretBytes);
    final expected = _uuidBytes(expectedAccountId);
    var difference = 0;
    for (var i = 0; i < 16; i++) {
      difference |= accountId[i] ^ expected[i];
    }
    if (difference != 0) {
      secret.fillRange(0, secret.length, 0);
      throw const SecretKeyFormatException(
        SecretKeyFormatError.accountMismatch,
      );
    }
    return secret;
  }

  static String _checksum(String accountId, Uint8List secret) {
    final digest = sha256.convert([
      ...ascii.encode('PLDNSK2CHK'),
      ..._uuidBytes(accountId),
      ...secret,
    ]).bytes;
    final tenBits = (digest[0] << 2) | (digest[1] >> 6);
    return '${_alphabet[tenBits >> 5]}${_alphabet[tenBits & 31]}';
  }

  static void _requireSecret(Uint8List secret) {
    if (secret.length != accountSecretBytes) {
      throw const SecretKeyFormatException(SecretKeyFormatError.malformed);
    }
  }

  static Uint8List _decodeCanonical(String value, int length) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const SecretKeyFormatException(SecretKeyFormatError.malformed);
    }
    try {
      final bytes = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(value)),
      );
      if (bytes.length == length && _b64(bytes) == value) return bytes;
    } on FormatException {
      // Reported below as a malformed payload.
    }
    throw const SecretKeyFormatException(SecretKeyFormatError.malformed);
  }
}

Uint8List _uuidBytes(String value) {
  final hex = value.replaceAll('-', '');
  if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hex)) {
    throw const SecretKeyFormatException(SecretKeyFormatError.malformed);
  }
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
