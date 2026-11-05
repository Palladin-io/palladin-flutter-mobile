import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../../../core/crypto/envelope/envelope_contract.dart';
import '../../../../core/crypto/envelope/envelope_suite.dart';
import '../../../../core/crypto/kem/xwing.dart';
import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/crypto/recipient_key_wrapper.dart';
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
    this._memberKeySuite = WrapperSuite.memberKeySuite,
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

  /// Suite of the unlocked member key; the security-upgrade flow passes the
  /// legacy suite only to open envelopes addressed to the old key.
  final WrapperSuite _memberKeySuite;
  final Future<SodiumSumo> Function() _sodiumLoader;

  Future<Map<String, Map<String, Object>>> createPublicTrustAnchors({
    required Uint8List agentMessagePrivateKey,
    required WrapperSuite agentMessageKeySuite,
    required Uint8List manifestSigningPrivateKey,
    required int agentMessageKeyVersion,
    required int manifestSigningKeyVersion,
  }) async {
    if (agentMessageKeyVersion <= 0 || manifestSigningKeyVersion <= 0) {
      throw const FormatException('Invalid Vault public-key version');
    }
    final sodium = await _sodiumLoader();
    final signing = _normalizeSigningKey(sodium, manifestSigningPrivateKey);
    Uint8List? messagePublic;
    try {
      messagePublic = agentMessagePublicKey(
        sodium,
        agentMessageKeySuite,
        agentMessagePrivateKey,
      );
      return {
        'agentMessage': {
          'protocolVersion': 2,
          'schemeId': agentMessageKeySuite.wireValue,
          'keyKind': 1,
          'keyVersion': agentMessageKeyVersion,
          'encodedPublicKey': VaultProtocolBytes.base64UrlEncode(messagePublic),
          'fingerprint': VaultProtocolBytes.base64UrlEncode(
            recipientFingerprint(
              agentMessageKeySuite,
              RecipientKeyKind.vaultAgentMessage.id,
              messagePublic,
            ),
          ),
        },
        'manifestSigning': {
          'protocolVersion': 2,
          'schemeId': 'palladin-ed25519-v1',
          'keyKind': 2,
          'keyVersion': manifestSigningKeyVersion,
          'encodedPublicKey': VaultProtocolBytes.base64UrlEncode(
            signing.publicKey,
          ),
          'fingerprint': _fingerprint(
            VaultPublicKeyKind.vaultSigning,
            signing.publicKey,
          ),
        },
      };
    } finally {
      messagePublic?.fillRange(0, messagePublic.length, 0);
      signing.publicKey.fillRange(0, signing.publicKey.length, 0);
      signing.privateKey.fillRange(0, signing.privateKey.length, 0);
    }
  }

  /// Suite of the Vault Agent message key [keyVersion] from the encrypted
  /// Vault response: its top-level `vaultAgentMessageKeySuiteId` names the
  /// current key's suite; any earlier key version predates the migration
  /// and is legacy.
  static WrapperSuite agentMessageKeySuite(
    Map<String, dynamic> vault,
    int keyVersion,
  ) {
    final current = vault['vaultAgentMessagePublicKey'];
    if (current is! Map || current['keyVersion'] is! int) {
      throw const FormatException('Vault Agent message key is missing');
    }
    if (current['keyVersion'] != keyVersion) {
      return WrapperSuite.x25519SealedBoxV1;
    }
    return WrapperSuite.tryParse(vault['vaultAgentMessageKeySuiteId']) ??
        (throw const FormatException('Unknown Vault Agent message key suite'));
  }

  /// Public half of a Vault Agent message key under its published suite.
  static Uint8List agentMessagePublicKey(
    SodiumSumo sodium,
    WrapperSuite suite,
    Uint8List privateKey,
  ) {
    if (privateKey.length != 32) {
      throw const FormatException('Vault Agent message key length');
    }
    return switch (suite) {
      WrapperSuite.xwingV1 => XWing(sodium).publicKeyFromSeed(privateKey),
      WrapperSuite.x25519SealedBoxV1 => () {
        final secret = SecureKey.fromList(sodium, privateKey);
        try {
          return Uint8List.fromList(sodium.crypto.scalarmult.base(n: secret));
        } finally {
          secret.dispose();
        }
      }(),
    };
  }

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

  /// A rotated Vault Agent message key is always created on the active
  /// suite; its private key is the 32-byte X-Wing seed.
  Future<VaultRotationKeys> generateKeys() async {
    final sodium = await _sodiumLoader();
    return VaultRotationKeys(
      vaultKey: sodium.randombytes.buf(32),
      vdk: sodium.randombytes.buf(32),
      agentMessagePrivateKey: XWing(sodium).generateSeed(),
      manifestSigningSeed: sodium.randombytes.buf(32),
    );
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
    if (!recipient.keySuite.canSeal) throw const KeyMigrationPendingException();
    final publicKey = VaultProtocolBytes.base64UrlDecode(
      recipient.publicKey,
      maximumBytes: recipient.keySuite.publicKeyBytes,
    );
    _requireDirectoryFingerprint(
      recipient.keySuite,
      RecipientKeyKind.agentEncryption,
      publicKey,
      recipient.recipientKeyFingerprint,
    );
    final sodium = await _sodiumLoader();
    final signing = _normalizeSigningKey(sodium, vaultSigningPrivateKey);
    final signingFingerprint = vaultPublicKeyFingerprint(
      VaultPublicKeyKind.vaultSigning,
      signing.publicKey,
    );
    try {
      return await buildAgentWrappedVaultKeyContract(
        vaultKey: vaultKey,
        organizationId: organizationId,
        vaultId: vaultId,
        grantId: recipient.grantId,
        agentId: recipient.agentId,
        agentAccessEpoch: recipient.agentAccessEpoch,
        vaultKeyVersion: vaultKeyVersion,
        agentPublicKey: publicKey,
        agentKeySuite: recipient.keySuite,
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
    Uint8List memberPrivateKey, {
    String? expectedOrganizationId,
    String? expectedVaultId,
    int? expectedVaultKeyVersion,
    int? expectedMemberKeyGeneration,
  }) async {
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
        descriptor['wrapperSuiteId'] != _memberKeySuite.wireValue) {
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
    if ((expectedOrganizationId != null &&
            organizationId != expectedOrganizationId) ||
        (expectedVaultId != null && vaultId != expectedVaultId) ||
        (expectedVaultKeyVersion != null &&
            wrappedKeyVersion != expectedVaultKeyVersion) ||
        (expectedMemberKeyGeneration != null &&
            memberKeyGeneration != expectedMemberKeyGeneration)) {
      throw const EnvelopeException(EnvelopeErrorKind.invalidDescriptor);
    }

    final parsedRecipientKeyKind = VaultPublicKeyKind.parseWire(
      recipientKeyKind,
    );
    if (parsedRecipientKeyKind != VaultPublicKeyKind.memberEncryption) {
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
        suiteId: _memberKeySuite,
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
      return await RecipientKeyWrapper(sodiumLoader: _sodiumLoader).open(
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
    if (expectedPurpose == EnvelopePurpose.manifestPrivateByVk &&
        opened.length == 64) {
      // Clients store libsodium's 64-byte Ed25519 secret key (seed || public
      // key); hand out the seed only after the embedded public key checks.
      try {
        final sodium = await _sodiumLoader();
        final seed = Uint8List.fromList(opened.sublist(0, 32));
        final normalized = _normalizeSigningKey(sodium, seed);
        final matches = VaultProtocolBytes.constantTimeEquals(
          normalized.publicKey,
          Uint8List.sublistView(opened, 32),
        );
        normalized.publicKey.fillRange(0, 32, 0);
        normalized.privateKey.fillRange(0, normalized.privateKey.length, 0);
        if (!matches) {
          seed.fillRange(0, seed.length, 0);
          throw FormatException('$label does not match its public key');
        }
        return seed;
      } finally {
        opened.fillRange(0, opened.length, 0);
      }
    }
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

  /// Seals the target VK to one member with the suite of that member's key
  /// directory entry; a member still on a read-only suite fails with
  /// [KeyMigrationPendingException].
  Future<Map<String, dynamic>> sealMemberVaultKey({
    required RotationMemberRecipient recipient,
    required String organizationId,
    required String vaultId,
    required int vkVersion,
    required int memberKeyGeneration,
    required Uint8List vaultKey,
  }) async {
    if (!recipient.keySuite.canSeal) throw const KeyMigrationPendingException();
    final publicKey = VaultProtocolBytes.base64UrlDecode(
      recipient.publicKey,
      maximumBytes: recipient.keySuite.publicKeyBytes,
    );
    try {
      final fingerprint = _requireDirectoryFingerprint(
        recipient.keySuite,
        RecipientKeyKind.memberEncryption,
        publicKey,
        recipient.recipientKeyFingerprint,
      );
      final context = WrapperContext(
        suiteId: recipient.keySuite,
        purpose: WrapperPurpose.memberVaultKey,
        scope: EnvelopeScope(
          organizationId: EnvelopeId.parse(organizationId),
          vaultId: EnvelopeId.parse(vaultId),
          memberId: EnvelopeId.parse(recipient.memberId),
        ),
        resourceRevision: vkVersion,
        wrappedKeyVersion: vkVersion,
        memberKeyGeneration: memberKeyGeneration,
        recipientKeyKind: RecipientKeyKind.memberEncryption.id,
        recipientKeyVersion: recipient.recipientKeyVersion,
        recipientFingerprint: fingerprint,
      );
      final sealed = await RecipientKeyWrapper(sodiumLoader: _sodiumLoader)
          .seal(
            key: vaultKey,
            context: context,
            recipient: RecipientPublicKey(
              suite: recipient.keySuite,
              keyKind: RecipientKeyKind.memberEncryption,
              keyVersion: recipient.recipientKeyVersion,
              publicKey: publicKey,
            ),
          );
      return {'wrappedVaultKey': context.wrappedKeyJson(sealed)};
    } finally {
      publicKey.fillRange(0, publicKey.length, 0);
    }
  }

  /// The directory fingerprint is checked against the suite-bound fingerprint
  /// of the directory's own public key before anything is sealed to it.
  Uint8List _requireDirectoryFingerprint(
    WrapperSuite suite,
    RecipientKeyKind kind,
    Uint8List publicKey,
    String directoryFingerprint,
  ) {
    final Uint8List fingerprint;
    try {
      fingerprint = recipientFingerprint(suite, kind.id, publicKey);
    } on KeyWrapperException {
      throw const FormatException('Recipient key does not match its suite');
    }
    if (VaultProtocolBytes.base64UrlEncode(fingerprint) !=
        directoryFingerprint) {
      throw const FormatException('Key directory fingerprint mismatch');
    }
    return fingerprint;
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

  /// Discovery provisioning for one Agent: the VDK sealed with the suite of
  /// the Agent's published encryption key, and a signed manifest that names
  /// the Vault Agent message key suite whenever that key is not legacy.
  /// An Agent still on a read-only suite fails with
  /// [KeyMigrationPendingException].
  Future<Map<String, dynamic>> createAgentMaterial({
    required RotationAgentRecipient agent,
    required String organizationId,
    required String vaultId,
    required VaultKeyEpochModel epoch,
    required Uint8List vdk,
    required Uint8List messagePrivateKey,
    required WrapperSuite messageKeySuite,
    required Uint8List signingSeed,
    DateTime? now,
  }) async {
    if (!agent.keySuite.canSeal) throw const KeyMigrationPendingException();
    final sodium = await _sodiumLoader();
    final agentPublicKey = Uint8List.fromList(base64.decode(agent.publicKey));
    final agentEd = Uint8List.fromList(base64.decode(agent.ed25519PublicKey));
    final seedSecret = SecureKey.fromList(sodium, signingSeed);
    final signingPair = sodium.crypto.sign.seedKeyPair(seedSecret);
    final signingPrivateKey = signingPair.secretKey.extractBytes();
    final messagePublic = agentMessagePublicKey(
      sodium,
      messageKeySuite,
      messagePrivateKey,
    );
    try {
      final Uint8List agentFingerprint;
      try {
        agentFingerprint = recipientFingerprint(
          agent.keySuite,
          RecipientKeyKind.agentEncryption.id,
          agentPublicKey,
        );
      } on KeyWrapperException {
        throw const FormatException('Agent key does not match its suite');
      }
      final context = WrapperContext(
        suiteId: agent.keySuite,
        purpose: WrapperPurpose.agentVdk,
        scope: EnvelopeScope(
          organizationId: EnvelopeId.parse(organizationId),
          vaultId: EnvelopeId.parse(vaultId),
          agentId: EnvelopeId.parse(agent.agentId),
        ),
        resourceRevision: epoch.vdkVersion,
        wrappedKeyVersion: epoch.vdkVersion,
        recipientKeyKind: RecipientKeyKind.agentEncryption.id,
        recipientKeyVersion: agent.recipientKeyVersion,
        recipientFingerprint: agentFingerprint,
      );
      final wrapped = await RecipientKeyWrapper(sodiumLoader: _sodiumLoader)
          .seal(
            key: vdk,
            context: context,
            recipient: RecipientPublicKey(
              suite: agent.keySuite,
              keyKind: RecipientKeyKind.agentEncryption,
              keyVersion: agent.recipientKeyVersion,
              publicKey: agentPublicKey,
            ),
          );
      final digest = Uint8List.fromList(
        sha256
            .convert(
              VaultProtocolBytes.concat([
                VaultProtocolBytes.utf8Encode('PLDNV2DG:AGENT-WRAPPED-VDK:'),
                VaultProtocolBytes.u16(2),
                wrapped,
              ]),
            )
            .bytes,
      );
      final revision = _next(agent.manifestRevision ?? '0');
      final unsigned = <String, Object?>{
        'protocolVersion': 2,
        'cryptoSuiteId': CryptoSuiteId.palladinVaultXChaChaV1.wireValue,
        'wrapperSuiteId': agent.keySuite.wireValue,
        'signatureSuiteId': 'palladin-ed25519-v1',
        'organizationId': organizationId,
        'vaultId': vaultId,
        'agentId': agent.agentId,
        'agentX25519Fingerprint': VaultProtocolBytes.base64UrlEncode(
          agentFingerprint,
        ),
        'agentEd25519Fingerprint': _fingerprint(
          VaultPublicKeyKind.agentSigning,
          agentEd,
        ),
        'vaultSigningPublicKey': VaultProtocolBytes.base64UrlEncode(
          signingPair.publicKey,
        ),
        'vaultSigningKeyFingerprint': _fingerprint(
          VaultPublicKeyKind.vaultSigning,
          signingPair.publicKey,
        ),
        'manifestSigningKeyVersion': epoch.manifestSigningKeyVersion,
        'vaultAgentMessagePublicKey': VaultProtocolBytes.base64UrlEncode(
          messagePublic,
        ),
        'vaultAgentMessageKeyFingerprint': VaultProtocolBytes.base64UrlEncode(
          recipientFingerprint(
            messageKeySuite,
            RecipientKeyKind.vaultAgentMessage.id,
            messagePublic,
          ),
        ),
        if (messageKeySuite != WrapperSuite.x25519SealedBoxV1)
          'vaultAgentMessageKeySuiteId': messageKeySuite.wireValue,
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
          'wrappedVdk': context.wrappedKeyJson(wrapped),
          'manifestRevision': revision,
          'manifestSignature': signature,
        },
        'manifest': {...unsigned, 'signature': signature},
      };
    } finally {
      seedSecret.dispose();
      signingPair.dispose();
      signingPrivateKey.fillRange(0, signingPrivateKey.length, 0);
      messagePublic.fillRange(0, messagePublic.length, 0);
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
