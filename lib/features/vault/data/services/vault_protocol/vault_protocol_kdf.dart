import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'vault_protocol_aad.dart';
import 'vault_protocol_bytes.dart';

enum VaultKdfPurpose {
  memberVaultMetadata(1),
  memberIndex(2),
  memberSecret(3),
  agentDiscovery(4),
  encryptedAsset(5);

  const VaultKdfPurpose(this.id);
  final int id;
}

/// Parameters authenticated into the Vault protocol 2 projection KDF.
final class VaultKdfContext {
  const VaultKdfContext({
    required this.purpose,
    required this.resourceKind,
    required this.organizationId,
    required this.vaultId,
    required this.keyVersion,
    required this.memberKeyGeneration,
    this.entryId,
  });

  final VaultKdfPurpose purpose;
  final int resourceKind;
  final String organizationId;
  final String vaultId;
  final String? entryId;
  final int keyVersion;
  final int memberKeyGeneration;
}

/// Derives a 32-byte projection key with the frozen HKDF-SHA-256 profile.
Uint8List deriveVaultProjectionKey(Uint8List baseKey, VaultKdfContext context) {
  if (baseKey.length != 32) {
    throw const FormatException('Vault protocol base key must be 32 bytes');
  }
  if (context.resourceKind != 1 && context.resourceKind != 2) {
    throw const FormatException('unsupported resource kind');
  }
  if ((context.resourceKind == 2) != (context.entryId != null)) {
    throw const FormatException('entryId presence must match resource kind');
  }
  final saltInput = VaultProtocolBytes.concat([
    VaultProtocolBytes.utf8Encode('PLDNV2HK'),
    VaultProtocolBytes.u16(vaultProtocolVersion),
    VaultProtocolBytes.u16(context.resourceKind),
    VaultProtocolBytes.uuid(context.organizationId),
    VaultProtocolBytes.uuid(context.vaultId),
    context.entryId == null
        ? Uint8List(16)
        : VaultProtocolBytes.uuid(context.entryId!),
    VaultProtocolBytes.u32(context.keyVersion),
    VaultProtocolBytes.u32(context.memberKeyGeneration),
  ]);
  final salt = Uint8List.fromList(sha256.convert(saltInput).bytes);
  final info = VaultProtocolBytes.concat([
    VaultProtocolBytes.utf8Encode('palladin:vault-v2:'),
    VaultProtocolBytes.u16(context.purpose.id),
  ]);
  Uint8List? pseudoRandomKey;
  Uint8List? previous;
  try {
    pseudoRandomKey = Uint8List.fromList(
      Hmac(sha256, salt).convert(baseKey).bytes,
    );
    final output = BytesBuilder(copy: false);
    var counter = 1;
    while (output.length < 32) {
      final input = VaultProtocolBytes.concat([
        ?previous,
        info,
        Uint8List.fromList([counter]),
      ]);
      previous?.fillRange(0, previous.length, 0);
      previous = Uint8List.fromList(
        Hmac(sha256, pseudoRandomKey).convert(input).bytes,
      );
      input.fillRange(0, input.length, 0);
      output.add(previous);
      counter += 1;
    }
    return Uint8List.fromList(output.takeBytes().sublist(0, 32));
  } finally {
    saltInput.fillRange(0, saltInput.length, 0);
    salt.fillRange(0, salt.length, 0);
    info.fillRange(0, info.length, 0);
    pseudoRandomKey?.fillRange(0, pseudoRandomKey.length, 0);
    previous?.fillRange(0, previous.length, 0);
  }
}
