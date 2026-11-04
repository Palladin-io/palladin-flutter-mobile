import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../kem/xwing.dart';
import '../key_wrapper/key_wrapper.dart';
import '../sodium_provider.dart';

/// Rejections from `identity-kdf/v3` `devicePairing.reject`.
enum DevicePairingError {
  malformedQr,
  recipientKeyDigestMismatch,
  challengeMismatch,
  malformedEnvelope,
  aeadFailure,
}

class DevicePairingException implements Exception {
  const DevicePairingException(this.error);
  final DevicePairingError error;
}

/// Which device shows the QR code.
enum PairingQrRole { recipientShows, senderShows }

/// Parsed `palladin-pair:v2:` QR payload.
final class PairingQr {
  PairingQr._(this.role, this.transferId, this.binding);

  final PairingQrRole role;

  /// 16-byte transfer id, encoded as unpadded base64url on the wire.
  final String transferId;

  /// `SHA-256(recipientPublicKey)` (recipient shows) or the server challenge
  /// (sender shows), as decoded bytes.
  final Uint8List binding;

  static const _recipientPrefix = 'palladin-pair:v2:r:';
  static const _senderPrefix = 'palladin-pair:v2:s:';

  static String recipientShows(String transferId, Uint8List recipientKey) =>
      '$_recipientPrefix$transferId.${_b64(sha256.convert(recipientKey).bytes)}';

  static String senderShows(String transferId, Uint8List challenge) =>
      '$_senderPrefix$transferId.${_b64(challenge)}';

  static PairingQr parse(String raw) {
    final (role, rest) = raw.startsWith(_recipientPrefix)
        ? (PairingQrRole.recipientShows, raw.substring(_recipientPrefix.length))
        : raw.startsWith(_senderPrefix)
        ? (PairingQrRole.senderShows, raw.substring(_senderPrefix.length))
        : throw const DevicePairingException(DevicePairingError.malformedQr);
    final parts = rest.split('.');
    if (parts.length != 2) {
      throw const DevicePairingException(DevicePairingError.malformedQr);
    }
    _decode(parts[0], 16, DevicePairingError.malformedQr);
    return PairingQr._(
      role,
      parts[0],
      _decode(parts[1], 32, DevicePairingError.malformedQr),
    );
  }
}

/// Offer both devices display as a SAS before the Secret Key is sealed.
final class PairingOffer {
  PairingOffer._(
    this.accountId,
    this._transferId,
    this._challenge,
    this._digest,
  );

  /// Builds the offer from backend session state, checking it against the
  /// independently scanned QR so a substituted key or challenge creates no
  /// envelope.
  factory PairingOffer.verify({
    required String accountId,
    required String transferId,
    required Uint8List challenge,
    required Uint8List recipientPublicKey,
    required PairingQr scanned,
  }) {
    if (recipientPublicKey.length != XWing.publicKeyBytes ||
        challenge.length != 32 ||
        scanned.transferId != transferId) {
      throw const DevicePairingException(DevicePairingError.malformedEnvelope);
    }
    final digest = Uint8List.fromList(sha256.convert(recipientPublicKey).bytes);
    switch (scanned.role) {
      case PairingQrRole.recipientShows when !_equal(scanned.binding, digest):
        throw const DevicePairingException(
          DevicePairingError.recipientKeyDigestMismatch,
        );
      case PairingQrRole.senderShows when !_equal(scanned.binding, challenge):
        throw const DevicePairingException(
          DevicePairingError.challengeMismatch,
        );
      default:
        break;
    }
    return PairingOffer._(
      accountId,
      _decode(transferId, 16, DevicePairingError.malformedQr),
      Uint8List.fromList(challenge),
      digest,
    );
  }

  /// Recipient-side offer over its own in-memory key.
  factory PairingOffer.forRecipient({
    required String accountId,
    required String transferId,
    required Uint8List challenge,
    required Uint8List recipientPublicKey,
  }) => PairingOffer._(
    accountId,
    _decode(transferId, 16, DevicePairingError.malformedQr),
    Uint8List.fromList(challenge),
    Uint8List.fromList(sha256.convert(recipientPublicKey).bytes),
  );

  final String accountId;
  final Uint8List _transferId;
  final Uint8List _challenge;
  final Uint8List _digest;

  Uint8List get offerBytes => Uint8List.fromList([
    ...ascii.encode('PLDNID3DO'),
    ..._u16(2),
    ..._uuidBytes(accountId),
    ..._transferId,
    ..._challenge,
    ..._digest,
  ]);

  /// First 50 bits of `SHA-256(offerBytes)`, lowercase Crockford, `5-5`.
  String get sas {
    final digest = sha256.convert(offerBytes).bytes;
    var value = 0;
    for (final byte in digest.sublist(0, 7)) {
      value = (value << 8) | byte;
    }
    value >>= 6;
    const alphabet = '0123456789abcdefghjkmnpqrstvwxyz';
    final out = StringBuffer();
    for (var index = 9; index >= 0; index--) {
      out.write(alphabet[(value >> (index * 5)) & 31]);
    }
    final text = out.toString();
    return '${text.substring(0, 5)}-${text.substring(5)}';
  }

  Uint8List _transcriptHash(Uint8List kemCiphertext) => Uint8List.fromList(
    sha256.convert([
      ...ascii.encode('PLDNID3DT'),
      ..._u16(2),
      ..._uuidBytes(accountId),
      ..._transferId,
      ..._challenge,
      ..._digest,
      ...sha256.convert(kemCiphertext).bytes,
    ]).bytes,
  );
}

/// Marker that the user compared the SAS on both devices.
final class ConfirmedPairingOffer {
  const ConfirmedPairingOffer(this.offer);
  final PairingOffer offer;
}

/// Wire envelope `{kemCiphertext, ciphertext}`.
final class PairingEnvelope {
  const PairingEnvelope({
    required this.kemCiphertext,
    required this.ciphertext,
  });
  final String kemCiphertext;
  final String ciphertext;
}

/// Seals and opens the Account Secret for device-to-device transfer.
class DevicePairingCrypto {
  DevicePairingCrypto({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;
  static const _kekInfo = 'palladin:identity:v3:device-pairing-account-secret';

  /// Fresh single-use recipient key pair kept in memory only.
  Future<(Uint8List seed, Uint8List publicKey)> generateRecipientKey() async {
    final xwing = XWing(await _sodiumLoader());
    final seed = xwing.generateSeed();
    return (seed, xwing.publicKeyFromSeed(seed));
  }

  Future<PairingEnvelope> seal({
    required ConfirmedPairingOffer confirmed,
    required Uint8List recipientPublicKey,
    required Uint8List accountSecret,
    Uint8List? encapsulationRandomness,
  }) async {
    final offer = confirmed.offer;
    if (accountSecret.length != 32 ||
        !_equal(sha256.convert(recipientPublicKey).bytes, offer._digest)) {
      throw const DevicePairingException(
        DevicePairingError.recipientKeyDigestMismatch,
      );
    }
    final sodium = await _sodiumLoader();
    final xwing = XWing(sodium);
    final (sharedSecret, kemCiphertext) = encapsulationRandomness == null
        ? xwing.encapsulate(recipientPublicKey)
        : xwing.encapsulateDerandomized(
            recipientPublicKey,
            encapsulationRandomness,
          );
    final transcript = offer._transcriptHash(kemCiphertext);
    final kek = hkdfSha256(
      ikm: sharedSecret,
      salt: transcript,
      info: Uint8List.fromList(ascii.encode(_kekInfo)),
    );
    final key = SecureKey.fromList(sodium, kek);
    try {
      final ciphertext = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
        message: accountSecret,
        nonce: Uint8List(24),
        key: key,
        additionalData: _aad(transcript),
      );
      return PairingEnvelope(
        kemCiphertext: _b64(kemCiphertext),
        ciphertext: _b64(ciphertext),
      );
    } finally {
      key.dispose();
      sharedSecret.fillRange(0, sharedSecret.length, 0);
      kek.fillRange(0, kek.length, 0);
    }
  }

  Future<Uint8List> open({
    required PairingOffer offer,
    required PairingEnvelope envelope,
    required Uint8List recipientSeed,
  }) async {
    final kemCiphertext = _decode(
      envelope.kemCiphertext,
      XWing.ciphertextBytes,
      DevicePairingError.malformedEnvelope,
    );
    final ciphertext = _decode(
      envelope.ciphertext,
      48,
      DevicePairingError.malformedEnvelope,
    );
    final sodium = await _sodiumLoader();
    final sharedSecret = XWing(
      sodium,
    ).decapsulate(kemCiphertext, recipientSeed);
    final transcript = offer._transcriptHash(kemCiphertext);
    final kek = hkdfSha256(
      ikm: sharedSecret,
      salt: transcript,
      info: Uint8List.fromList(ascii.encode(_kekInfo)),
    );
    final key = SecureKey.fromList(sodium, kek);
    try {
      return sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: ciphertext,
        nonce: Uint8List(24),
        key: key,
        additionalData: _aad(transcript),
      );
    } on SodiumException {
      throw const DevicePairingException(DevicePairingError.aeadFailure);
    } finally {
      key.dispose();
      sharedSecret.fillRange(0, sharedSecret.length, 0);
      kek.fillRange(0, kek.length, 0);
    }
  }

  static Uint8List _aad(Uint8List transcript) =>
      Uint8List.fromList([...ascii.encode('PLDNID3DA'), ...transcript]);
}

/// Opens the X-Wing account recovery challenge v2 (`identity-kdf/v3`).
class RecoveryChallengeV2Crypto {
  RecoveryChallengeV2Crypto({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;
  static const packageBytes = 1168;

  /// Returns the 32-byte challenge secret; [userId] is the authenticated
  /// session user, never a value from the challenge response.
  Future<Uint8List> open({
    required String encodedPackage,
    required String userId,
    required Uint8List memberSeed,
  }) async {
    final package = _decode(
      encodedPackage,
      packageBytes,
      DevicePairingError.malformedEnvelope,
    );
    final sodium = await _sodiumLoader();
    final xwing = XWing(sodium);
    final publicKey = xwing.publicKeyFromSeed(memberSeed);
    final kemCiphertext = Uint8List.sublistView(
      package,
      0,
      XWing.ciphertextBytes,
    );
    final sharedSecret = xwing.decapsulate(kemCiphertext, memberSeed);
    final user = _uuidBytes(userId);
    final aeadKey = hkdfSha256(
      ikm: sharedSecret,
      salt: Uint8List(0),
      info: Uint8List.fromList([
        ...ascii.encode('PLDNRCV2'),
        ...user,
        ...sha256.convert(publicKey).bytes,
        ...sha256.convert(kemCiphertext).bytes,
      ]),
    );
    final key = SecureKey.fromList(sodium, aeadKey);
    try {
      return sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: Uint8List.sublistView(package, XWing.ciphertextBytes),
        nonce: Uint8List(24),
        key: key,
        additionalData: Uint8List.fromList([
          ...ascii.encode('PLDNRCV2'),
          ...user,
        ]),
      );
    } on SodiumException {
      throw const DevicePairingException(DevicePairingError.aeadFailure);
    } finally {
      key.dispose();
      sharedSecret.fillRange(0, sharedSecret.length, 0);
      aeadKey.fillRange(0, aeadKey.length, 0);
      package.fillRange(0, package.length, 0);
    }
  }
}

Uint8List _decode(String value, int length, DevicePairingError error) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw DevicePairingException(error);
  }
  try {
    final bytes = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(value)),
    );
    if (bytes.length == length && _b64(bytes) == value) return bytes;
  } on FormatException {
    // Reported below with the caller's typed error.
  }
  throw DevicePairingException(error);
}

bool _equal(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}

Uint8List _uuidBytes(String value) {
  final hex = value.replaceAll('-', '');
  if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hex)) {
    throw const DevicePairingException(DevicePairingError.malformedEnvelope);
  }
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

Uint8List _u16(int value) =>
    (ByteData(2)..setUint16(0, value)).buffer.asUint8List();

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
