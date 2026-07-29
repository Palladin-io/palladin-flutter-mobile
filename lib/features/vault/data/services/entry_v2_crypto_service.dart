import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/asymmetric_keys.dart';
import '../../../../core/crypto/envelope/envelope_contract.dart';
import '../../../../core/crypto/envelope/envelope_suite.dart';
import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/crypto/x25519_key_wrapper.dart';
import '../../domain/entities/vault_plaintext.dart';
import '../models/entry_v2_contracts.dart';

/// Canonical protocol-v2 crypto pipeline for Entry projections and secrets.
class EntryV2CryptoService {
  EntryV2CryptoService({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  /// Seals one canonical Grant payload and its DEK to an Agent recipient.
  Future<Map<String, Object?>> sealGrant({
    required String organizationId,
    required String vaultId,
    required String entryId,
    required String grantId,
    required String agentId,
    required int entryRevision,
    required int memberKeyGeneration,
    required Uint8List agentPublicKey,
    required int recipientKeyVersion,
    required int approvedMethods,
    required List<String> fieldIds,
    required Map<String, Object?> grantPayload,
    int grantEnvelopeRevision = 1,
    int grantKeyVersion = 1,
    DateTime? expiresAt,
    int? remainingUses,
  }) async {
    final sodium = await _sodiumLoader();
    final dek = sodium.randombytes.buf(32);
    final fingerprint = Uint8List.fromList(
      sha256.convert([
        ...ascii.encode('PLDNV2FP'),
        0,
        2,
        0,
        1,
        ...agentPublicKey,
      ]).bytes,
    );
    final commitment = computeFieldSetCommitment(fieldIds);
    final scope = EnvelopeScope(
      organizationId: EnvelopeId.parse(organizationId),
      vaultId: EnvelopeId.parse(vaultId),
      entryId: EnvelopeId.parse(entryId),
      grantOrRequestId: EnvelopeId.parse(grantId),
      agentId: EnvelopeId.parse(agentId),
    );
    final instant = expiresAt?.toUtc();
    final descriptor = EnvelopeDescriptor(
      purpose: EnvelopePurpose.grant,
      scope: scope,
      resourceRevision: grantEnvelopeRevision,
      keyVersion: grantKeyVersion,
      memberKeyGeneration: memberKeyGeneration,
      purposeData: GrantPurposeData(
        entryRevision: entryRevision,
        recipientKeyVersion: recipientKeyVersion,
        recipientFingerprint: fingerprint,
        methods: approvedMethods,
        fieldSetCommitment: commitment,
        expiresAtSeconds: instant == null
            ? null
            : instant.millisecondsSinceEpoch ~/ 1000,
        expiresAtNanoseconds: instant == null
            ? null
            : (instant.millisecondsSinceEpoch % 1000) * 1000000,
        remainingUses: remainingUses,
      ),
    );
    final plaintext = canonicalVaultJson(grantPayload);
    try {
      final envelope = await _sealEnvelope(
        XChaChaVaultEnvelopeSuite(sodiumLoader: _sodiumLoader),
        descriptor,
        dek,
        plaintext,
      );
      final parentHash = WrapperContext.hashParent(descriptor);
      final wrapper = WrapperContext(
        purpose: WrapperPurpose.grantDek,
        scope: scope,
        resourceRevision: grantEnvelopeRevision,
        wrappedKeyVersion: grantKeyVersion,
        memberKeyGeneration: memberKeyGeneration,
        recipientKeyVersion: recipientKeyVersion,
        recipientFingerprint: fingerprint,
        parentDescriptorHash: parentHash,
      );
      final sealed =
          await X25519SealedBoxKeyWrapper(sodiumLoader: _sodiumLoader).seal(
            key: dek,
            context: wrapper,
            recipient: X25519PublicKey(agentPublicKey),
          );
      return {
        ...envelope,
        'wrappedGrantDek': {
          'descriptor': _wrapperJson(wrapper),
          'encodedSealedKeyPackage': _b64(sealed),
        },
        'fieldIds': [...fieldIds]..sort(),
      };
    } finally {
      dek.fillRange(0, dek.length, 0);
      fingerprint.fillRange(0, fingerprint.length, 0);
      commitment.fillRange(0, commitment.length, 0);
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  Future<EntryEnvelopeBundleModel> seal({
    required String organizationId,
    required String vaultId,
    required String entryId,
    required int revision,
    int? entryKeyRevision,
    int? memberIndexRevision,
    int? agentDiscoveryRevision,
    int entryKeyVersion = 1,
    required int vaultKeyVersion,
    required int vdkVersion,
    required int memberKeyGeneration,
    required int operation,
    required MemberSecret secret,
    required Uint8List vaultKey,
    required Uint8List vaultDiscoveryKey,
    Uint8List? existingEntryDek,
  }) async {
    final sodium = await _sodiumLoader();
    final entryDek = existingEntryDek == null
        ? sodium.randombytes.buf(32)
        : Uint8List.fromList(existingEntryDek);
    final suite = XChaChaVaultEnvelopeSuite(sodiumLoader: _sodiumLoader);
    final scope = EnvelopeScope(
      organizationId: EnvelopeId.parse(organizationId),
      vaultId: EnvelopeId.parse(vaultId),
      entryId: EnvelopeId.parse(entryId),
    );
    final entryKeyDescriptor = EnvelopeDescriptor(
      purpose: EnvelopePurpose.entryDekByVk,
      scope: scope,
      resourceRevision: entryKeyRevision ?? revision,
      keyVersion: entryKeyVersion,
      memberKeyGeneration: memberKeyGeneration,
      purposeData: WrappingPurposeData(
        wrappingVaultKeyVersion: vaultKeyVersion,
      ),
    );
    final indexDescriptor = EnvelopeDescriptor(
      purpose: EnvelopePurpose.memberIndex,
      scope: scope,
      resourceRevision: memberIndexRevision ?? revision,
      keyVersion: entryKeyVersion,
      memberKeyGeneration: memberKeyGeneration,
    );
    final secretDescriptor = EnvelopeDescriptor(
      purpose: EnvelopePurpose.memberSecret,
      scope: scope,
      resourceRevision: revision,
      keyVersion: entryKeyVersion,
      memberKeyGeneration: memberKeyGeneration,
      purposeData: MemberSecretPurposeData(operation: operation),
    );
    final discoveryDescriptor = EnvelopeDescriptor(
      purpose: EnvelopePurpose.agentDiscovery,
      scope: scope,
      resourceRevision: agentDiscoveryRevision ?? revision,
      keyVersion: vdkVersion,
      memberKeyGeneration: memberKeyGeneration,
    );
    final secretBytes = canonicalVaultJson(secret.toJson());
    final indexBytes = canonicalVaultJson(
      VaultPlaintextProjector.memberIndex(secret).toJson(),
    );
    final discovery = VaultPlaintextProjector.agentDiscovery(secret);
    final discoveryBytes = discovery == null
        ? null
        : canonicalVaultJson(discovery);
    try {
      return EntryEnvelopeBundleModel(
        entryKey: await _sealEnvelope(
          suite,
          entryKeyDescriptor,
          vaultKey,
          entryDek,
        ),
        memberIndex: await _sealEnvelope(
          suite,
          indexDescriptor,
          vaultKey,
          indexBytes,
        ),
        memberSecret: await _sealEnvelope(
          suite,
          secretDescriptor,
          entryDek,
          secretBytes,
        ),
        agentDiscovery: discoveryBytes == null
            ? null
            : await _sealEnvelope(
                suite,
                discoveryDescriptor,
                vaultDiscoveryKey,
                discoveryBytes,
              ),
      );
    } finally {
      entryDek.fillRange(0, entryDek.length, 0);
      secretBytes.fillRange(0, secretBytes.length, 0);
      indexBytes.fillRange(0, indexBytes.length, 0);
      discoveryBytes?.fillRange(0, discoveryBytes.length, 0);
    }
  }

  Future<Map<String, dynamic>> openMemberIndex({
    required Map<String, dynamic> envelope,
    required Uint8List vaultKey,
  }) => _openJson(envelope, vaultKey, EnvelopePurpose.memberIndex);

  Future<Map<String, dynamic>> openMemberSecret({
    required Map<String, dynamic> entryKey,
    required Map<String, dynamic> memberSecret,
    required Uint8List vaultKey,
  }) async {
    final dek = await _open(entryKey, vaultKey, EnvelopePurpose.entryDekByVk);
    try {
      return await _openJson(memberSecret, dek, EnvelopePurpose.memberSecret);
    } finally {
      dek.fillRange(0, dek.length, 0);
    }
  }

  Future<Uint8List> openEntryDek({
    required Map<String, dynamic> entryKey,
    required Uint8List vaultKey,
  }) => _open(entryKey, vaultKey, EnvelopePurpose.entryDekByVk);

  Future<Map<String, Object?>> _sealEnvelope(
    ClientEnvelopeSuite suite,
    EnvelopeDescriptor descriptor,
    Uint8List rootKey,
    Uint8List plaintext,
  ) async {
    final payload = await suite.seal(
      descriptor: descriptor,
      rootKey: rootKey,
      plaintext: plaintext,
    );
    return {
      'descriptor': _descriptorJson(descriptor),
      'encodedSuitePayload': payload.toBase64Url(),
    };
  }

  Future<Map<String, dynamic>> _openJson(
    Map<String, dynamic> envelope,
    Uint8List key,
    EnvelopePurpose purpose,
  ) async {
    final plaintext = await _open(envelope, key, purpose);
    try {
      final value = jsonDecode(utf8.decode(plaintext));
      if (value is! Map<String, dynamic>) {
        throw const VaultPlaintextFormatException(
          'Plaintext is not an object.',
        );
      }
      return value;
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  Future<Uint8List> _open(
    Map<String, dynamic> envelope,
    Uint8List key,
    EnvelopePurpose purpose,
  ) async {
    final descriptorJson = envelope['descriptor'] as Map<String, dynamic>;
    final descriptor = entryEnvelopeDescriptorFromJson(descriptorJson, purpose);
    return CryptoSuiteRegistry()
        .resolveWire(descriptorJson['cryptoSuiteId'] as String)
        .open(
          descriptor: descriptor,
          rootKey: key,
          payload: EncodedSuitePayload.fromBase64Url(
            envelope['encodedSuitePayload'] as String,
          ),
        );
  }
}

@visibleForTesting
EnvelopeDescriptor entryEnvelopeDescriptorFromJson(
  Map<String, dynamic> json,
  EnvelopePurpose expected,
) {
  if (EnvelopePurpose.parseWire(json['purpose']) != expected) {
    throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
  }
  final scope = json['scope'] as Map<String, dynamic>;
  final binding = json['binding'] as Map<String, dynamic>;
  final purposeData = switch (expected) {
    EnvelopePurpose.entryDekByVk => WrappingPurposeData(
      wrappingVaultKeyVersion: binding['wrappingVaultKeyVersion'] as int,
    ),
    EnvelopePurpose.memberSecret => MemberSecretPurposeData(
      operation: binding['operation'] as int,
    ),
    _ => const NoPurposeData(),
  };
  return EnvelopeDescriptor(
    protocolVersion: json['protocolVersion'] as int,
    purpose: expected,
    scope: EnvelopeScope(
      organizationId: EnvelopeId.parse(scope['organizationId'] as String),
      vaultId: EnvelopeId.parse(scope['vaultId'] as String),
      entryId: EnvelopeId.parse(scope['entryId'] as String),
    ),
    resourceRevision: int.parse(json['resourceRevision'] as String),
    keyVersion: json['keyVersion'] as int,
    memberKeyGeneration: json['memberKeyGeneration'] as int?,
    purposeData: purposeData,
  );
}

Map<String, Object?> _descriptorJson(EnvelopeDescriptor value) => {
  'protocolVersion': value.protocolVersion,
  'cryptoSuiteId': value.cryptoSuiteId.wireValue,
  'purpose': value.purpose.id,
  'scope': {
    'organizationId': _id(value.scope.organizationId),
    'vaultId': _id(value.scope.vaultId),
    'entryId': _id(value.scope.entryId!),
    'grantOrRequestId': null,
    'agentId': null,
    'memberId': null,
  },
  'resourceRevision': value.resourceRevision.toString(),
  'keyVersion': value.keyVersion,
  'memberKeyGeneration': value.memberKeyGeneration,
  'binding': switch (value.purposeData) {
    WrappingPurposeData(:final wrappingVaultKeyVersion) => {
      'wrappingVaultKeyVersion': wrappingVaultKeyVersion,
    },
    MemberSecretPurposeData(:final operation) => {'operation': operation},
    GrantPurposeData(
      :final entryRevision,
      :final recipientKeyVersion,
      :final recipientFingerprint,
      :final methods,
      :final fieldSetCommitment,
      :final expiresAtSeconds,
      :final expiresAtNanoseconds,
      :final remainingUses,
    ) =>
      {
        'entryRevision': entryRevision.toString(),
        'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
        'recipientKeyVersion': recipientKeyVersion,
        'recipientKeyFingerprint': _b64(recipientFingerprint),
        'approvedMethods': methods,
        'fieldSetCommitment': _b64(fieldSetCommitment),
        'expiresAt': expiresAtSeconds == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                expiresAtSeconds * 1000 +
                    (expiresAtNanoseconds ?? 0) ~/ 1000000,
                isUtc: true,
              ).toIso8601String(),
        'remainingUses': remainingUses,
      },
    _ => <String, Object>{},
  },
};

String _id(EnvelopeId value) {
  final hex = value.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Map<String, Object?> _wrapperJson(WrapperContext value) => {
  'protocolVersion': value.protocolVersion,
  'wrapperSuiteId': value.suiteId.wireValue,
  'purpose': value.purpose.id,
  'scope': {
    'organizationId': _id(value.scope.organizationId),
    'vaultId': _id(value.scope.vaultId),
    'entryId': _id(value.scope.entryId!),
    'grantOrRequestId': _id(value.scope.grantOrRequestId!),
    'agentId': _id(value.scope.agentId!),
    'memberId': null,
  },
  'resourceRevision': value.resourceRevision.toString(),
  'wrappedKeyVersion': value.wrappedKeyVersion,
  'memberKeyGeneration': value.memberKeyGeneration,
  'recipientKeyKind': value.recipientKeyKind,
  'recipientKeyVersion': value.recipientKeyVersion,
  'recipientFingerprint': _b64(value.recipientFingerprint),
  'parentDescriptorHash': _b64(value.parentDescriptorHash!),
};

String _b64(List<int> value) => base64UrlEncode(value).replaceAll('=', '');
