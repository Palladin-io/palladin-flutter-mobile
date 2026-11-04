import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mobile_palladin/core/crypto/recipient_key_wrapper.dart';
import 'package:sodium/sodium_sumo.dart';

/// Writes a `palladin-x25519-sealed-box-v1` package the way clients did before
/// that suite became read-only, so tests can cover the open-only legacy path.
Uint8List sealLegacyForTest(
  SodiumSumo sodium, {
  required Uint8List key,
  required WrapperContext context,
  required Uint8List recipientPublicKey,
}) {
  if (context.suiteId != WrapperSuite.x25519SealedBoxV1) {
    throw ArgumentError('legacy fixtures use the sealed-box suite');
  }
  final contextHash = sha256.convert([
    ...ascii.encode('PLDNX2CTX'),
    ...context.encode(),
  ]).bytes;
  return sodium.crypto.box.seal(
    message: Uint8List.fromList([
      ...ascii.encode('PLDNX2K1'),
      ...key,
      ...contextHash,
    ]),
    publicKey: recipientPublicKey,
  );
}
