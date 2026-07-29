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

  /// Parses the closed backend JSON enum contract while retaining support for
  /// the numeric protocol representation used by native fixtures and AAD.
  static VaultPublicKeyKind parseWire(Object? value) {
    if (value is String) {
      return VaultPublicKeyKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () =>
            throw const FormatException('Unsupported Vault public key kind'),
      );
    }
    if (value is int) {
      return VaultPublicKeyKind.values.firstWhere(
        (kind) => kind.id == value,
        orElse: () =>
            throw const FormatException('Unsupported Vault public key kind'),
      );
    }
    throw const FormatException('Malformed Vault public key kind');
  }
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
