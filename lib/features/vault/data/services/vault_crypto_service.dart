import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/asymmetric_keys.dart';
import '../../../../core/crypto/envelope/envelope_contract.dart';
import '../../../../core/crypto/envelope/envelope_suite.dart';
import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/crypto/x25519_key_wrapper.dart';
import '../../../../core/crypto/vault_session_store.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/entities/vault_plaintext.dart';
import '../models/vault_v2_contracts.dart';

/// Zero-knowledge crypto pipeline for vault creation.
///
/// Generates a fresh 32-byte vault key (VK) and seals it for the
/// user's X25519 public key using `crypto_box_seal` (anonymous sealed
/// box). The wrapped VK is base64-encoded and shipped to the backend
/// — the plaintext VK never leaves this method's stack frame.
///
/// The owner derives their own public key from [privateKey] via
/// `crypto_scalarmult_base`, so the caller only needs to supply the
/// private key already cached in the unlocked auth state.
class VaultCryptoService {
  VaultCryptoService({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  /// Opens the caller-specific VK wrapper and authenticated Vault metadata.
  Future<OpenedVaultProjection> openVaultProjection({
    required Map<String, dynamic> json,
    required Uint8List memberPrivateKey,
  }) async {
    final wrappedRoot = json['memberVaultKey'] as Map<String, dynamic>;
    final wrapped = wrappedRoot['wrappedVaultKey'] as Map<String, dynamic>;
    final wrapperJson = wrapped['descriptor'] as Map<String, dynamic>;
    final wrapperScope = wrapperJson['scope'] as Map<String, dynamic>;
    final scope = EnvelopeScope(
      organizationId: EnvelopeId.parse(
        wrapperScope['organizationId'] as String,
      ),
      vaultId: EnvelopeId.parse(wrapperScope['vaultId'] as String),
      memberId: EnvelopeId.parse(wrapperScope['memberId'] as String),
    );
    final wrapper = WrapperContext(
      protocolVersion: wrapperJson['protocolVersion'] as int,
      purpose: WrapperPurpose.memberVaultKey,
      scope: scope,
      resourceRevision: int.parse(wrapperJson['resourceRevision'] as String),
      wrappedKeyVersion: wrapperJson['wrappedKeyVersion'] as int,
      memberKeyGeneration: wrapperJson['memberKeyGeneration'] as int,
      recipientKeyKind: wrapperJson['recipientKeyKind'] as int,
      recipientKeyVersion: wrapperJson['recipientKeyVersion'] as int,
      recipientFingerprint: _decode(
        wrapperJson['recipientFingerprint'] as String,
      ),
    );
    final vk = await X25519SealedBoxKeyWrapper(sodiumLoader: _sodiumLoader)
        .open(
          wrapped: _decode(wrapped['encodedSealedKeyPackage'] as String),
          context: wrapper,
          recipientSecretKey: memberPrivateKey,
        );
    Uint8List? plaintext;
    Uint8List? discoveryKey;
    try {
      final metadataJson = json['memberVaultMetadata'] as Map<String, dynamic>;
      final descriptorJson = metadataJson['descriptor'] as Map<String, dynamic>;
      final descriptorScope = descriptorJson['scope'] as Map<String, dynamic>;
      final descriptor = EnvelopeDescriptor(
        protocolVersion: descriptorJson['protocolVersion'] as int,
        cryptoSuiteId: CryptoSuiteId.palladinVaultXChaChaV1,
        purpose: EnvelopePurpose.memberVaultMetadata,
        scope: EnvelopeScope(
          organizationId: EnvelopeId.parse(
            descriptorScope['organizationId'] as String,
          ),
          vaultId: EnvelopeId.parse(descriptorScope['vaultId'] as String),
        ),
        resourceRevision: int.parse(
          descriptorJson['resourceRevision'] as String,
        ),
        keyVersion: descriptorJson['keyVersion'] as int,
        memberKeyGeneration: descriptorJson['memberKeyGeneration'] as int,
      );
      plaintext = await CryptoSuiteRegistry()
          .resolveWire(descriptorJson['cryptoSuiteId'] as String)
          .open(
            descriptor: descriptor,
            rootKey: vk,
            payload: EncodedSuitePayload.fromBase64Url(
              metadataJson['encodedSuitePayload'] as String,
            ),
          );
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map<String, dynamic>) {
        throw const VaultPlaintextFormatException('Metadata is not an object.');
      }
      final discoveryJson = json['discoveryKey'];
      if (discoveryJson is Map<String, dynamic>) {
        discoveryKey = await _openVkWrappedEnvelope(
          json: discoveryJson,
          expectedPurpose: EnvelopePurpose.vaultDiscoveryKeyByVk,
          vaultKey: vk,
        );
      }
      return OpenedVaultProjection(
        organizationId: wrapperScope['organizationId'] as String,
        vaultId: wrapperScope['vaultId'] as String,
        vaultKey: Uint8List.fromList(vk),
        vaultDiscoveryKey: discoveryKey == null
            ? null
            : Uint8List.fromList(discoveryKey),
        metadata: MemberVaultMetadata.fromJson(decoded),
        epoch: VaultKeyEpochModel(
          vaultKeyVersion:
              (json['currentKeyEpoch']
                      as Map<String, dynamic>)['vaultKeyVersion']
                  as int,
          vdkVersion:
              (json['currentKeyEpoch'] as Map<String, dynamic>)['vdkVersion']
                  as int,
          agentMessageKeyVersion:
              (json['currentKeyEpoch']
                      as Map<String, dynamic>)['agentMessageKeyVersion']
                  as int,
          manifestSigningKeyVersion:
              (json['currentKeyEpoch']
                      as Map<String, dynamic>)['manifestSigningKeyVersion']
                  as int,
        ),
        memberKeyGeneration: json['memberKeyGeneration'] as int,
        wrapper: MemberVaultKeyWrapperMetadata(
          wrapperSuiteId: wrapperJson['wrapperSuiteId'] as String,
          wrappedKeyVersion: wrapperJson['wrappedKeyVersion'] as int,
          memberKeyGeneration: wrapperJson['memberKeyGeneration'] as int,
          recipientKeyVersion: wrapperJson['recipientKeyVersion'] as int,
          recipientFingerprint: wrapperJson['recipientFingerprint'] as String,
        ),
      );
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
      discoveryKey?.fillRange(0, discoveryKey.length, 0);
      vk.fillRange(0, vk.length, 0);
    }
  }

  Future<Uint8List> _openVkWrappedEnvelope({
    required Map<String, dynamic> json,
    required EnvelopePurpose expectedPurpose,
    required Uint8List vaultKey,
  }) async {
    final descriptorJson = json['descriptor'] as Map<String, dynamic>;
    if (descriptorJson['purpose'] != expectedPurpose.id) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    final scopeJson = descriptorJson['scope'] as Map<String, dynamic>;
    final binding = descriptorJson['binding'] as Map<String, dynamic>;
    final descriptor = EnvelopeDescriptor(
      protocolVersion: descriptorJson['protocolVersion'] as int,
      cryptoSuiteId: CryptoSuiteId.palladinVaultXChaChaV1,
      purpose: expectedPurpose,
      scope: EnvelopeScope(
        organizationId: EnvelopeId.parse(scopeJson['organizationId'] as String),
        vaultId: EnvelopeId.parse(scopeJson['vaultId'] as String),
      ),
      resourceRevision: int.parse(descriptorJson['resourceRevision'] as String),
      keyVersion: descriptorJson['keyVersion'] as int,
      memberKeyGeneration: descriptorJson['memberKeyGeneration'] as int?,
      purposeData: WrappingPurposeData(
        wrappingVaultKeyVersion: binding['wrappingVaultKeyVersion'] as int,
      ),
    );
    return CryptoSuiteRegistry()
        .resolveWire(descriptorJson['cryptoSuiteId'] as String)
        .open(
          descriptor: descriptor,
          rootKey: vaultKey,
          payload: EncodedSuitePayload.fromBase64Url(
            json['encodedSuitePayload'] as String,
          ),
        );
  }

  /// Builds the complete challenge-bound protocol-v2 Vault transition.
  Future<CreatedVaultBundle> createVaultBundle({
    required String organizationId,
    required String memberId,
    required int memberKeyVersion,
    required String vaultId,
    required Uint8List memberPrivateKey,
    required String name,
    String? description,
    String? icon,
    String? color,
    required GrantMode grantMode,
  }) async {
    final sodium = await _sodiumLoader();
    final vk = sodium.randombytes.buf(32);
    final vdk = sodium.randombytes.buf(32);
    final messageKeys = sodium.crypto.box.keyPair();
    final signingKeys = sodium.crypto.sign.keyPair();
    final memberSecret = SecureKey.fromList(sodium, memberPrivateKey);
    Uint8List? messagePrivate;
    Uint8List? signingPrivate;
    Uint8List? metadataPlaintext;
    try {
      messagePrivate = messageKeys.secretKey.extractBytes();
      signingPrivate = signingKeys.secretKey.extractBytes();
      final memberPublic = sodium.crypto.scalarmult.base(n: memberSecret);
      final scope = EnvelopeScope(
        organizationId: EnvelopeId.parse(organizationId),
        vaultId: EnvelopeId.parse(vaultId),
        memberId: EnvelopeId.parse(memberId),
      );
      final vaultScope = EnvelopeScope(
        organizationId: scope.organizationId,
        vaultId: scope.vaultId,
      );
      final suite = XChaChaVaultEnvelopeSuite(sodiumLoader: _sodiumLoader);
      final metadataDescriptor = EnvelopeDescriptor(
        purpose: EnvelopePurpose.memberVaultMetadata,
        scope: vaultScope,
        resourceRevision: 1,
        keyVersion: 1,
        memberKeyGeneration: 1,
      );
      final metadata = MemberVaultMetadata(
        name: name,
        description: description,
        icon: icon == null ? null : GlyphVaultIcon(icon),
        color: color?.toUpperCase(),
        grantMode: grantMode == GrantMode.full ? 'full' : 'granular',
      );
      metadataPlaintext = canonicalVaultJson(metadata.toJson());
      final metadataPayload = await suite.seal(
        descriptor: metadataDescriptor,
        rootKey: vk,
        plaintext: metadataPlaintext,
      );

      Future<VaultOpaqueEnvelopeModel> wrapByVk({
        required EnvelopePurpose purpose,
        required Uint8List plaintext,
      }) async {
        final descriptor = EnvelopeDescriptor(
          purpose: purpose,
          scope: vaultScope,
          resourceRevision: 1,
          keyVersion: 1,
          memberKeyGeneration: 1,
          purposeData: const WrappingPurposeData(wrappingVaultKeyVersion: 1),
        );
        final payload = await suite.seal(
          descriptor: descriptor,
          rootKey: vk,
          plaintext: plaintext,
        );
        return VaultOpaqueEnvelopeModel(
          descriptor: _descriptorJson(descriptor),
          encodedSuitePayload: payload.toBase64Url(),
        );
      }

      final wrapperContext = WrapperContext(
        purpose: WrapperPurpose.memberVaultKey,
        scope: scope,
        resourceRevision: 1,
        wrappedKeyVersion: 1,
        memberKeyGeneration: 1,
        recipientKeyKind: 5,
        recipientKeyVersion: memberKeyVersion,
        recipientFingerprint: _fingerprint(memberPublic, 5),
      );
      final sealedVk =
          await X25519SealedBoxKeyWrapper(sodiumLoader: _sodiumLoader).seal(
            key: vk,
            context: wrapperContext,
            recipient: X25519PublicKey(memberPublic),
          );
      final messageFingerprint = _fingerprint(messageKeys.publicKey, 4);
      final signingFingerprint = _fingerprint(signingKeys.publicKey, 3);
      final request = CreateVaultV2Request(
        vaultId: vaultId,
        memberVaultMetadata: VaultOpaqueEnvelopeModel(
          descriptor: _descriptorJson(metadataDescriptor),
          encodedSuitePayload: metadataPayload.toBase64Url(),
        ),
        currentKeyEpoch: const VaultKeyEpochModel(
          vaultKeyVersion: 1,
          vdkVersion: 1,
          agentMessageKeyVersion: 1,
          manifestSigningKeyVersion: 1,
        ),
        creatorVaultKey: X25519WrappedKeyModel(
          descriptor: _wrapperJson(wrapperContext),
          encodedSealedKeyPackage: _b64(sealedVk),
        ),
        discoveryKey: await wrapByVk(
          purpose: EnvelopePurpose.vaultDiscoveryKeyByVk,
          plaintext: vdk,
        ),
        vaultPrivateKeys: [
          await wrapByVk(
            purpose: EnvelopePurpose.agentMessagePrivateByVk,
            plaintext: messagePrivate,
          ),
          await wrapByVk(
            purpose: EnvelopePurpose.manifestPrivateByVk,
            plaintext: signingPrivate,
          ),
        ],
        vaultAgentMessagePublicKey: VaultPublicKeyContractModel(
          schemeId: 'palladin-x25519-v1',
          keyKind: VaultPublicKeyKind.agentMessageX25519,
          keyVersion: 1,
          encodedPublicKey: _b64(messageKeys.publicKey),
          fingerprint: _b64(messageFingerprint),
        ),
        vaultManifestSigningPublicKey: VaultPublicKeyContractModel(
          schemeId: 'palladin-ed25519-v1',
          keyKind: VaultPublicKeyKind.manifestSigningEd25519,
          keyVersion: 1,
          encodedPublicKey: _b64(signingKeys.publicKey),
          fingerprint: _b64(signingFingerprint),
        ),
      );
      return CreatedVaultBundle(
        request: request,
        vaultKey: Uint8List.fromList(vk),
        vaultDiscoveryKey: Uint8List.fromList(vdk),
        metadata: metadata,
        memberFingerprint: _b64(_fingerprint(memberPublic, 5)),
      );
    } finally {
      vk.fillRange(0, vk.length, 0);
      vdk.fillRange(0, vdk.length, 0);
      messagePrivate?.fillRange(0, messagePrivate.length, 0);
      signingPrivate?.fillRange(0, signingPrivate.length, 0);
      metadataPlaintext?.fillRange(0, metadataPlaintext.length, 0);
      memberSecret.dispose();
      messageKeys.dispose();
      signingKeys.dispose();
    }
  }

  /// Generates a random 32-byte vault key, derives the user's X25519
  /// public key from [privateKey], seals the VK for that public key,
  /// and returns the sealed bytes base64-encoded.
  ///
  /// The plaintext VK and any intermediate [SecureKey] handles are
  /// disposed before returning — only the sealed copy survives this
  /// call.
  Future<String> generateWrappedVK(Uint8List privateKey) async {
    final sodium = await _sodiumLoader();

    final vk = sodium.randombytes.buf(32);
    final scalar = SecureKey.fromList(sodium, privateKey);
    try {
      final publicKey = sodium.crypto.scalarmult.base(n: scalar);

      final wrapped = sodium.crypto.box.seal(message: vk, publicKey: publicKey);

      return base64.encode(wrapped);
    } finally {
      // Zeroize the plaintext VK and the SecureKey copy of the
      // private key — the wrapped copy is the only thing that should
      // survive this method.
      vk.fillRange(0, vk.length, 0);
      scalar.dispose();
    }
  }

  /// Generates a random 32-byte vault key, seals it directly for the
  /// supplied X25519 [publicKey], and returns the sealed bytes
  /// base64-encoded.
  ///
  /// Use this variant when the private key is unavailable (e.g. during
  /// the onboarding flow where the keypair is generated, used to build
  /// the setup payload, and then zeroed before this call). The public
  /// key from [OnboardingSetupPayload.publicKey] is passed directly so
  /// no private-key material is needed.
  ///
  /// The plaintext VK is zeroized before returning.
  Future<String> generateWrappedVKFromPublicKey(Uint8List publicKey) async {
    final sodium = await _sodiumLoader();
    final vk = sodium.randombytes.buf(32);
    try {
      final wrapped = sodium.crypto.box.seal(message: vk, publicKey: publicKey);
      return base64.encode(wrapped);
    } finally {
      vk.fillRange(0, vk.length, 0);
    }
  }
}

/// Complete create transition plus the only raw key retained by the caller.
final class CreatedVaultBundle {
  const CreatedVaultBundle({
    required this.request,
    required this.vaultKey,
    required this.vaultDiscoveryKey,
    required this.metadata,
    required this.memberFingerprint,
  });
  final CreateVaultV2Request request;
  final Uint8List vaultKey;
  final Uint8List vaultDiscoveryKey;
  final MemberVaultMetadata metadata;
  final String memberFingerprint;
}

/// Decrypted metadata plus raw VK handed directly to the in-memory store.
final class OpenedVaultProjection {
  const OpenedVaultProjection({
    required this.organizationId,
    required this.vaultId,
    required this.vaultKey,
    required this.vaultDiscoveryKey,
    required this.metadata,
    required this.epoch,
    required this.memberKeyGeneration,
    required this.wrapper,
  });
  final String organizationId;
  final String vaultId;
  final Uint8List vaultKey;
  final Uint8List? vaultDiscoveryKey;
  final MemberVaultMetadata metadata;
  final VaultKeyEpochModel epoch;
  final int memberKeyGeneration;
  final MemberVaultKeyWrapperMetadata wrapper;
}

Map<String, Object?> _scopeJson(EnvelopeScope scope) => {
  'organizationId': _idString(scope.organizationId),
  'vaultId': _idString(scope.vaultId),
  'entryId': scope.entryId == null ? null : _idString(scope.entryId!),
  'grantOrRequestId': scope.grantOrRequestId == null
      ? null
      : _idString(scope.grantOrRequestId!),
  'agentId': scope.agentId == null ? null : _idString(scope.agentId!),
  'memberId': scope.memberId == null ? null : _idString(scope.memberId!),
};

Map<String, Object?> _descriptorJson(EnvelopeDescriptor value) => {
  'protocolVersion': value.protocolVersion,
  'cryptoSuiteId': value.cryptoSuiteId.wireValue,
  'purpose': value.purpose.id,
  'scope': _scopeJson(value.scope),
  'resourceRevision': value.resourceRevision.toString(),
  'keyVersion': value.keyVersion,
  'memberKeyGeneration': value.memberKeyGeneration,
  'binding': switch (value.purposeData) {
    WrappingPurposeData(:final wrappingVaultKeyVersion) => {
      'wrappingVaultKeyVersion': wrappingVaultKeyVersion,
    },
    _ => <String, Object>{},
  },
};

X25519WrapperDescriptorModel _wrapperJson(WrapperContext value) =>
    X25519WrapperDescriptorModel(
      protocolVersion: value.protocolVersion,
      wrapperSuiteId: value.suiteId.wireValue,
      purpose: value.purpose.id,
      scope: _scopeJson(value.scope),
      resourceRevision: value.resourceRevision.toString(),
      wrappedKeyVersion: value.wrappedKeyVersion,
      memberKeyGeneration: value.memberKeyGeneration,
      recipientKeyKind: value.recipientKeyKind,
      recipientKeyVersion: value.recipientKeyVersion,
      recipientFingerprint: _b64(value.recipientFingerprint),
      parentDescriptorHash: value.parentDescriptorHash == null
          ? null
          : _b64(value.parentDescriptorHash!),
    );

Uint8List _fingerprint(List<int> publicKey, int kind) {
  final data = ByteData(4)
    ..setUint16(0, 2, Endian.big)
    ..setUint16(2, kind, Endian.big);
  return Uint8List.fromList(
    sha256.convert([
      ...ascii.encode('PLDNV2FP'),
      ...data.buffer.asUint8List(),
      ...publicKey,
    ]).bytes,
  );
}

String _b64(List<int> value) => base64UrlEncode(value).replaceAll('=', '');

Uint8List _decode(String value) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));

String _idString(EnvelopeId id) {
  final hex = id.bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
