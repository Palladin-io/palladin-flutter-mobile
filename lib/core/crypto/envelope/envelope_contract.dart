import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Protocol-level failures are deliberately non-sensitive and fail closed.
class EnvelopeException implements Exception {
  const EnvelopeException(this.kind);

  final EnvelopeErrorKind kind;
}

/// Stable error categories for canonical envelope processing.
enum EnvelopeErrorKind {
  invalidDescriptor,
  unsupportedProtocol,
  unsupportedSuite,
  invalidPayload,
  authenticationFailed,
}

/// Registered envelope purposes. Numeric IDs are part of protocol v2.
enum EnvelopePurpose {
  memberVaultMetadata(1),
  vaultDiscoveryKeyByVk(2),
  agentMessagePrivateByVk(3),
  manifestPrivateByVk(4),
  memberIndex(5),
  memberSecret(6),
  agentDiscovery(7),
  entryDekByVk(8),
  reason(9),
  grant(10);

  const EnvelopePurpose(this.id);
  final int id;

  static EnvelopePurpose parseWire(Object? value) {
    const names = <String, EnvelopePurpose>{
      'memberVaultMetadata': EnvelopePurpose.memberVaultMetadata,
      'vaultDiscoveryKey': EnvelopePurpose.vaultDiscoveryKeyByVk,
      'vaultAgentMessagePrivateKey': EnvelopePurpose.agentMessagePrivateByVk,
      'vaultManifestSigningPrivateKey': EnvelopePurpose.manifestPrivateByVk,
      'memberIndex': EnvelopePurpose.memberIndex,
      'memberSecret': EnvelopePurpose.memberSecret,
      'agentDiscovery': EnvelopePurpose.agentDiscovery,
      'entryDekByVaultKey': EnvelopePurpose.entryDekByVk,
      'encryptedReason': EnvelopePurpose.reason,
      'grantPayload': EnvelopePurpose.grant,
    };
    if (value is String) {
      final purpose = names[value];
      if (purpose != null) return purpose;
    }
    if (value is int) {
      for (final purpose in EnvelopePurpose.values) {
        if (purpose.id == value) return purpose;
      }
    }
    throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
  }
}

/// The one allowlisted Vault suite at the protocol-v2 cutover.
enum CryptoSuiteId {
  palladinVaultXChaChaV1('palladin-vault-xchacha-v1');

  const CryptoSuiteId(this.wireValue);
  final String wireValue;
}

/// RFC 4122 UUID bytes in network order.
final class EnvelopeId {
  EnvelopeId._(this._bytes);

  final Uint8List _bytes;
  Uint8List get bytes => Uint8List.fromList(_bytes);

  factory EnvelopeId.parse(String value) {
    final compact = value.replaceAll('-', '');
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(compact)) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    final bytes = Uint8List.fromList([
      for (var i = 0; i < compact.length; i += 2)
        int.parse(compact.substring(i, i + 2), radix: 16),
    ]);
    if (bytes.every((byte) => byte == 0)) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    return EnvelopeId._(bytes);
  }
}

/// Stable tenant/resource coordinates authenticated by every envelope.
final class EnvelopeScope {
  const EnvelopeScope({
    required this.organizationId,
    required this.vaultId,
    this.entryId,
    this.grantOrRequestId,
    this.agentId,
    this.memberId,
  });

  final EnvelopeId organizationId;
  final EnvelopeId vaultId;
  final EnvelopeId? entryId;
  final EnvelopeId? grantOrRequestId;
  final EnvelopeId? agentId;
  final EnvelopeId? memberId;
}

/// Extra authenticated fields whose shape is fixed by [EnvelopePurpose].
sealed class EnvelopePurposeData {
  const EnvelopePurposeData();
}

final class NoPurposeData extends EnvelopePurposeData {
  const NoPurposeData();
}

final class MemberSecretPurposeData extends EnvelopePurposeData {
  const MemberSecretPurposeData({required this.operation});
  final int operation;
}

final class WrappingPurposeData extends EnvelopePurposeData {
  const WrappingPurposeData({required this.wrappingVaultKeyVersion});
  final int wrappingVaultKeyVersion;
}

final class ReasonPurposeData extends EnvelopePurposeData {
  ReasonPurposeData({
    required this.agentMessageKeyVersion,
    required Uint8List recipientFingerprint,
    required this.methods,
  }) : _recipientFingerprint = Uint8List.fromList(recipientFingerprint);

  final int agentMessageKeyVersion;
  final Uint8List _recipientFingerprint;
  Uint8List get recipientFingerprint =>
      Uint8List.fromList(_recipientFingerprint);
  final int methods;
}

final class GrantPurposeData extends EnvelopePurposeData {
  GrantPurposeData({
    required this.entryRevision,
    required this.recipientKeyVersion,
    required Uint8List recipientFingerprint,
    required this.methods,
    required this.deliveryPolicy,
    required Uint8List fieldSetCommitment,
    this.expiresAtSeconds,
    this.expiresAtNanoseconds,
    this.remainingUses,
  }) : _recipientFingerprint = Uint8List.fromList(recipientFingerprint),
       _fieldSetCommitment = Uint8List.fromList(fieldSetCommitment);

  final int entryRevision;
  final int recipientKeyVersion;
  final Uint8List _recipientFingerprint;
  Uint8List get recipientFingerprint =>
      Uint8List.fromList(_recipientFingerprint);
  final int methods;
  final int deliveryPolicy;
  final Uint8List _fieldSetCommitment;
  Uint8List get fieldSetCommitment => Uint8List.fromList(_fieldSetCommitment);
  final int? expiresAtSeconds;
  final int? expiresAtNanoseconds;
  final int? remainingUses;
}

/// Algorithm-independent authenticated envelope descriptor.
final class EnvelopeDescriptor {
  EnvelopeDescriptor({
    this.protocolVersion = 2,
    this.cryptoSuiteId = CryptoSuiteId.palladinVaultXChaChaV1,
    required this.purpose,
    required this.scope,
    required this.resourceRevision,
    required this.keyVersion,
    this.memberKeyGeneration,
    this.purposeData = const NoPurposeData(),
  }) {
    _validate();
  }

  final int protocolVersion;
  final CryptoSuiteId cryptoSuiteId;
  final EnvelopePurpose purpose;
  final EnvelopeScope scope;
  final int resourceRevision;
  final int keyVersion;
  final int? memberKeyGeneration;
  final EnvelopePurposeData purposeData;

  static const int _maxUint16 = 0xffff;
  static const int _maxUint32 = 0xffffffff;

  void _validate() {
    if (protocolVersion != 2) {
      throw const EnvelopeException(EnvelopeErrorKind.unsupportedProtocol);
    }
    if (resourceRevision <= 0 || keyVersion <= 0 || keyVersion > _maxUint32) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    final generation = memberKeyGeneration;
    if (generation != null && (generation <= 0 || generation > _maxUint32)) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    _validateScopeAndPurposeData();
  }

  void _validateScopeAndPurposeData() {
    final hasEntry = scope.entryId != null;
    final hasGrant = scope.grantOrRequestId != null;
    final hasAgent = scope.agentId != null;
    final hasMember = scope.memberId != null;
    final valid = switch (purpose) {
      EnvelopePurpose.memberVaultMetadata =>
        !hasEntry &&
            !hasGrant &&
            !hasAgent &&
            !hasMember &&
            purposeData is NoPurposeData,
      EnvelopePurpose.vaultDiscoveryKeyByVk =>
        !hasEntry && !hasGrant && !hasAgent && !hasMember,
      EnvelopePurpose.memberIndex || EnvelopePurpose.memberSecret =>
        hasEntry && !hasGrant && !hasAgent && !hasMember,
      EnvelopePurpose.agentDiscovery =>
        hasEntry &&
            !hasGrant &&
            !hasAgent &&
            !hasMember &&
            purposeData is NoPurposeData,
      EnvelopePurpose.entryDekByVk =>
        hasEntry && !hasGrant && !hasAgent && !hasMember,
      EnvelopePurpose.agentMessagePrivateByVk ||
      EnvelopePurpose.manifestPrivateByVk =>
        !hasEntry && !hasGrant && !hasAgent && !hasMember,
      EnvelopePurpose.reason ||
      EnvelopePurpose.grant => hasEntry && hasGrant && hasAgent && !hasMember,
    };
    if (!valid) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    switch (purpose) {
      case EnvelopePurpose.memberSecret:
        final data = purposeData;
        if (data is! MemberSecretPurposeData ||
            data.operation <= 0 ||
            data.operation > _maxUint16) {
          throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
        }
      case EnvelopePurpose.entryDekByVk ||
          EnvelopePurpose.vaultDiscoveryKeyByVk ||
          EnvelopePurpose.agentMessagePrivateByVk ||
          EnvelopePurpose.manifestPrivateByVk:
        final data = purposeData;
        if (data is! WrappingPurposeData ||
            data.wrappingVaultKeyVersion <= 0 ||
            data.wrappingVaultKeyVersion > _maxUint32) {
          throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
        }
      case EnvelopePurpose.reason:
        final data = purposeData;
        if (data is! ReasonPurposeData ||
            data.agentMessageKeyVersion <= 0 ||
            data.agentMessageKeyVersion > _maxUint32 ||
            data.recipientFingerprint.length != 32 ||
            data.recipientFingerprint.every((byte) => byte == 0) ||
            data.methods <= 0 ||
            data.methods > _maxUint16) {
          throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
        }
      case EnvelopePurpose.grant:
        final data = purposeData;
        if (data is! GrantPurposeData ||
            data.entryRevision <= 0 ||
            data.recipientKeyVersion <= 0 ||
            data.recipientKeyVersion > _maxUint32 ||
            data.recipientFingerprint.length != 32 ||
            data.recipientFingerprint.every((byte) => byte == 0) ||
            data.methods <= 0 ||
            data.methods > _maxUint16 ||
            (data.deliveryPolicy != 0 && data.deliveryPolicy != 1) ||
            data.fieldSetCommitment.length != 32 ||
            (data.expiresAtSeconds == null) !=
                (data.expiresAtNanoseconds == null) ||
            (data.expiresAtNanoseconds != null &&
                (data.expiresAtNanoseconds! < 0 ||
                    data.expiresAtNanoseconds! >= 1000000000)) ||
            (data.remainingUses != null &&
                (data.remainingUses! <= 0 ||
                    data.remainingUses! > _maxUint32))) {
          throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
        }
      case EnvelopePurpose.memberVaultMetadata ||
          EnvelopePurpose.vaultDiscoveryKeyByVk ||
          EnvelopePurpose.memberIndex ||
          EnvelopePurpose.agentDiscovery:
        if (purposeData is! NoPurposeData) {
          throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
        }
    }
  }

  /// Canonical protocol-v2 AAD bytes.
  Uint8List encodeAad() {
    final writer = _CanonicalWriter()..ascii('PLDNENV2');
    _writeBase(writer, includeRevision: true);
    _writePurposeData(writer);
    return writer.takeBytes();
  }

  /// HKDF info: same identity and key lifecycle, excluding resource revision.
  Uint8List encodeKdfInfo() {
    final writer = _CanonicalWriter()..ascii('PLDNKDF2');
    _writeBase(writer, includeRevision: false);
    return writer.takeBytes();
  }

  void _writeBase(_CanonicalWriter writer, {required bool includeRevision}) {
    final suite = ascii.encode(cryptoSuiteId.wireValue);
    writer
      ..u16(protocolVersion)
      ..u16(suite.length)
      ..bytes(suite)
      ..u16(purpose.id);
    writer.bytes(encodeEnvelopeScope(scope));
    if (includeRevision) writer.u64(resourceRevision);
    writer.u32(keyVersion);
    final generation = memberKeyGeneration;
    writer.u8(generation == null ? 0 : 1);
    if (generation != null) writer.u32(generation);
  }

  void _writePurposeData(_CanonicalWriter writer) {
    switch (purposeData) {
      case NoPurposeData():
        return;
      case MemberSecretPurposeData(:final operation):
        writer.u16(operation);
      case WrappingPurposeData(:final wrappingVaultKeyVersion):
        writer.u32(wrappingVaultKeyVersion);
      case ReasonPurposeData(
        :final agentMessageKeyVersion,
        :final recipientFingerprint,
        :final methods,
      ):
        writer
          ..asciiWithU16Length('palladin-x25519-sealed-box-v1')
          ..u32(agentMessageKeyVersion)
          ..bytes(recipientFingerprint)
          ..u16(methods);
      case GrantPurposeData(
        :final entryRevision,
        :final recipientKeyVersion,
        :final recipientFingerprint,
        :final methods,
        :final deliveryPolicy,
        :final fieldSetCommitment,
        :final expiresAtSeconds,
        :final expiresAtNanoseconds,
        :final remainingUses,
      ):
        writer
          ..u64(entryRevision)
          ..asciiWithU16Length('palladin-x25519-sealed-box-v1')
          ..u32(recipientKeyVersion)
          ..bytes(recipientFingerprint)
          ..u16(methods)
          ..u16(deliveryPolicy)
          ..bytes(fieldSetCommitment)
          ..u8(expiresAtSeconds == null ? 0 : 1);
        if (expiresAtSeconds != null) {
          writer
            ..i64(expiresAtSeconds)
            ..u32(expiresAtNanoseconds!);
        }
        writer.u8(remainingUses == null ? 0 : 1);
        if (remainingUses != null) writer.u32(remainingUses);
    }
  }
}

/// Canonical typed-scope encoding shared by envelopes and key wrappers.
Uint8List encodeEnvelopeScope(EnvelopeScope scope) {
  var bitmap = 3;
  if (scope.entryId != null) bitmap |= 4;
  if (scope.grantOrRequestId != null) bitmap |= 8;
  if (scope.agentId != null) bitmap |= 16;
  if (scope.memberId != null) bitmap |= 32;
  final writer = _CanonicalWriter()
    ..u16(bitmap)
    ..bytes(scope.organizationId.bytes)
    ..bytes(scope.vaultId.bytes);
  for (final id in [
    scope.entryId,
    scope.grantOrRequestId,
    scope.agentId,
    scope.memberId,
  ]) {
    if (id != null) writer.bytes(id.bytes);
  }
  return writer.takeBytes();
}

/// Computes the canonical commitment for a grant's exact field set.
Uint8List computeFieldSetCommitment(Iterable<String> fieldIds) {
  final pattern = RegExp(r'^[A-Za-z0-9._:-]{1,128}$');
  final fields = fieldIds.toList()..sort((a, b) => a.compareTo(b));
  if (fields.toSet().length != fields.length ||
      fields.any((field) => !pattern.hasMatch(field))) {
    throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
  }
  final writer = _CanonicalWriter()
    ..ascii('PLDNV2FS')
    ..u32(fields.length);
  for (final field in fields) {
    final encoded = ascii.encode(field);
    writer
      ..u16(encoded.length)
      ..bytes(encoded);
  }
  return Uint8List.fromList(sha256.convert(writer.takeBytes()).bytes);
}

final class _CanonicalWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void ascii(String value) =>
      bytes(Uint8List.fromList(const AsciiEncoder().convert(value)));
  void asciiWithU16Length(String value) {
    final encoded = const AsciiEncoder().convert(value);
    u16(encoded.length);
    bytes(encoded);
  }

  void bytes(List<int> value) => _bytes.add(value);
  void u8(int value) => _bytes.addByte(value);
  void u16(int value) => _integer(value, 2);
  void u32(int value) => _integer(value, 4);
  void u64(int value) => _integer(value, 8);
  void i64(int value) => _integer(value, 8, signed: true);

  void _integer(int value, int width, {bool signed = false}) {
    final data = ByteData(width);
    switch (width) {
      case 2:
        data.setUint16(0, value, Endian.big);
      case 4:
        data.setUint32(0, value, Endian.big);
      case 8:
        signed
            ? data.setInt64(0, value, Endian.big)
            : data.setUint64(0, value, Endian.big);
    }
    _bytes.add(data.buffer.asUint8List());
  }

  Uint8List takeBytes() => _bytes.takeBytes();
}
