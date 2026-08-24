import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import 'asymmetric_keys.dart';
import 'envelope/envelope_contract.dart';
import 'sodium_provider.dart';

/// Registered X25519 recipient-wrapper profile.
enum RecipientWrapperSuiteId {
  x25519SealedBoxV1('palladin-x25519-sealed-box-v1');

  const RecipientWrapperSuiteId(this.wireValue);
  final String wireValue;
}

/// Wrapper contexts are closed and have purpose-specific scope requirements.
enum WrapperPurpose {
  memberVaultKey(1),
  agentVdk(2),
  reasonDek(3),
  grantDek(4),
  agentVaultKey(5),
  scriptExecutionDek(6);

  const WrapperPurpose(this.id);
  final int id;

  static WrapperPurpose parseWire(Object? value) {
    const names = <String, WrapperPurpose>{
      'memberVaultKey': WrapperPurpose.memberVaultKey,
      'agentDiscoveryVdk': WrapperPurpose.agentVdk,
      'reasonDek': WrapperPurpose.reasonDek,
      'grantDek': WrapperPurpose.grantDek,
      'agentVaultKey': WrapperPurpose.agentVaultKey,
      'scriptExecutionDek': WrapperPurpose.scriptExecutionDek,
    };
    if (value is String) {
      final purpose = names[value];
      if (purpose != null) return purpose;
    }
    if (value is int) {
      for (final purpose in WrapperPurpose.values) {
        if (purpose.id == value) return purpose;
      }
    }
    throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
  }
}

/// Immutable authenticated context for one wrapped 32-byte key.
final class WrapperContext {
  WrapperContext({
    this.protocolVersion = 2,
    this.suiteId = RecipientWrapperSuiteId.x25519SealedBoxV1,
    required this.purpose,
    required this.scope,
    required this.resourceRevision,
    required this.wrappedKeyVersion,
    this.memberKeyGeneration,
    this.recipientKeyKind = 1,
    required this.recipientKeyVersion,
    required Uint8List recipientFingerprint,
    Uint8List? parentDescriptorHash,
  }) : _recipientFingerprint = Uint8List.fromList(recipientFingerprint),
       _parentDescriptorHash = parentDescriptorHash == null
           ? null
           : Uint8List.fromList(parentDescriptorHash) {
    _validate();
  }

  final int protocolVersion;
  final RecipientWrapperSuiteId suiteId;
  final WrapperPurpose purpose;
  final EnvelopeScope scope;
  final int resourceRevision;
  final int wrappedKeyVersion;
  final int? memberKeyGeneration;
  final int recipientKeyKind;
  final int recipientKeyVersion;
  final Uint8List _recipientFingerprint;
  final Uint8List? _parentDescriptorHash;
  Uint8List get recipientFingerprint =>
      Uint8List.fromList(_recipientFingerprint);
  Uint8List? get parentDescriptorHash => _parentDescriptorHash == null
      ? null
      : Uint8List.fromList(_parentDescriptorHash);

  void _validate() {
    final hasEntry = scope.entryId != null;
    final hasGrant = scope.grantOrRequestId != null;
    final hasAgent = scope.agentId != null;
    final hasMember = scope.memberId != null;
    final scopeValid = switch (purpose) {
      WrapperPurpose.memberVaultKey =>
        !hasEntry && !hasGrant && !hasAgent && hasMember,
      WrapperPurpose.agentVdk =>
        !hasEntry && !hasGrant && hasAgent && !hasMember,
      WrapperPurpose.reasonDek ||
      WrapperPurpose.grantDek ||
      WrapperPurpose.scriptExecutionDek =>
        hasEntry && hasGrant && hasAgent && !hasMember,
      WrapperPurpose.agentVaultKey =>
        !hasEntry && hasGrant && hasAgent && !hasMember,
    };
    final needsParent =
        purpose == WrapperPurpose.reasonDek ||
        purpose == WrapperPurpose.grantDek ||
        purpose == WrapperPurpose.scriptExecutionDek;
    final expectedRecipientKeyKind = switch (purpose) {
      WrapperPurpose.memberVaultKey => 5,
      WrapperPurpose.agentVdk ||
      WrapperPurpose.grantDek ||
      WrapperPurpose.scriptExecutionDek => 1,
      WrapperPurpose.reasonDek => 4,
      WrapperPurpose.agentVaultKey => 1,
    };
    final needsGeneration = switch (purpose) {
      WrapperPurpose.memberVaultKey ||
      WrapperPurpose.reasonDek ||
      WrapperPurpose.grantDek => true,
      WrapperPurpose.agentVdk ||
      WrapperPurpose.agentVaultKey ||
      WrapperPurpose.scriptExecutionDek => false,
    };
    if (protocolVersion != 2 ||
        !scopeValid ||
        resourceRevision <= 0 ||
        wrappedKeyVersion <= 0 ||
        recipientKeyKind != expectedRecipientKeyKind ||
        recipientKeyVersion <= 0 ||
        recipientFingerprint.length != 32 ||
        recipientFingerprint.every((byte) => byte == 0) ||
        (memberKeyGeneration != null && memberKeyGeneration! <= 0) ||
        needsGeneration != (memberKeyGeneration != null) ||
        (parentDescriptorHash != null && parentDescriptorHash!.length != 32) ||
        needsParent != (parentDescriptorHash != null)) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
  }

  /// Canonical `PLDNX2W1` wrapper-context bytes.
  Uint8List encode() {
    final suite = ascii.encode(suiteId.wireValue);
    final builder = BytesBuilder(copy: false)
      ..add(ascii.encode('PLDNX2W1'))
      ..add(_u16(protocolVersion))
      ..add(_u16(suite.length))
      ..add(suite)
      ..add(_u16(purpose.id))
      ..add(encodeEnvelopeScope(scope))
      ..add(_u64(resourceRevision))
      ..add(_u32(wrappedKeyVersion))
      ..addByte(memberKeyGeneration == null ? 0 : 1);
    if (memberKeyGeneration != null) builder.add(_u32(memberKeyGeneration!));
    builder
      ..add(_u16(recipientKeyKind))
      ..add(_u32(recipientKeyVersion))
      ..add(recipientFingerprint);
    builder.addByte(parentDescriptorHash == null ? 0 : 1);
    if (parentDescriptorHash != null) builder.add(parentDescriptorHash!);
    return builder.takeBytes();
  }

  static Uint8List hashParent(EnvelopeDescriptor descriptor) =>
      Uint8List.fromList(sha256.convert(descriptor.encodeAad()).bytes);
}

/// Exact 120-byte `crypto_box_seal` wrapper for one 32-byte content key.
final class X25519SealedBoxKeyWrapper {
  X25519SealedBoxKeyWrapper({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  static const int encodedBytes = 120;
  static const int _keyBytes = 32;
  static const int _plaintextBytes = 72;
  final Future<SodiumSumo> Function() _sodiumLoader;

  Future<Uint8List> seal({
    required Uint8List key,
    required WrapperContext context,
    required X25519PublicKey recipient,
  }) async {
    if (key.length != _keyBytes) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    _verifyRecipient(recipient.bytes, context);
    final contextHash = _contextHash(context);
    final plaintext = Uint8List(_plaintextBytes)
      ..setRange(0, 8, ascii.encode('PLDNX2K1'))
      ..setRange(8, 40, key)
      ..setRange(40, 72, contextHash);
    try {
      final sodium = await _sodiumLoader();
      final sealed = sodium.crypto.box.seal(
        message: plaintext,
        publicKey: recipient.bytes,
      );
      if (sealed.length != encodedBytes) {
        throw const EnvelopeException(EnvelopeErrorKind.invalidPayload);
      }
      return sealed;
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  Future<Uint8List> open({
    required Uint8List wrapped,
    required WrapperContext context,
    required Uint8List recipientSecretKey,
  }) async {
    if (wrapped.length != encodedBytes || recipientSecretKey.length != 32) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidPayload);
    }
    final sodium = await _sodiumLoader();
    final secret = SecureKey.fromList(sodium, recipientSecretKey);
    Uint8List? plaintext;
    try {
      final publicKey = sodium.crypto.scalarmult.base(n: secret);
      _verifyRecipient(publicKey, context);
      try {
        plaintext = sodium.crypto.box.sealOpen(
          cipherText: wrapped,
          publicKey: publicKey,
          secretKey: secret,
        );
      } on SodiumException {
        throw const EnvelopeException(EnvelopeErrorKind.authenticationFailed);
      }
      final expectedHash = _contextHash(context);
      if (plaintext.length != _plaintextBytes ||
          !_constantTimeEqual(
            plaintext.sublist(0, 8),
            ascii.encode('PLDNX2K1'),
          ) ||
          !_constantTimeEqual(plaintext.sublist(40), expectedHash)) {
        throw const EnvelopeException(EnvelopeErrorKind.authenticationFailed);
      }
      return Uint8List.fromList(plaintext.sublist(8, 40));
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
      secret.dispose();
    }
  }
}

/// Builds the sole ciphertext material added by a FULL grant. The plaintext
/// Vault key is copied only into the native sealed-box call and is never
/// returned by this helper.
Future<Map<String, Object?>> buildAgentWrappedVaultKeyContract({
  required Uint8List vaultKey,
  required String organizationId,
  required String vaultId,
  required String grantId,
  required String agentId,
  required int agentAccessEpoch,
  required int vaultKeyVersion,
  required Uint8List agentPublicKey,
  required int recipientKeyVersion,
  Future<SodiumSumo> Function()? sodiumLoader,
}) async {
  final fingerprint = Uint8List.fromList(
    sha256.convert([
      ...ascii.encode('PLDNV2FP'),
      ..._u16(2),
      ..._u16(1),
      ...agentPublicKey,
    ]).bytes,
  );
  final context = WrapperContext(
    purpose: WrapperPurpose.agentVaultKey,
    scope: EnvelopeScope(
      organizationId: EnvelopeId.parse(organizationId),
      vaultId: EnvelopeId.parse(vaultId),
      grantOrRequestId: EnvelopeId.parse(grantId),
      agentId: EnvelopeId.parse(agentId),
    ),
    resourceRevision: agentAccessEpoch,
    wrappedKeyVersion: vaultKeyVersion,
    recipientKeyVersion: recipientKeyVersion,
    recipientFingerprint: fingerprint,
  );
  Uint8List? sealed;
  try {
    sealed = await X25519SealedBoxKeyWrapper(sodiumLoader: sodiumLoader).seal(
      key: vaultKey,
      context: context,
      recipient: X25519PublicKey(agentPublicKey),
    );
    return {
      'wrappedVaultKey': {
        'descriptor': {
          'protocolVersion': context.protocolVersion,
          'wrapperSuiteId': context.suiteId.wireValue,
          'purpose': context.purpose.id,
          'scope': {
            'organizationId': organizationId,
            'vaultId': vaultId,
            'entryId': null,
            'grantOrRequestId': grantId,
            'agentId': agentId,
            'memberId': null,
          },
          'resourceRevision': agentAccessEpoch.toString(),
          'wrappedKeyVersion': vaultKeyVersion,
          'memberKeyGeneration': null,
          'recipientKeyKind': 1,
          'recipientKeyVersion': recipientKeyVersion,
          'recipientFingerprint': base64UrlEncode(
            fingerprint,
          ).replaceAll('=', ''),
          'parentDescriptorHash': null,
        },
        'encodedSealedKeyPackage': base64UrlEncode(sealed).replaceAll('=', ''),
      },
    };
  } finally {
    fingerprint.fillRange(0, fingerprint.length, 0);
    sealed?.fillRange(0, sealed.length, 0);
  }
}

Uint8List _contextHash(WrapperContext context) => Uint8List.fromList(
  sha256.convert([...ascii.encode('PLDNX2CTX'), ...context.encode()]).bytes,
);

void _verifyRecipient(List<int> publicKey, WrapperContext context) {
  final actual = sha256.convert([
    ...ascii.encode('PLDNV2FP'),
    ..._u16(context.protocolVersion),
    ..._u16(context.recipientKeyKind),
    ...publicKey,
  ]).bytes;
  if (!_constantTimeEqual(actual, context.recipientFingerprint)) {
    throw const EnvelopeException(EnvelopeErrorKind.authenticationFailed);
  }
}

bool _constantTimeEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

Uint8List _u16(int value) => _number(value, 2);
Uint8List _u32(int value) => _number(value, 4);
Uint8List _u64(int value) => _number(value, 8);

Uint8List _number(int value, int width) {
  final data = ByteData(width);
  switch (width) {
    case 2:
      data.setUint16(0, value, Endian.big);
    case 4:
      data.setUint32(0, value, Endian.big);
    case 8:
      data.setUint64(0, value, Endian.big);
  }
  return data.buffer.asUint8List();
}
