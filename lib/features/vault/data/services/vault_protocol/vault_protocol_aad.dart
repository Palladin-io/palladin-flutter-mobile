import 'dart:typed_data';

import 'vault_protocol_bytes.dart';

const vaultProtocolVersion = 2;
const vaultAlgorithmSuite = 1;

enum VaultAadProfile {
  memberVaultMetadata,
  memberIndex,
  memberSecret,
  agentDiscovery,
  entryKeyWrapper,
  vaultPrivateKey,
  vaultDiscoveryKey,
  encryptedReason,
  grantPayload,
}

enum _ValueType { u16, u32, u64, uuid, bytes, instant }

final class _Binding {
  const _Binding(
    this.tag,
    this.type,
    this.source, {
    this.constant,
    this.optional = false,
  });

  final int tag;
  final _ValueType type;
  final String source;
  final int? constant;
  final bool optional;
}

const _common = <_Binding>[
  _Binding(1, _ValueType.u16, 'header.protocolVersion'),
  _Binding(2, _ValueType.u16, 'header.algorithmSuite'),
  _Binding(4, _ValueType.uuid, 'organizationId'),
  _Binding(5, _ValueType.uuid, 'vaultId'),
];

final Map<VaultAadProfile, List<_Binding>> _profiles = {
  VaultAadProfile.memberVaultMetadata: [
    ..._common,
    const _Binding(3, _ValueType.u16, 'header.resourceKind', constant: 1),
    const _Binding(7, _ValueType.u16, 'header.projectionKind', constant: 1),
    const _Binding(8, _ValueType.u64, 'metadataRevision'),
    const _Binding(9, _ValueType.u32, 'header.keyVersion'),
    const _Binding(10, _ValueType.u32, 'header.memberKeyGeneration'),
  ],
  VaultAadProfile.memberIndex: [
    ..._common,
    const _Binding(3, _ValueType.u16, 'header.resourceKind', constant: 2),
    const _Binding(6, _ValueType.uuid, 'entryId'),
    const _Binding(7, _ValueType.u16, 'header.projectionKind', constant: 2),
    const _Binding(8, _ValueType.u64, 'memberIndexRevision'),
    const _Binding(9, _ValueType.u32, 'header.keyVersion'),
    const _Binding(10, _ValueType.u32, 'header.memberKeyGeneration'),
  ],
  VaultAadProfile.memberSecret: [
    ..._common,
    const _Binding(3, _ValueType.u16, 'header.resourceKind', constant: 2),
    const _Binding(6, _ValueType.uuid, 'entryId'),
    const _Binding(7, _ValueType.u16, 'header.projectionKind', constant: 3),
    const _Binding(8, _ValueType.u64, 'revision'),
    const _Binding(9, _ValueType.u32, 'header.keyVersion'),
    const _Binding(10, _ValueType.u32, 'header.memberKeyGeneration'),
    const _Binding(20, _ValueType.u16, 'operation'),
  ],
  VaultAadProfile.agentDiscovery: [
    ..._common,
    const _Binding(3, _ValueType.u16, 'header.resourceKind', constant: 2),
    const _Binding(6, _ValueType.uuid, 'entryId'),
    const _Binding(7, _ValueType.u16, 'header.projectionKind', constant: 4),
    const _Binding(8, _ValueType.u64, 'agentDiscoveryRevision'),
    const _Binding(9, _ValueType.u32, 'vdkVersion'),
    const _Binding(10, _ValueType.u32, 'header.memberKeyGeneration'),
  ],
  VaultAadProfile.entryKeyWrapper: [
    ..._common,
    const _Binding(3, _ValueType.u16, 'header.resourceKind', constant: 2),
    const _Binding(6, _ValueType.uuid, 'entryId'),
    const _Binding(7, _ValueType.u16, 'header.projectionKind', constant: 8),
    const _Binding(8, _ValueType.u64, 'wrapperRevision'),
    const _Binding(9, _ValueType.u32, 'keyVersion'),
    const _Binding(10, _ValueType.u32, 'memberKeyGeneration'),
    const _Binding(21, _ValueType.u32, 'wrappingKeyVersion'),
  ],
  VaultAadProfile.vaultPrivateKey: [
    ..._common,
    const _Binding(3, _ValueType.u16, 'header.resourceKind', constant: 1),
    const _Binding(7, _ValueType.u16, 'header.projectionKind', constant: 7),
    const _Binding(8, _ValueType.u64, 'privateKeyRevision'),
    const _Binding(9, _ValueType.u32, 'privateKeyVersion'),
    const _Binding(10, _ValueType.u32, 'memberKeyGeneration'),
    const _Binding(21, _ValueType.u32, 'wrappingKeyVersion'),
    const _Binding(22, _ValueType.u16, 'privateKeyKind'),
  ],
  VaultAadProfile.vaultDiscoveryKey: [
    ..._common,
    const _Binding(3, _ValueType.u16, 'header.resourceKind', constant: 1),
    const _Binding(7, _ValueType.u16, 'header.projectionKind', constant: 12),
    const _Binding(8, _ValueType.u64, 'discoveryKeyRevision'),
    const _Binding(9, _ValueType.u32, 'vdkVersion'),
    const _Binding(10, _ValueType.u32, 'memberKeyGeneration'),
    const _Binding(21, _ValueType.u32, 'wrappingKeyVersion'),
  ],
  VaultAadProfile.encryptedReason: [
    ..._common,
    const _Binding(3, _ValueType.u16, 'header.resourceKind', constant: 3),
    const _Binding(6, _ValueType.uuid, 'entryId'),
    const _Binding(7, _ValueType.u16, 'header.projectionKind', constant: 5),
    const _Binding(8, _ValueType.u64, 'requestRevision'),
    const _Binding(9, _ValueType.u32, 'reasonKeyVersion'),
    const _Binding(10, _ValueType.u32, 'header.memberKeyGeneration'),
    const _Binding(12, _ValueType.uuid, 'grantRequestId'),
    const _Binding(13, _ValueType.uuid, 'agentId'),
    const _Binding(14, _ValueType.u16, 'requestedMethods'),
    const _Binding(17, _ValueType.u32, 'agentMessageKeyVersion'),
    const _Binding(18, _ValueType.bytes, 'recipientAgentMessageKeyFingerprint'),
  ],
  VaultAadProfile.grantPayload: [
    ..._common,
    const _Binding(3, _ValueType.u16, 'header.resourceKind', constant: 4),
    const _Binding(6, _ValueType.uuid, 'entryId'),
    const _Binding(7, _ValueType.u16, 'header.projectionKind', constant: 6),
    const _Binding(8, _ValueType.u64, 'grantEnvelopeRevision'),
    const _Binding(9, _ValueType.u32, 'grantKeyVersion'),
    const _Binding(10, _ValueType.u32, 'header.memberKeyGeneration'),
    const _Binding(11, _ValueType.uuid, 'grantId'),
    const _Binding(13, _ValueType.uuid, 'agentId'),
    const _Binding(14, _ValueType.u16, 'approvedMethods'),
    const _Binding(15, _ValueType.instant, 'expiresAt', optional: true),
    const _Binding(16, _ValueType.u32, 'useLimit', optional: true),
    const _Binding(17, _ValueType.u32, 'recipientAgentKeyVersion'),
    const _Binding(18, _ValueType.bytes, 'recipientAgentKeyFingerprint'),
    const _Binding(19, _ValueType.u64, 'entryRevision'),
  ],
};

Map<String, Object?> _header(Map<String, Object?> context) {
  final value = context['header'];
  if (value is! Map) throw const FormatException('missing envelope header');
  return value.cast<String, Object?>();
}

Object? _read(Map<String, Object?> context, String source) {
  if (!source.startsWith('header.')) return context[source];
  return _header(context)[source.substring('header.'.length)];
}

int _integer(Object value, String source) {
  if (value is! int) throw FormatException('$source must be an integer');
  return value;
}

Uint8List _encode(_ValueType type, Object value, String source) {
  switch (type) {
    case _ValueType.u16:
      return VaultProtocolBytes.u16(_integer(value, source));
    case _ValueType.u32:
      return VaultProtocolBytes.u32(_integer(value, source));
    case _ValueType.u64:
      return VaultProtocolBytes.u64(value);
    case _ValueType.uuid:
      if (value is! String) throw FormatException('$source must be a UUID');
      return VaultProtocolBytes.uuid(value);
    case _ValueType.bytes:
      if (value is! String) throw FormatException('$source must be base64url');
      return VaultProtocolBytes.base64UrlDecode(value, maximumBytes: 64);
    case _ValueType.instant:
      if (value is! String ||
          !RegExp(
            r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{0,5}[1-9])?Z$',
          ).hasMatch(value)) {
        throw FormatException('$source must be a canonical instant');
      }
      final bytes = VaultProtocolBytes.utf8Encode(value);
      if (bytes.length > 27) throw FormatException('$source exceeds limit');
      return bytes;
  }
}

/// Encodes the exact frozen binary TLV AAD for [profile].
Uint8List encodeVaultAad(
  VaultAadProfile profile,
  Map<String, Object?> context,
) {
  final header = _header(context);
  if (header['protocolVersion'] != vaultProtocolVersion) {
    throw const FormatException('unsupported Vault protocol version');
  }
  if (header['algorithmSuite'] != vaultAlgorithmSuite) {
    throw const FormatException('unsupported Vault algorithm suite');
  }
  final fields = <Uint8List>[];
  for (final binding in _profiles[profile]!) {
    final value = _read(context, binding.source);
    if (value == null) {
      if (binding.optional) continue;
      throw FormatException('${profile.name} missing ${binding.source}');
    }
    if (binding.constant != null && value != binding.constant) {
      throw FormatException('${profile.name} header/profile mismatch');
    }
    final encoded = _encode(binding.type, value, binding.source);
    final typeCode = binding.type.index + 1;
    fields.add(
      VaultProtocolBytes.concat([
        Uint8List.fromList([binding.tag, typeCode]),
        VaultProtocolBytes.u16(encoded.length),
        encoded,
      ]),
    );
  }
  fields.sort((left, right) => left[0].compareTo(right[0]));
  return VaultProtocolBytes.concat([
    VaultProtocolBytes.utf8Encode('PLDNV2AD'),
    Uint8List.fromList([1, fields.length]),
    VaultProtocolBytes.u16(0),
    ...fields,
  ]);
}

void assertVaultEnvelopeBindings(
  VaultAadProfile profile,
  Map<String, Object?> context,
) {
  encodeVaultAad(profile, context);
  final header = _header(context);
  const revisionSource = {
    VaultAadProfile.memberVaultMetadata: 'metadataRevision',
    VaultAadProfile.memberIndex: 'memberIndexRevision',
    VaultAadProfile.memberSecret: 'revision',
    VaultAadProfile.agentDiscovery: 'agentDiscoveryRevision',
    VaultAadProfile.entryKeyWrapper: 'wrapperRevision',
    VaultAadProfile.vaultPrivateKey: 'privateKeyRevision',
    VaultAadProfile.vaultDiscoveryKey: 'discoveryKeyRevision',
    VaultAadProfile.encryptedReason: 'requestRevision',
    VaultAadProfile.grantPayload: 'grantEnvelopeRevision',
  };
  if (context[revisionSource[profile]] != header['resourceRevision']) {
    throw const FormatException('resource revision/header mismatch');
  }
  const keySource = {
    VaultAadProfile.agentDiscovery: 'vdkVersion',
    VaultAadProfile.entryKeyWrapper: 'keyVersion',
    VaultAadProfile.vaultPrivateKey: 'privateKeyVersion',
    VaultAadProfile.vaultDiscoveryKey: 'vdkVersion',
    VaultAadProfile.encryptedReason: 'reasonKeyVersion',
    VaultAadProfile.grantPayload: 'grantKeyVersion',
  };
  final source = keySource[profile];
  if (source != null && context[source] != header['keyVersion']) {
    throw const FormatException('key version/header mismatch');
  }
  if ({
        VaultAadProfile.entryKeyWrapper,
        VaultAadProfile.vaultPrivateKey,
        VaultAadProfile.vaultDiscoveryKey,
      }.contains(profile) &&
      context['memberKeyGeneration'] != header['memberKeyGeneration']) {
    throw const FormatException('member generation/header mismatch');
  }
}
