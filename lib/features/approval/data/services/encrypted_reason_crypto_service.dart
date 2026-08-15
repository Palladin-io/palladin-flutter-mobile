import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/envelope/envelope_contract.dart';
import '../../../../core/crypto/envelope/envelope_suite.dart';
import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/crypto/x25519_key_wrapper.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_fingerprint.dart';
import '../../domain/entities/encrypted_reason.dart';

abstract interface class EncryptedReasonCrypto {
  Future<Uint8List> verifyAndOpenKey({
    required EncryptedReason reason,
    required Uint8List signingPublicKey,
    required Uint8List recipientPrivateKey,
  });

  Future<Uint8List> decrypt({
    required EncryptedReason reason,
    required Uint8List reasonKey,
  });
}

final class EncryptedReasonCryptoService implements EncryptedReasonCrypto {
  EncryptedReasonCryptoService({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  @override
  Future<Uint8List> verifyAndOpenKey({
    required EncryptedReason reason,
    required Uint8List signingPublicKey,
    required Uint8List recipientPrivateKey,
  }) async {
    final descriptor = _descriptor(reason);
    final wrappedJson = reason.wrappedReasonDek;
    final wrapped = VaultProtocolBytes.base64UrlDecode(
      wrappedJson['encodedSealedKeyPackage'] as String,
      maximumBytes: X25519SealedBoxKeyWrapper.encodedBytes,
    );
    final wrapper = _wrapper(reason, descriptor);
    final signature = VaultProtocolBytes.base64UrlDecode(
      reason.agentSignature,
      maximumBytes: 64,
    );
    final transcript = signatureTranscript(reason);
    try {
      if (signingPublicKey.length != 32 || signature.length != 64) {
        throw const FormatException('Invalid encrypted reason signature');
      }
      final sodium = await _sodiumLoader();
      if (!sodium.crypto.sign.verifyDetached(
        message: transcript,
        signature: signature,
        publicKey: signingPublicKey,
      )) {
        throw const FormatException('Encrypted reason signature mismatch');
      }
      return await X25519SealedBoxKeyWrapper(sodiumLoader: _sodiumLoader).open(
        wrapped: wrapped,
        context: wrapper,
        recipientSecretKey: recipientPrivateKey,
      );
    } finally {
      wrapped.fillRange(0, wrapped.length, 0);
      signature.fillRange(0, signature.length, 0);
      transcript.fillRange(0, transcript.length, 0);
    }
  }

  /// Canonical transcript shared with the backend and Rust CLI.
  Uint8List signatureTranscript(EncryptedReason reason) {
    final descriptorBytes = _descriptor(reason).encodeAad();
    final payloadBytes = EncodedSuitePayload.fromBase64Url(
      reason.encodedSuitePayload,
    ).bytes;
    final wrapped = VaultProtocolBytes.base64UrlDecode(
      reason.wrappedReasonDek['encodedSealedKeyPackage'] as String,
      maximumBytes: X25519SealedBoxKeyWrapper.encodedBytes,
    );
    final suite = VaultProtocolBytes.utf8Encode(
      RecipientWrapperSuiteId.x25519SealedBoxV1.wireValue,
    );
    try {
      return VaultProtocolBytes.concat([
        VaultProtocolBytes.utf8Encode('PLDNV2SIG:ENCRYPTED-REASON:'),
        VaultProtocolBytes.u16(2),
        descriptorBytes,
        payloadBytes,
        VaultProtocolBytes.u16(suite.length),
        suite,
        wrapped,
      ]);
    } finally {
      descriptorBytes.fillRange(0, descriptorBytes.length, 0);
      payloadBytes.fillRange(0, payloadBytes.length, 0);
      wrapped.fillRange(0, wrapped.length, 0);
      suite.fillRange(0, suite.length, 0);
    }
  }

  @override
  Future<Uint8List> decrypt({
    required EncryptedReason reason,
    required Uint8List reasonKey,
  }) => XChaChaVaultEnvelopeSuite(sodiumLoader: _sodiumLoader).open(
    descriptor: _descriptor(reason),
    rootKey: reasonKey,
    payload: EncodedSuitePayload.fromBase64Url(reason.encodedSuitePayload),
  );

  EnvelopeDescriptor _descriptor(EncryptedReason reason) {
    final json = reason.descriptor;
    final scope = reason.scope;
    final binding = reason.binding;
    if (json['cryptoSuiteId'] !=
            CryptoSuiteId.palladinVaultXChaChaV1.wireValue ||
        binding['wrapperSuiteId'] !=
            RecipientWrapperSuiteId.x25519SealedBoxV1.wireValue ||
        scope['memberId'] != null) {
      throw const FormatException('Invalid encrypted reason descriptor');
    }
    return EnvelopeDescriptor(
      protocolVersion: json['protocolVersion'] as int,
      purpose: EnvelopePurpose.parseWire(json['purpose']),
      scope: EnvelopeScope(
        organizationId: EnvelopeId.parse(scope['organizationId'] as String),
        vaultId: EnvelopeId.parse(scope['vaultId'] as String),
        entryId: EnvelopeId.parse(scope['entryId'] as String),
        grantOrRequestId: EnvelopeId.parse(scope['grantOrRequestId'] as String),
        agentId: EnvelopeId.parse(scope['agentId'] as String),
      ),
      resourceRevision: int.parse(json['resourceRevision'] as String),
      keyVersion: json['keyVersion'] as int,
      memberKeyGeneration: json['memberKeyGeneration'] as int,
      purposeData: ReasonPurposeData(
        agentMessageKeyVersion: binding['recipientKeyVersion'] as int,
        recipientFingerprint: VaultProtocolBytes.base64UrlDecode(
          binding['recipientKeyFingerprint'] as String,
          maximumBytes: 32,
        ),
        methods: binding['requestedMethods'] as int,
      ),
    );
  }

  WrapperContext _wrapper(EncryptedReason reason, EnvelopeDescriptor parent) {
    final json = Map<String, dynamic>.from(
      reason.wrappedReasonDek['descriptor'] as Map,
    );
    final scope = Map<String, dynamic>.from(json['scope'] as Map);
    final parentScope = reason.scope;
    final binding = reason.binding;
    final recipientKeyKind = VaultPublicKeyKind.parseWire(
      json['recipientKeyKind'],
    );
    if (json['wrapperSuiteId'] !=
            RecipientWrapperSuiteId.x25519SealedBoxV1.wireValue ||
        WrapperPurpose.parseWire(json['purpose']) != WrapperPurpose.reasonDek ||
        scope['organizationId'] != parentScope['organizationId'] ||
        scope['vaultId'] != parentScope['vaultId'] ||
        scope['entryId'] != parentScope['entryId'] ||
        scope['grantOrRequestId'] != parentScope['grantOrRequestId'] ||
        scope['agentId'] != parentScope['agentId'] ||
        scope['memberId'] != null ||
        recipientKeyKind != VaultPublicKeyKind.vaultMessageX25519 ||
        json['recipientKeyVersion'] != binding['recipientKeyVersion'] ||
        json['recipientFingerprint'] != binding['recipientKeyFingerprint']) {
      throw const FormatException('Invalid encrypted reason wrapper profile');
    }
    final wrapper = WrapperContext(
      protocolVersion: json['protocolVersion'] as int,
      purpose: WrapperPurpose.parseWire(json['purpose']),
      scope: EnvelopeScope(
        organizationId: EnvelopeId.parse(scope['organizationId'] as String),
        vaultId: EnvelopeId.parse(scope['vaultId'] as String),
        entryId: EnvelopeId.parse(scope['entryId'] as String),
        grantOrRequestId: EnvelopeId.parse(scope['grantOrRequestId'] as String),
        agentId: EnvelopeId.parse(scope['agentId'] as String),
      ),
      resourceRevision: int.parse(json['resourceRevision'] as String),
      wrappedKeyVersion: json['wrappedKeyVersion'] as int,
      memberKeyGeneration: json['memberKeyGeneration'] as int,
      recipientKeyKind: recipientKeyKind.id,
      recipientKeyVersion: json['recipientKeyVersion'] as int,
      recipientFingerprint: VaultProtocolBytes.base64UrlDecode(
        json['recipientFingerprint'] as String,
        maximumBytes: 32,
      ),
      parentDescriptorHash: VaultProtocolBytes.base64UrlDecode(
        json['parentDescriptorHash'] as String,
        maximumBytes: 32,
      ),
    );
    final expectedParent = WrapperContext.hashParent(parent);
    if (!VaultProtocolBytes.constantTimeEquals(
          wrapper.parentDescriptorHash!,
          expectedParent,
        ) ||
        wrapper.resourceRevision != parent.resourceRevision ||
        wrapper.wrappedKeyVersion != parent.keyVersion ||
        wrapper.memberKeyGeneration != parent.memberKeyGeneration) {
      throw const FormatException('Encrypted reason wrapper mismatch');
    }
    return wrapper;
  }
}
