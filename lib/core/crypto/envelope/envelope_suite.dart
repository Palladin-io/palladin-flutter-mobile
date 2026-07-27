import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../sodium_provider.dart';
import 'envelope_contract.dart';

/// Opaque, bounded suite-owned payload.
final class EncodedSuitePayload {
  EncodedSuitePayload._(this._bytes);

  static const int maxBytes = 1024 * 1024;
  final Uint8List _bytes;
  Uint8List get bytes => Uint8List.fromList(_bytes);

  factory EncodedSuitePayload.fromBytes(List<int> value) {
    if (value.length < XChaChaVaultEnvelopeSuite.minimumPayloadBytes ||
        value.length > maxBytes) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidPayload);
    }
    return EncodedSuitePayload._(Uint8List.fromList(value));
  }

  factory EncodedSuitePayload.fromBase64Url(String value) {
    if (value.isEmpty ||
        value.contains('=') ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidPayload);
    }
    try {
      final decoded = base64Url.decode(base64Url.normalize(value));
      if (base64UrlEncode(decoded).replaceAll('=', '') != value) {
        throw const EnvelopeException(EnvelopeErrorKind.invalidPayload);
      }
      return EncodedSuitePayload.fromBytes(decoded);
    } on FormatException {
      throw const EnvelopeException(EnvelopeErrorKind.invalidPayload);
    }
  }

  String toBase64Url() => base64UrlEncode(_bytes).replaceAll('=', '');
}

/// Client implementation selected only through a compiled allowlist.
abstract interface class ClientEnvelopeSuite {
  CryptoSuiteId get id;

  Future<EncodedSuitePayload> seal({
    required EnvelopeDescriptor descriptor,
    required Uint8List rootKey,
    required Uint8List plaintext,
    Uint8List? nonce,
  });

  Future<Uint8List> open({
    required EnvelopeDescriptor descriptor,
    required Uint8List rootKey,
    required EncodedSuitePayload payload,
  });
}

/// XChaCha20-Poly1305-IETF with HKDF-SHA-256 purpose separation.
final class XChaChaVaultEnvelopeSuite implements ClientEnvelopeSuite {
  XChaChaVaultEnvelopeSuite({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  static const int keyBytes = 32;
  static const int nonceBytes = 24;
  static const int tagBytes = 16;
  static const int minimumPayloadBytes = nonceBytes + tagBytes;

  final Future<SodiumSumo> Function() _sodiumLoader;

  @override
  CryptoSuiteId get id => CryptoSuiteId.palladinVaultXChaChaV1;

  @override
  Future<EncodedSuitePayload> seal({
    required EnvelopeDescriptor descriptor,
    required Uint8List rootKey,
    required Uint8List plaintext,
    Uint8List? nonce,
  }) async {
    _validateDescriptor(descriptor);
    _validateRootKey(rootKey);
    if (plaintext.length + minimumPayloadBytes > EncodedSuitePayload.maxBytes) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidPayload);
    }
    final sodium = await _sodiumLoader();
    final actualNonce = nonce == null
        ? sodium.randombytes.buf(nonceBytes)
        : Uint8List.fromList(nonce);
    if (actualNonce.length != nonceBytes) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidPayload);
    }
    final derived = deriveSubkey(rootKey: rootKey, descriptor: descriptor);
    final key = SecureKey.fromList(sodium, derived);
    try {
      final ciphertext = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
        message: plaintext,
        nonce: actualNonce,
        key: key,
        additionalData: descriptor.encodeAad(),
      );
      return EncodedSuitePayload.fromBytes([...actualNonce, ...ciphertext]);
    } finally {
      derived.fillRange(0, derived.length, 0);
      key.dispose();
    }
  }

  @override
  Future<Uint8List> open({
    required EnvelopeDescriptor descriptor,
    required Uint8List rootKey,
    required EncodedSuitePayload payload,
  }) async {
    _validateDescriptor(descriptor);
    _validateRootKey(rootKey);
    final sodium = await _sodiumLoader();
    final derived = deriveSubkey(rootKey: rootKey, descriptor: descriptor);
    final key = SecureKey.fromList(sodium, derived);
    try {
      return sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: Uint8List.sublistView(payload.bytes, nonceBytes),
        nonce: Uint8List.sublistView(payload.bytes, 0, nonceBytes),
        key: key,
        additionalData: descriptor.encodeAad(),
      );
    } on SodiumException {
      throw const EnvelopeException(EnvelopeErrorKind.authenticationFailed);
    } finally {
      derived.fillRange(0, derived.length, 0);
      key.dispose();
    }
  }

  void _validateDescriptor(EnvelopeDescriptor descriptor) {
    if (descriptor.cryptoSuiteId != id) {
      throw const EnvelopeException(EnvelopeErrorKind.unsupportedSuite);
    }
  }

  void _validateRootKey(Uint8List rootKey) {
    if (rootKey.length != keyBytes) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
  }

  /// Derives the 32-byte purpose/scope subkey from the typed descriptor.
  /// The caller owns and must zero the returned bytes after use.
  Uint8List deriveSubkey({
    required Uint8List rootKey,
    required EnvelopeDescriptor descriptor,
  }) {
    _validateDescriptor(descriptor);
    _validateRootKey(rootKey);
    return _hkdfSha256(rootKey, descriptor.encodeKdfInfo());
  }

  Uint8List _hkdfSha256(Uint8List ikm, Uint8List info) {
    final zeroSalt = Uint8List(32);
    final prk = Hmac(sha256, zeroSalt).convert(ikm).bytes;
    final block = Hmac(sha256, prk).convert([...info, 1]).bytes;
    return Uint8List.fromList(block.sublist(0, keyBytes));
  }
}

/// Immutable suite allowlist; unknown identifiers never fall back.
final class CryptoSuiteRegistry {
  CryptoSuiteRegistry({List<ClientEnvelopeSuite>? suites})
    : _suites = {
        for (final suite in suites ?? [XChaChaVaultEnvelopeSuite()])
          suite.id: suite,
      };

  final Map<CryptoSuiteId, ClientEnvelopeSuite> _suites;

  ClientEnvelopeSuite resolve(CryptoSuiteId id) {
    final suite = _suites[id];
    if (suite == null) {
      throw const EnvelopeException(EnvelopeErrorKind.unsupportedSuite);
    }
    return suite;
  }

  /// Resolves an untrusted wire identifier without negotiation or fallback.
  ClientEnvelopeSuite resolveWire(String wireValue) {
    for (final entry in _suites.entries) {
      if (entry.key.wireValue == wireValue) return entry.value;
    }
    throw const EnvelopeException(EnvelopeErrorKind.unsupportedSuite);
  }
}
