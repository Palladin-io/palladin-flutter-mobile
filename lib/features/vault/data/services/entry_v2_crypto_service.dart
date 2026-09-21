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
import 'vault_protocol/vault_protocol_signature_service.dart';

const _agentWrappedVaultKeySignatureDomain =
    'PLDNV2SIG:AGENT-WRAPPED-VAULT-KEY:';

/// Canonical protocol-v2 crypto pipeline for Entry projections and secrets.
class EntryV2CryptoService {
  EntryV2CryptoService({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  /// Seals the current 32-byte Vault key to one authoritative Agent identity.
  /// The returned package is grant/Agent/access-epoch/VK-version bound and is
  /// the only extra ciphertext stored for a FULL grant.
  Future<Map<String, Object?>> sealAgentVaultKey({
    required Uint8List vaultKey,
    required String organizationId,
    required String vaultId,
    required String grantId,
    required String agentId,
    required int agentAccessEpoch,
    required int vaultKeyVersion,
    required Uint8List agentPublicKey,
    required int recipientKeyVersion,
    required int vaultSigningKeyVersion,
    required Uint8List vaultSigningPrivateKey,
  }) async {
    final sodium = await _sodiumLoader();
    final signing = _normalizeSigningKey(sodium, vaultSigningPrivateKey);
    final signingFingerprint = Uint8List.fromList(
      sha256.convert([
        ...ascii.encode('PLDNV2FP'),
        0,
        2,
        0,
        3,
        ...signing.publicKey,
      ]).bytes,
    );
    final signatures = VaultProtocolSignatureService(
      sodiumLoader: _sodiumLoader,
    );
    try {
      return await buildAgentWrappedVaultKeyContract(
        vaultKey: vaultKey,
        organizationId: organizationId,
        vaultId: vaultId,
        grantId: grantId,
        agentId: agentId,
        agentAccessEpoch: agentAccessEpoch,
        vaultKeyVersion: vaultKeyVersion,
        agentPublicKey: agentPublicKey,
        recipientKeyVersion: recipientKeyVersion,
        vaultSigningKeyVersion: vaultSigningKeyVersion,
        vaultSigningKeyFingerprint: signingFingerprint,
        signProducer: (unsigned) => signatures.sign(
          domainPrefix: _agentWrappedVaultKeySignatureDomain,
          unsignedObject: unsigned,
          privateKey: signing.privateKey,
        ),
        sodiumLoader: _sodiumLoader,
      );
    } finally {
      signing.publicKey.fillRange(0, signing.publicKey.length, 0);
      signing.privateKey.fillRange(0, signing.privateKey.length, 0);
      signingFingerprint.fillRange(0, signingFingerprint.length, 0);
    }
  }

  ({Uint8List publicKey, Uint8List privateKey}) _normalizeSigningKey(
    SodiumSumo sodium,
    Uint8List value,
  ) {
    if (value.length == sodium.crypto.sign.seedBytes) {
      final seed = SecureKey.fromList(sodium, value);
      try {
        final pair = sodium.crypto.sign.seedKeyPair(seed);
        try {
          return (
            publicKey: Uint8List.fromList(pair.publicKey),
            privateKey: Uint8List.fromList(pair.secretKey.extractBytes()),
          );
        } finally {
          pair.secretKey.dispose();
        }
      } finally {
        seed.dispose();
      }
    }
    if (value.length != sodium.crypto.sign.secretKeyBytes) {
      throw const FormatException('Vault signing key length is invalid');
    }
    final secretKey = SecureKey.fromList(sodium, value);
    try {
      return (
        publicKey: Uint8List.fromList(sodium.crypto.sign.skToPk(secretKey)),
        privateKey: Uint8List.fromList(value),
      );
    } finally {
      secretKey.dispose();
    }
  }

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
    required int deliveryPolicy,
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
    final instantMicros = instant?.microsecondsSinceEpoch;
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
        deliveryPolicy: deliveryPolicy,
        fieldSetCommitment: commitment,
        expiresAtSeconds: instantMicros == null
            ? null
            : instantMicros ~/ Duration.microsecondsPerSecond,
        expiresAtNanoseconds: instantMicros == null
            ? null
            : (instantMicros % Duration.microsecondsPerSecond) * 1000,
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
    Uint8List? secretBytes, indexBytes, discoveryBytes;
    try {
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
      secretBytes = canonicalVaultJson(secret.toJson());
      indexBytes = canonicalVaultJson(
        VaultPlaintextProjector.memberIndex(secret).toJson(),
      );
      final discovery = VaultPlaintextProjector.agentDiscovery(secret);
      discoveryBytes = discovery == null ? null : canonicalVaultJson(discovery);
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
          entryDek,
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
      secretBytes?.fillRange(0, secretBytes.length, 0);
      indexBytes?.fillRange(0, indexBytes.length, 0);
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

  /// Opens authenticated MemberSecret bytes without decoding the complete
  /// secret object. Callers own and must wipe the returned buffer.
  Future<Uint8List> openMemberSecretBytes({
    required Map<String, dynamic> entryKey,
    required Map<String, dynamic> memberSecret,
    required Uint8List vaultKey,
  }) async {
    final dek = await _open(entryKey, vaultKey, EnvelopePurpose.entryDekByVk);
    try {
      return await _open(memberSecret, dek, EnvelopePurpose.memberSecret);
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
    final suiteId = descriptorJson['cryptoSuiteId'];
    if (suiteId != CryptoSuiteId.palladinVaultXChaChaV1.wireValue) {
      throw const EnvelopeException(EnvelopeErrorKind.unsupportedSuite);
    }
    return XChaChaVaultEnvelopeSuite(sodiumLoader: _sodiumLoader).open(
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
      operation: _entryOperationFromJson(binding['operation']),
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

int _entryOperationFromJson(Object? value) => switch (value) {
  'created' || 1 => 1,
  'updated' || 2 => 2,
  'archived' || 3 => 3,
  'restored' || 4 => 4,
  'deleted' || 5 => 5,
  _ => throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor),
};

Map<String, Object?> _descriptorJson(EnvelopeDescriptor value) => {
  'protocolVersion': value.protocolVersion,
  'cryptoSuiteId': value.cryptoSuiteId.wireValue,
  'purpose': value.purpose.id,
  'scope': {
    'organizationId': _id(value.scope.organizationId),
    'vaultId': _id(value.scope.vaultId),
    'entryId': value.scope.entryId == null ? null : _id(value.scope.entryId!),
    'grantOrRequestId': value.scope.grantOrRequestId == null
        ? null
        : _id(value.scope.grantOrRequestId!),
    'agentId': value.scope.agentId == null ? null : _id(value.scope.agentId!),
    'memberId': value.scope.memberId == null
        ? null
        : _id(value.scope.memberId!),
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
      :final deliveryPolicy,
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
        'deliveryPolicy': deliveryPolicy,
        'fieldSetCommitment': _b64(fieldSetCommitment),
        'expiresAt': expiresAtSeconds == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(
                expiresAtSeconds * Duration.microsecondsPerSecond +
                    (expiresAtNanoseconds ?? 0) ~/ 1000,
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
    'entryId': value.scope.entryId == null ? null : _id(value.scope.entryId!),
    'grantOrRequestId': value.scope.grantOrRequestId == null
        ? null
        : _id(value.scope.grantOrRequestId!),
    'agentId': value.scope.agentId == null ? null : _id(value.scope.agentId!),
    'memberId': value.scope.memberId == null
        ? null
        : _id(value.scope.memberId!),
  },
  'resourceRevision': value.resourceRevision.toString(),
  'wrappedKeyVersion': value.wrappedKeyVersion,
  'memberKeyGeneration': value.memberKeyGeneration,
  'recipientKeyKind': value.recipientKeyKind,
  'recipientKeyVersion': value.recipientKeyVersion,
  'recipientFingerprint': _b64(value.recipientFingerprint),
  'parentDescriptorHash': value.parentDescriptorHash == null
      ? null
      : _b64(value.parentDescriptorHash!),
};

String _b64(List<int> value) => base64UrlEncode(value).replaceAll('=', '');
