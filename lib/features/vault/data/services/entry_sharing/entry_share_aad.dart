import 'dart:convert';
import 'dart:typed_data';

import '../../../domain/entities/entry_share.dart';
import '../vault_protocol/vault_protocol_bytes.dart';

/// Sharing accepts canonical RFC UUID versions 1–8, including backend UUIDv7.
/// The separate frozen Vault-v2 byte profile remains unchanged.
Uint8List entryShareUuid(String value) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(value)) {
    throw const EntryShareException(EntryShareErrorKind.invalidSnapshot);
  }
  return VaultProtocolBytes.hex(value.replaceAll('-', ''));
}

Uint8List entryShareAad(EntryShareScope scope) {
  try {
    final expiry = RegExp(
      r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?Z$',
    ).firstMatch(scope.expiresAt);
    if (expiry == null) {
      throw const EntryShareException(EntryShareErrorKind.invalidSnapshot);
    }
    final instant = DateTime.parse('${expiry[1]}Z');
    // DateTime.parse normalizes invalid calendar components. Reject them and
    // encode fractions independently, without Dart's microsecond truncation.
    if (instant.millisecondsSinceEpoch < 0 ||
        instant.toIso8601String() != '${expiry[1]}.000Z') {
      throw const EntryShareException(EntryShareErrorKind.invalidSnapshot);
    }
    return VaultProtocolBytes.concat([
      Uint8List.fromList(ascii.encode('PLDN-ENTRY-SHARE-v1')),
      entryShareUuid(scope.shareId),
      entryShareUuid(scope.organizationId),
      entryShareUuid(scope.vaultId),
      entryShareUuid(scope.entryId),
      VaultProtocolBytes.u64(scope.sourceRevision),
      VaultProtocolBytes.u64(instant.millisecondsSinceEpoch ~/ 1000),
      VaultProtocolBytes.u32(int.parse((expiry[2] ?? '').padRight(9, '0'))),
    ]);
  } catch (_) {
    throw const EntryShareException(EntryShareErrorKind.invalidSnapshot);
  }
}
