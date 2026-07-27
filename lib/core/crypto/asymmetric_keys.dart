import 'dart:typed_data';

import 'envelope/envelope_contract.dart';

/// Ed25519 signing public key; never interchangeable with recipient keys.
final class Ed25519PublicKey {
  Ed25519PublicKey(List<int> bytes) : _bytes = _copy32(bytes);
  final Uint8List _bytes;
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

/// X25519 recipient public key; never interchangeable with signing keys.
final class X25519PublicKey {
  X25519PublicKey(List<int> bytes) : _bytes = _copy32(bytes);
  final Uint8List _bytes;
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

Uint8List _copy32(List<int> value) {
  if (value.length != 32) {
    throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
  }
  return Uint8List.fromList(value);
}
