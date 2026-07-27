import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../../core/crypto/sodium_provider.dart';
import 'vault_protocol_aad.dart';
import 'vault_protocol_bytes.dart';

/// RFC 8785-compatible canonical JSON for the protocol's closed value subset.
String canonicalizeVaultJson(Object? value) {
  if (value == null || value is bool) return jsonEncode(value);
  if (value is String) {
    VaultProtocolBytes.utf8Encode(value);
    return jsonEncode(value);
  }
  if (value is int) {
    if (value < 0 || value > 9007199254740991) {
      throw const FormatException(
        'Vault canonical JSON permits non-negative safe integers only',
      );
    }
    return value.toString();
  }
  if (value is List) {
    return '[${value.map(canonicalizeVaultJson).join(',')}]';
  }
  if (value is Map) {
    final map = value.cast<String, Object?>();
    final keys = map.keys.toList()..sort();
    return '{${keys.map((key) {
      VaultProtocolBytes.utf8Encode(key);
      return '${jsonEncode(key)}:${canonicalizeVaultJson(map[key])}';
    }).join(',')}}';
  }
  throw const FormatException('unsupported Vault canonical JSON value');
}

Uint8List vaultSignatureInput(String domainPrefix, Object unsignedObject) {
  if (!{
    'PLDNV2SIG:VAULT-MANIFEST:',
    'PLDNV2SIG:ENCRYPTED-REASON:',
  }.contains(domainPrefix)) {
    throw const FormatException('unsupported Vault signature domain');
  }
  return VaultProtocolBytes.concat([
    VaultProtocolBytes.utf8Encode(domainPrefix),
    VaultProtocolBytes.u16(vaultProtocolVersion),
    VaultProtocolBytes.utf8Encode(canonicalizeVaultJson(unsignedObject)),
  ]);
}

/// Dedicated Ed25519 signing and verification service for protocol objects.
final class VaultProtocolSignatureService {
  VaultProtocolSignatureService({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  Future<bool> verify({
    required String domainPrefix,
    required Object unsignedObject,
    required String signature,
    required Uint8List publicKey,
  }) async {
    if (publicKey.length != 32) {
      throw const FormatException('Ed25519 public key must be 32 bytes');
    }
    final signatureBytes = VaultProtocolBytes.base64UrlDecode(signature);
    if (signatureBytes.length != 64) {
      throw const FormatException('Ed25519 signature must be 64 bytes');
    }
    final input = vaultSignatureInput(domainPrefix, unsignedObject);
    final sodium = await _sodiumLoader();
    try {
      return sodium.crypto.sign.verifyDetached(
        message: input,
        signature: signatureBytes,
        publicKey: publicKey,
      );
    } finally {
      input.fillRange(0, input.length, 0);
      signatureBytes.fillRange(0, signatureBytes.length, 0);
    }
  }

  Future<String> sign({
    required String domainPrefix,
    required Object unsignedObject,
    required Uint8List privateKey,
  }) async {
    final sodium = await _sodiumLoader();
    if (privateKey.length != sodium.crypto.sign.secretKeyBytes) {
      throw const FormatException('Ed25519 private key must be 64 bytes');
    }
    final input = vaultSignatureInput(domainPrefix, unsignedObject);
    final secretKey = SecureKey.fromList(sodium, privateKey);
    try {
      return VaultProtocolBytes.base64UrlEncode(
        sodium.crypto.sign.detached(message: input, secretKey: secretKey),
      );
    } finally {
      input.fillRange(0, input.length, 0);
      secretKey.dispose();
    }
  }
}
