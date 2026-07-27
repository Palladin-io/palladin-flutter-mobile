import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'vault_protocol_aad.dart';
import 'vault_protocol_bytes.dart';

enum VaultPublicKeyKind {
  agentX25519(1),
  agentEd25519(2),
  vaultSigningEd25519(3),
  vaultMessageX25519(4),
  memberX25519(5);

  const VaultPublicKeyKind(this.id);
  final int id;
}

/// Computes the domain-separated SHA-256 fingerprint of a raw public key.
Uint8List vaultPublicKeyFingerprint(
  VaultPublicKeyKind kind,
  Uint8List publicKey,
) {
  if (publicKey.length != 32) {
    throw const FormatException('Vault public key must be 32 raw bytes');
  }
  final input = VaultProtocolBytes.concat([
    VaultProtocolBytes.utf8Encode('PLDNV2FP'),
    VaultProtocolBytes.u16(vaultProtocolVersion),
    VaultProtocolBytes.u16(kind.id),
    publicKey,
  ]);
  try {
    return Uint8List.fromList(sha256.convert(input).bytes);
  } finally {
    input.fillRange(0, input.length, 0);
  }
}
