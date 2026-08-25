import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/envelope/envelope_contract.dart';
import '../../../../core/crypto/envelope/envelope_suite.dart';
import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/crypto/x25519_key_wrapper.dart';
import '../models/vault_rotation_models.dart';
import 'vault_protocol/vault_protocol_aad.dart';
import 'vault_protocol/vault_protocol_bytes.dart';
import 'vault_protocol/vault_protocol_envelope_service.dart';
import 'vault_protocol/vault_protocol_fingerprint.dart';
import 'vault_protocol/vault_protocol_kdf.dart';
import 'vault_protocol/vault_protocol_signature_service.dart';

final class VaultRotationKeys {
  VaultRotationKeys({
    required this.vaultKey,
    required this.vdk,
    required this.agentMessagePrivateKey,
    required this.manifestSigningSeed,
  });

  final Uint8List vaultKey;
  final Uint8List vdk;
  final Uint8List agentMessagePrivateKey;
  final Uint8List manifestSigningSeed;

  void dispose() {
    for (final key in [
      vaultKey,
      vdk,
      agentMessagePrivateKey,
      manifestSigningSeed,
    ]) {
      key.fillRange(0, key.length, 0);
    }
  }
}

EnvelopeId? _optionalEnvelopeId(Object? value) =>
    value == null ? null : EnvelopeId.parse(value as String);

/// All cryptographic transformations used by the staged rotation engine.
class VaultRotationCryptoService {
  VaultRotationCryptoService({
    Future<SodiumSumo> Function()? sodiumLoader,
    VaultProtocolEnvelopeService? envelopes,
    VaultProtocolSignatureService? signatures,
    CryptoSuiteRegistry? cryptoSuites,
  }) : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance,
       _envelopes = envelopes ?? VaultProtocolEnvelopeService(),
       _signatures =
           signatures ??
           VaultProtocolSignatureService(
             sodiumLoader: sodiumLoader ?? SodiumProvider.instance,
           ),
       _cryptoSuites =
           cryptoSuites ??
           CryptoSuiteRegistry(
             suites: [
               XChaChaVaultEnvelopeSuite(
                 sodiumLoader: sodiumLoader ?? SodiumProvider.instance,
               ),
             ],
           );

  final Future<SodiumSumo> Function() _sodiumLoader;
  final VaultProtocolEnvelopeService _envelopes;
  final VaultProtocolSignatureService _signatures;
  final CryptoSuiteRegistry _cryptoSuites;

  /// Selects one canonical Vault private-key envelope by authenticated
  /// descriptor fields. The current API does not expose legacy flattened
  /// `privateKeyKind` / `privateKeyVersion` properties.
  static Map<String, dynamic> requirePrivateKeyEnvelope({
    required Object? envelopes,
    required String purpose,
    required int keyVersion,
  }) {
    if (envelopes is! List || keyVersion <= 0) {
      throw const FormatException('Malformed Vault private-key directory');
    }
    final matches = envelopes
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .where((item) {
          final descriptor = item['descriptor'];
          if (descriptor is! Map) return false;
          return descriptor['purpose'] == purpose &&
              descriptor['keyVersion'] == keyVersion;
        })
        .toList(growable: false);
    if (matches.length != 1) {
      throw const FormatException('Vault private key is unavailable');
    }
    return matches.single;
  }

  Future<VaultRotationKeys> generateKeys() async {
    final sodium = await _sodiumLoader();
    final messagePair = sodium.crypto.box.keyPair();
    try {
      return VaultRotationKeys(
        vaultKey: sodium.randombytes.buf(32),
        vdk: sodium.randombytes.buf(32),
        agentMessagePrivateKey: messagePair.secretKey.extractBytes(),
        manifestSigningSeed: sodium.randombytes.buf(32),
      );
    } finally {
      messagePair.dispose();
    }
  }

  Future<Map<String, Object?>> sealAgentVaultKey({
    required RotationFullGrantRecipient recipient,
    required String organizationId,
    required String vaultId,
    required int vaultKeyVersion,
    required Uint8List vaultKey,
    required int vaultSigningKeyVersion,
    required Uint8List vaultSigningPrivateKey,
  }) async {
    final publicKey = VaultProtocolBytes.base64UrlDecode(
      recipient.x25519PublicKey,
    );
    final sodium = await _sodiumLoader();
    final signing = _normalizeSigningKey(sodium, vaultSigningPrivateKey);
    final signingFingerprint = vaultPublicKeyFingerprint(
      VaultPublicKeyKind.vaultSigningEd25519,
      signing.publicKey,
    );
    try {
      if (_fingerprint(VaultPublicKeyKind.agentX25519, publicKey) !=
          recipient.recipientKeyFingerprint) {
        throw const FormatException('Agent recipient fingerprint mismatch');
      }
      return await buildAgentWrappedVaultKeyContract(
        vaultKey: vaultKey,
        organizationId: organizationId,
        vaultId: vaultId,
        grantId: recipient.grantId,
        agentId: recipient.agentId,
        agentAccessEpoch: recipient.agentAccessEpoch,
        vaultKeyVersion: vaultKeyVersion,
        agentPublicKey: publicKey,
        recipientKeyVersion: recipient.recipientKeyVersion,
        vaultSigningKeyVersion: vaultSigningKeyVersion,
        vaultSigningKeyFingerprint: signingFingerprint,
        signProducer: (unsigned) => _signatures.sign(
          domainPrefix: 'PLDNV2SIG:AGENT-WRAPPED-VAULT-KEY:',
          unsignedObject: unsigned,
          privateKey: signing.privateKey,
        ),
        sodiumLoader: _sodiumLoader,
      );
    } finally {
      publicKey.fillRange(0, publicKey.length, 0);
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

  Future<Uint8List> openMemberVaultKey(
    Map<String, dynamic> envelope,
    Uint8List memberPrivateKey,
  ) async {
    if (memberPrivateKey.length != 32 || envelope['wrappedVaultKey'] is! Map) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    final wrapped = Map<String, dynamic>.from(
      envelope['wrappedVaultKey'] as Map,
    );
    if (wrapped['descriptor'] is! Map) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    final descriptor = Map<String, dynamic>.from(wrapped['descriptor'] as Map);
    final purpose = WrapperPurpose.parseWire(descriptor['purpose']);
    final scopeJson = descriptor['scope'];
    if (purpose != WrapperPurpose.memberVaultKey ||
        scopeJson is! Map ||
        descriptor['wrapperSuiteId'] !=
            RecipientWrapperSuiteId.x25519SealedBoxV1.wireValue) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    final scope = Map<String, dynamic>.from(scopeJson);
    final protocolVersion = descriptor['protocolVersion'];
    final organizationId = scope['organizationId'];
    final vaultId = scope['vaultId'];
    final memberId = scope['memberId'];
    final resourceRevision = descriptor['resourceRevision'];
    final wrappedKeyVersion = descriptor['wrappedKeyVersion'];
    final memberKeyGeneration = descriptor['memberKeyGeneration'];
    final recipientKeyKind = descriptor['recipientKeyKind'];
    final recipientKeyVersion = descriptor['recipientKeyVersion'];
    final recipientFingerprint = descriptor['recipientFingerprint'];
    final encodedSealedKeyPackage = wrapped['encodedSealedKeyPackage'];
    if (protocolVersion is! int ||
        organizationId is! String ||
        vaultId is! String ||
        memberId is! String ||
        resourceRevision is! String ||
        wrappedKeyVersion is! int ||
        memberKeyGeneration is! int ||
        recipientKeyVersion is! int ||
        recipientFingerprint is! String ||
        encodedSealedKeyPackage is! String) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }

    final parsedRecipientKeyKind = VaultPublicKeyKind.parseWire(
      recipientKeyKind,
    );
    if (parsedRecipientKeyKind != VaultPublicKeyKind.memberX25519) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    final fingerprint = VaultProtocolBytes.base64UrlDecode(
      recipientFingerprint,
      maximumBytes: 32,
    );
    final sealedPackage = VaultProtocolBytes.base64UrlDecode(
      encodedSealedKeyPackage,
      maximumBytes: 4096,
    );
    try {
      final context = WrapperContext(
        protocolVersion: protocolVersion,
        purpose: purpose,
        scope: EnvelopeScope(
          organizationId: EnvelopeId.parse(organizationId),
          vaultId: EnvelopeId.parse(vaultId),
          memberId: EnvelopeId.parse(memberId),
        ),
        resourceRevision: int.parse(resourceRevision),
        wrappedKeyVersion: wrappedKeyVersion,
        memberKeyGeneration: memberKeyGeneration,
        recipientKeyKind: parsedRecipientKeyKind.id,
        recipientKeyVersion: recipientKeyVersion,
        recipientFingerprint: fingerprint,
      );
      return await X25519SealedBoxKeyWrapper(sodiumLoader: _sodiumLoader).open(
        wrapped: sealedPackage,
        context: context,
        recipientSecretKey: memberPrivateKey,
      );
    } finally {
      fingerprint.fillRange(0, fingerprint.length, 0);
      sealedPackage.fillRange(0, sealedPackage.length, 0);
    }
  }

  Future<Uint8List> openDiscoveryKey(
    Map<String, dynamic> envelope,
    Uint8List vaultKey,
  ) => _openAead(VaultAadProfile.vaultDiscoveryKey, envelope, vaultKey);

  Future<Uint8List> openPrivateKey(
    Map<String, dynamic> envelope,
    Uint8List vaultKey,
  ) => _openAead(VaultAadProfile.vaultPrivateKey, envelope, vaultKey);

  /// Opens the current descriptor-based Agent-message private-key envelope
  /// returned by `GET /api/vaults/{id}`. Rotation claim payloads still use the
  /// frozen binary-AAD projection handled by [openPrivateKey].
  Future<Uint8List> openCanonicalAgentMessagePrivateKey(
    Map<String, dynamic> envelope,
    Uint8List vaultKey, {
    required int expectedKeyVersion,
  }) => _openCanonicalVaultPrivateKey(
    envelope,
    vaultKey,
    expectedKeyVersion: expectedKeyVersion,
    expectedPurpose: EnvelopePurpose.agentMessagePrivateByVk,
    label: 'Agent message private key',
  );

  Future<Uint8List> openCanonicalManifestSigningPrivateKey(
    Map<String, dynamic> envelope,
    Uint8List vaultKey, {
    required int expectedKeyVersion,
  }) => _openCanonicalVaultPrivateKey(
    envelope,
    vaultKey,
    expectedKeyVersion: expectedKeyVersion,
    expectedPurpose: EnvelopePurpose.manifestPrivateByVk,
    label: 'Vault manifest signing seed',
  );

  Future<Uint8List> _openCanonicalVaultPrivateKey(
    Map<String, dynamic> envelope,
    Uint8List vaultKey, {
    required int expectedKeyVersion,
    required EnvelopePurpose expectedPurpose,
    required String label,
  }) async {
    final descriptorJson = envelope['descriptor'];
    final encodedPayload = envelope['encodedSuitePayload'];
    if (descriptorJson is! Map || encodedPayload is! String) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    final descriptor = Map<String, dynamic>.from(descriptorJson);
    final scopeJson = descriptor['scope'];
    final bindingJson = descriptor['binding'];
    if (scopeJson is! Map || bindingJson is! Map) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    final purpose = EnvelopePurpose.parseWire(descriptor['purpose']);
    final keyVersion = descriptor['keyVersion'];
    final memberKeyGeneration = descriptor['memberKeyGeneration'];
    final resourceRevision = descriptor['resourceRevision'];
    final cryptoSuiteId = descriptor['cryptoSuiteId'];
    final wrappingVaultKeyVersion = bindingJson['wrappingVaultKeyVersion'];
    if (purpose != expectedPurpose ||
        keyVersion is! int ||
        keyVersion != expectedKeyVersion ||
        memberKeyGeneration is! int ||
        resourceRevision is! String ||
        cryptoSuiteId is! String ||
        wrappingVaultKeyVersion is! int) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }
    final revisionBytes = VaultProtocolBytes.u64(resourceRevision);
    revisionBytes.fillRange(0, revisionBytes.length, 0);
    final scope = Map<String, dynamic>.from(scopeJson);
    final envelopeDescriptor = EnvelopeDescriptor(
      protocolVersion: descriptor['protocolVersion'] as int,
      cryptoSuiteId: CryptoSuiteId.palladinVaultXChaChaV1,
      purpose: purpose,
      scope: EnvelopeScope(
        organizationId: EnvelopeId.parse(scope['organizationId'] as String),
        vaultId: EnvelopeId.parse(scope['vaultId'] as String),
        entryId: _optionalEnvelopeId(scope['entryId']),
        grantOrRequestId: _optionalEnvelopeId(scope['grantOrRequestId']),
        agentId: _optionalEnvelopeId(scope['agentId']),
        memberId: _optionalEnvelopeId(scope['memberId']),
      ),
      resourceRevision: int.parse(resourceRevision),
      keyVersion: keyVersion,
      memberKeyGeneration: memberKeyGeneration,
      purposeData: WrappingPurposeData(
        wrappingVaultKeyVersion: wrappingVaultKeyVersion,
      ),
    );
    if (cryptoSuiteId != envelopeDescriptor.cryptoSuiteId.wireValue) {
      throw const EnvelopeException(EnvelopeErrorKind.unsupportedSuite);
    }
    final opened = await _cryptoSuites
        .resolveWire(cryptoSuiteId)
        .open(
          descriptor: envelopeDescriptor,
          rootKey: vaultKey,
          payload: EncodedSuitePayload.fromBase64Url(encodedPayload),
        );
    if (opened.length != 32) {
      opened.fillRange(0, opened.length, 0);
      throw FormatException('$label must be 32 bytes');
    }
    return opened;
  }

  Future<Uint8List> _openAead(
    VaultAadProfile profile,
    Map<String, dynamic> envelope,
    Uint8List key,
  ) async {
    final opened = await _envelopes.decrypt(
      profile: profile,
      envelope: envelope,
      key: key,
      expected: VaultEnvelopeExpectations(
        aadContext: envelope,
        minimumMemberKeyGeneration:
            envelope['memberKeyGeneration'] as int? ??
            (envelope['header']! as Map)['memberKeyGeneration']! as int,
      ),
    );
    if (opened.length != 32) {
      opened.fillRange(0, opened.length, 0);
      throw const FormatException('Vault key material must be 32 bytes');
    }
    return opened;
  }

  Future<Map<String, dynamic>> sealMemberVaultKey({
    required RotationMemberRecipient recipient,
    required String organizationId,
    required String vaultId,
    required int vkVersion,
    required int memberKeyGeneration,
    required Uint8List vaultKey,
  }) async {
    final publicKey = VaultProtocolBytes.base64UrlDecode(
      recipient.x25519PublicKey,
      maximumBytes: 32,
    );
    final expectedFingerprint = VaultProtocolBytes.base64UrlEncode(
      vaultPublicKeyFingerprint(VaultPublicKeyKind.memberX25519, publicKey),
    );
    if (expectedFingerprint != recipient.recipientKeyFingerprint) {
      throw const FormatException('Member key directory fingerprint mismatch');
    }
    final plaintext = VaultProtocolBytes.utf8Encode(
      canonicalizeVaultJson({
        'protocolVersion': 2,
        'organizationId': organizationId,
        'vaultId': vaultId,
        'memberId': recipient.memberId,
        'vkVersion': vkVersion,
        'memberKeyGeneration': memberKeyGeneration,
        'vaultKey': VaultProtocolBytes.base64UrlEncode(vaultKey),
      }),
    );
    try {
      final sealed = await _envelopes.sealPackage(
        packageBytes: plaintext,
        recipientPublicKey: publicKey,
      );
      return {
        'protocolVersion': 2,
        'algorithmSuite': 1,
        'organizationId': organizationId,
        'vaultId': vaultId,
        'memberId': recipient.memberId,
        'vkVersion': vkVersion,
        'memberKeyGeneration': memberKeyGeneration,
        'recipientMemberKeyVersion': recipient.recipientKeyVersion,
        'recipientMemberKeyFingerprint': recipient.recipientKeyFingerprint,
        'sealedVaultKeyPackage': VaultProtocolBytes.base64UrlEncode(sealed),
      };
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
      publicKey.fillRange(0, publicKey.length, 0);
    }
  }

  Future<Map<String, dynamic>> rewrapEntryKey(
    Map<String, dynamic> source,
    Uint8List currentVaultKey,
    Uint8List targetVaultKey,
    int generation,
    int vaultKeyVersion,
  ) async {
    final dek = await _envelopes.decrypt(
      profile: VaultAadProfile.entryKeyWrapper,
      envelope: source,
      key: currentVaultKey,
      expected: VaultEnvelopeExpectations(
        aadContext: source,
        minimumMemberKeyGeneration: source['memberKeyGeneration']! as int,
      ),
    );
    try {
      if (dek.length != 32) throw const FormatException('Invalid Entry DEK');
      final revision = _next(source['wrapperRevision']! as String);
      final context = <String, Object?>{
        'organizationId': source['organizationId'],
        'vaultId': source['vaultId'],
        'entryId': source['entryId'],
        'wrapperRevision': revision,
        'keyVersion': source['keyVersion'],
        'memberKeyGeneration': generation,
        'wrappingKeyVersion': vaultKeyVersion,
        'header': _header(
          2,
          8,
          revision,
          source['keyVersion']! as int,
          generation,
        ),
      };
      final encrypted = await _envelopes.encrypt(
        profile: VaultAadProfile.entryKeyWrapper,
        context: context,
        plaintext: dek,
        key: targetVaultKey,
      );
      return {
        ...context,
        'header': {...context['header']! as Map, 'nonce': encrypted['nonce']},
        'wrappedEntryDekByVk': encrypted['ciphertext'],
      };
    } finally {
      dek.fillRange(0, dek.length, 0);
    }
  }

  Future<Map<String, dynamic>> rotateProjection({
    required VaultAadProfile profile,
    required Map<String, dynamic> source,
    required Uint8List currentBaseKey,
    required Uint8List targetBaseKey,
    required int targetKeyVersion,
    required int targetGeneration,
  }) async {
    final isMetadata = profile == VaultAadProfile.memberVaultMetadata;
    final revisionField = isMetadata
        ? 'metadataRevision'
        : 'agentDiscoveryRevision';
    final purpose = isMetadata
        ? VaultKdfPurpose.memberVaultMetadata
        : VaultKdfPurpose.agentDiscovery;
    final resourceKind = isMetadata ? 1 : 2;
    final sourceHeader = Map<String, dynamic>.from(source['header']! as Map);
    final currentKey = deriveVaultProjectionKey(
      currentBaseKey,
      VaultKdfContext(
        purpose: purpose,
        resourceKind: resourceKind,
        organizationId: source['organizationId']! as String,
        vaultId: source['vaultId']! as String,
        entryId: source['entryId'] as String?,
        keyVersion: sourceHeader['keyVersion']! as int,
        memberKeyGeneration: sourceHeader['memberKeyGeneration']! as int,
      ),
    );
    Uint8List? plaintext;
    Uint8List? targetKey;
    try {
      plaintext = await _envelopes.decrypt(
        profile: profile,
        envelope: source,
        key: currentKey,
        expected: VaultEnvelopeExpectations(
          aadContext: source,
          minimumMemberKeyGeneration:
              sourceHeader['memberKeyGeneration']! as int,
        ),
      );
      targetKey = deriveVaultProjectionKey(
        targetBaseKey,
        VaultKdfContext(
          purpose: purpose,
          resourceKind: resourceKind,
          organizationId: source['organizationId']! as String,
          vaultId: source['vaultId']! as String,
          entryId: source['entryId'] as String?,
          keyVersion: targetKeyVersion,
          memberKeyGeneration: targetGeneration,
        ),
      );
      final revision = isMetadata
          ? _next(source[revisionField]! as String)
          : source[revisionField]! as String;
      final context = <String, Object?>{
        'organizationId': source['organizationId'],
        'vaultId': source['vaultId'],
        if (!isMetadata) 'entryId': source['entryId'],
        revisionField: revision,
        if (!isMetadata) 'vdkVersion': targetKeyVersion,
        'header': _header(
          resourceKind,
          isMetadata ? 1 : 4,
          revision,
          targetKeyVersion,
          targetGeneration,
        ),
      };
      final encrypted = await _envelopes.encrypt(
        profile: profile,
        context: context,
        plaintext: plaintext,
        key: targetKey,
      );
      return {
        ...context,
        'header': {...context['header']! as Map, 'nonce': encrypted['nonce']},
        'ciphertext': encrypted['ciphertext'],
      };
    } finally {
      currentKey.fillRange(0, currentKey.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
      targetKey?.fillRange(0, targetKey.length, 0);
    }
  }

  Future<Map<String, dynamic>> encryptKeyMaterial({
    required Map<String, dynamic> source,
    required VaultAadProfile profile,
    required Uint8List plaintext,
    required Uint8List targetVaultKey,
    required int targetVersion,
    required int targetGeneration,
    required int targetVaultKeyVersion,
  }) async {
    final isDiscovery = profile == VaultAadProfile.vaultDiscoveryKey;
    final revisionField = isDiscovery
        ? 'discoveryKeyRevision'
        : 'privateKeyRevision';
    final revision = _next(source[revisionField]! as String);
    final context = <String, Object?>{
      'organizationId': source['organizationId'],
      'vaultId': source['vaultId'],
      if (!isDiscovery) 'privateKeyKind': source['privateKeyKind'],
      revisionField: revision,
      if (isDiscovery)
        'vdkVersion': targetVersion
      else
        'privateKeyVersion': targetVersion,
      'memberKeyGeneration': targetGeneration,
      'wrappingKeyVersion': targetVaultKeyVersion,
      'header': _header(
        1,
        isDiscovery ? 12 : 7,
        revision,
        targetVersion,
        targetGeneration,
      ),
    };
    final encrypted = await _envelopes.encrypt(
      profile: profile,
      context: context,
      plaintext: plaintext,
      key: targetVaultKey,
    );
    return {
      ...context,
      'header': {...context['header']! as Map, 'nonce': encrypted['nonce']},
      'ciphertext': encrypted['ciphertext'],
    };
  }

  Future<Map<String, dynamic>> createAgentMaterial({
    required RotationAgentRecipient agent,
    required String organizationId,
    required String vaultId,
    required VaultKeyEpochModel epoch,
    required Uint8List vdk,
    required Uint8List messagePrivateKey,
    required Uint8List signingSeed,
    DateTime? now,
  }) async {
    final sodium = await _sodiumLoader();
    final agentX = Uint8List.fromList(base64.decode(agent.x25519PublicKey));
    final agentEd = Uint8List.fromList(base64.decode(agent.ed25519PublicKey));
    final messageSecret = SecureKey.fromList(sodium, messagePrivateKey);
    final seedSecret = SecureKey.fromList(sodium, signingSeed);
    final signingPair = sodium.crypto.sign.seedKeyPair(seedSecret);
    final signingPrivateKey = signingPair.secretKey.extractBytes();
    final messagePublic = sodium.crypto.scalarmult.base(n: messageSecret);
    final payload = VaultProtocolBytes.utf8Encode(
      canonicalizeVaultJson({
        'protocolVersion': 2,
        'organizationId': organizationId,
        'vaultId': vaultId,
        'agentId': agent.agentId,
        'vdkVersion': epoch.vdkVersion,
        'vdk': VaultProtocolBytes.base64UrlEncode(vdk),
      }),
    );
    try {
      final wrapped = await _envelopes.sealPackage(
        packageBytes: payload,
        recipientPublicKey: agentX,
      );
      final digestInput = VaultProtocolBytes.concat([
        VaultProtocolBytes.utf8Encode('PLDNV2DG:AGENT-WRAPPED-VDK:'),
        VaultProtocolBytes.u16(2),
        wrapped,
      ]);
      final digest = Uint8List.fromList(sha256.convert(digestInput).bytes);
      final revision = _next(agent.manifestRevision ?? '0');
      final unsigned = <String, Object?>{
        'protocolVersion': 2,
        'algorithmSuite': 1,
        'organizationId': organizationId,
        'vaultId': vaultId,
        'agentId': agent.agentId,
        'agentX25519Fingerprint': _fingerprint(
          VaultPublicKeyKind.agentX25519,
          agentX,
        ),
        'agentEd25519Fingerprint': _fingerprint(
          VaultPublicKeyKind.agentEd25519,
          agentEd,
        ),
        'vaultSigningPublicKey': VaultProtocolBytes.base64UrlEncode(
          signingPair.publicKey,
        ),
        'vaultSigningKeyFingerprint': _fingerprint(
          VaultPublicKeyKind.vaultSigningEd25519,
          signingPair.publicKey,
        ),
        'manifestSigningKeyVersion': epoch.manifestSigningKeyVersion,
        'vaultAgentMessagePublicKey': VaultProtocolBytes.base64UrlEncode(
          messagePublic,
        ),
        'vaultAgentMessageKeyFingerprint': _fingerprint(
          VaultPublicKeyKind.vaultMessageX25519,
          messagePublic,
        ),
        'agentMessageKeyVersion': epoch.agentMessageKeyVersion,
        'vdkVersion': epoch.vdkVersion,
        'agentWrappedVdkDigest': VaultProtocolBytes.base64UrlEncode(digest),
        'manifestRevision': revision,
        'issuedAt': _canonicalInstant(now ?? DateTime.now().toUtc()),
        'minimumAgentRuntimeProtocol': 2,
      };
      final signature = await _signatures.sign(
        domainPrefix: 'PLDNV2SIG:VAULT-MANIFEST:',
        unsignedObject: unsigned,
        privateKey: signingPrivateKey,
      );
      return {
        'agentId': agent.agentId,
        'envelope': {
          'protocolVersion': 2,
          'organizationId': organizationId,
          'vaultId': vaultId,
          'agentId': agent.agentId,
          'vdkVersion': epoch.vdkVersion,
          'algorithmSuite': 1,
          'recipientAgentKeyVersion': agent.recipientKeyVersion,
          'recipientAgentKeyFingerprint': unsigned['agentX25519Fingerprint'],
          'agentWrappedVdk': VaultProtocolBytes.base64UrlEncode(wrapped),
          'manifestRevision': revision,
          'manifestSignature': signature,
        },
        'manifest': {...unsigned, 'signature': signature},
      };
    } finally {
      messageSecret.dispose();
      seedSecret.dispose();
      signingPair.dispose();
      signingPrivateKey.fillRange(0, signingPrivateKey.length, 0);
      payload.fillRange(0, payload.length, 0);
    }
  }

  Map<String, Object?> _header(
    int resourceKind,
    int projectionKind,
    String revision,
    int keyVersion,
    int generation,
  ) => {
    'protocolVersion': 2,
    'algorithmSuite': 1,
    'resourceKind': resourceKind,
    'projectionKind': projectionKind,
    'resourceRevision': revision,
    'keyVersion': keyVersion,
    'memberKeyGeneration': generation,
    'nonce': '',
  };

  String _fingerprint(VaultPublicKeyKind kind, Uint8List key) =>
      VaultProtocolBytes.base64UrlEncode(vaultPublicKeyFingerprint(kind, key));

  String _next(String value) => (BigInt.parse(value) + BigInt.one).toString();

  String _canonicalInstant(DateTime value) {
    var result = value.toUtc().toIso8601String();
    result = result.replaceFirst(RegExp(r'0+Z$'), 'Z');
    return result.replaceFirst('.Z', 'Z');
  }
}
