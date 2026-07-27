/// Closed protocol-v2 public-key kinds from the Vault backend contract.
enum VaultPublicKeyKind {
  agentMessageX25519(4),
  manifestSigningEd25519(3);

  const VaultPublicKeyKind(this.wireValue);
  final int wireValue;
}

/// A typed Vault public key. Signing and recipient keys cannot share a kind.
final class VaultPublicKeyContractModel {
  const VaultPublicKeyContractModel({
    this.protocolVersion = 2,
    required this.schemeId,
    required this.keyKind,
    required this.keyVersion,
    required this.encodedPublicKey,
    required this.fingerprint,
  });

  final int protocolVersion;
  final String schemeId;
  final VaultPublicKeyKind keyKind;
  final int keyVersion;
  final String encodedPublicKey;
  final String fingerprint;

  Map<String, Object> toJson() => {
    'protocolVersion': protocolVersion,
    'schemeId': schemeId,
    'keyKind': keyKind.wireValue,
    'keyVersion': keyVersion,
    'encodedPublicKey': encodedPublicKey,
    'fingerprint': fingerprint,
  };
}

/// Exact wire descriptor for an X25519 sealed-box key wrapper.
final class X25519WrapperDescriptorModel {
  const X25519WrapperDescriptorModel({
    this.protocolVersion = 2,
    required this.wrapperSuiteId,
    required this.purpose,
    required this.scope,
    required this.resourceRevision,
    required this.wrappedKeyVersion,
    required this.memberKeyGeneration,
    required this.recipientKeyKind,
    required this.recipientKeyVersion,
    required this.recipientFingerprint,
    this.parentDescriptorHash,
  });

  final int protocolVersion;
  final String wrapperSuiteId;
  final int purpose;
  final Map<String, Object?> scope;
  final String resourceRevision;
  final int wrappedKeyVersion;
  final int? memberKeyGeneration;
  final int recipientKeyKind;
  final int recipientKeyVersion;
  final String recipientFingerprint;
  final String? parentDescriptorHash;

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'wrapperSuiteId': wrapperSuiteId,
    'purpose': purpose,
    'scope': scope,
    'resourceRevision': resourceRevision,
    'wrappedKeyVersion': wrappedKeyVersion,
    'memberKeyGeneration': memberKeyGeneration,
    'recipientKeyKind': recipientKeyKind,
    'recipientKeyVersion': recipientKeyVersion,
    'recipientFingerprint': recipientFingerprint,
    'parentDescriptorHash': parentDescriptorHash,
  };
}

/// Exact backend `X25519WrappedKeyContract` shape.
final class X25519WrappedKeyModel {
  const X25519WrappedKeyModel({
    required this.descriptor,
    required this.encodedSealedKeyPackage,
  });
  final X25519WrapperDescriptorModel descriptor;
  final String encodedSealedKeyPackage;
  Map<String, Object> toJson() => {
    'descriptor': descriptor.toJson(),
    'encodedSealedKeyPackage': encodedSealedKeyPackage,
  };
}

/// Structural versions switched together by an atomic Vault transition.
final class VaultKeyEpochModel {
  const VaultKeyEpochModel({
    required this.vaultKeyVersion,
    required this.vdkVersion,
    required this.agentMessageKeyVersion,
    required this.manifestSigningKeyVersion,
  });
  final int vaultKeyVersion;
  final int vdkVersion;
  final int agentMessageKeyVersion;
  final int manifestSigningKeyVersion;
  Map<String, Object> toJson() => {
    'vaultKeyVersion': vaultKeyVersion,
    'vdkVersion': vdkVersion,
    'agentMessageKeyVersion': agentMessageKeyVersion,
    'manifestSigningKeyVersion': manifestSigningKeyVersion,
  };
}

/// Opaque symmetric envelope with its authenticated typed descriptor.
final class VaultOpaqueEnvelopeModel {
  const VaultOpaqueEnvelopeModel({
    required this.descriptor,
    required this.encodedSuitePayload,
  });
  final Map<String, Object?> descriptor;
  final String encodedSuitePayload;
  Map<String, Object> toJson() => {
    'descriptor': descriptor,
    'encodedSuitePayload': encodedSuitePayload,
  };
}

/// Atomic protocol-v2 Vault creation request. It has no legacy metadata fields.
final class CreateVaultV2Request {
  const CreateVaultV2Request({
    required this.vaultId,
    required this.memberVaultMetadata,
    required this.currentKeyEpoch,
    required this.creatorVaultKey,
    required this.discoveryKey,
    required this.vaultPrivateKeys,
    required this.vaultAgentMessagePublicKey,
    required this.vaultManifestSigningPublicKey,
  });
  final String vaultId;
  final VaultOpaqueEnvelopeModel memberVaultMetadata;
  final VaultKeyEpochModel currentKeyEpoch;
  final X25519WrappedKeyModel creatorVaultKey;
  final VaultOpaqueEnvelopeModel discoveryKey;
  final List<VaultOpaqueEnvelopeModel> vaultPrivateKeys;
  final VaultPublicKeyContractModel vaultAgentMessagePublicKey;
  final VaultPublicKeyContractModel vaultManifestSigningPublicKey;

  Map<String, Object> toJson() => {
    'vaultId': vaultId,
    'memberVaultMetadata': memberVaultMetadata.toJson(),
    'currentKeyEpoch': currentKeyEpoch.toJson(),
    'creatorVaultKey': {'wrappedVaultKey': creatorVaultKey.toJson()},
    'discoveryKey': discoveryKey.toJson(),
    'vaultPrivateKeys': vaultPrivateKeys
        .map((value) => value.toJson())
        .toList(),
    'vaultAgentMessagePublicKey': vaultAgentMessagePublicKey.toJson(),
    'vaultManifestSigningPublicKey': vaultManifestSigningPublicKey.toJson(),
  };
}
