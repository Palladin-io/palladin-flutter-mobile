import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/jwt_claims.dart';
import '../../../unlock/data/datasources/account_remote_datasource.dart';
import '../../domain/entities/vault_entity.dart';
import '../datasources/vault_remote_datasource.dart';
import '../models/vault_rotation_models.dart';
import 'vault_protocol/vault_protocol_aad.dart';
import 'vault_protocol/vault_protocol_bytes.dart';
import 'vault_protocol/vault_protocol_envelope_service.dart';
import 'vault_protocol/vault_protocol_fingerprint.dart';
import 'vault_protocol/vault_protocol_kdf.dart';
import 'vault_protocol/vault_protocol_signature_service.dart';
import 'vault_rotation_crypto_service.dart';

final class _PendingVaultCreation {
  _PendingVaultCreation({required this.payload, required this.display});
  final Map<String, dynamic> payload;
  final VaultEntity display;
}

/// Builds one complete Vault v2 creation transaction entirely on-device.
abstract interface class VaultCreator {
  Future<VaultEntity> create({
    required String name,
    String? description,
    String? icon,
    String? color,
    required Uint8List memberPrivateKey,
  });
}

class VaultCreationService implements VaultCreator {
  VaultCreationService({
    required VaultRemoteDatasource remote,
    required AccountRemoteDatasource accountRemote,
    required SecureTokenStorage tokenStorage,
    required VaultRotationCryptoService crypto,
    required VaultProtocolEnvelopeService envelopes,
    Future<SodiumSumo> Function()? sodiumLoader,
  }) : _remote = remote,
       _accountRemote = accountRemote,
       _tokenStorage = tokenStorage,
       _crypto = crypto,
       _envelopes = envelopes,
       _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final VaultRemoteDatasource _remote;
  final AccountRemoteDatasource _accountRemote;
  final SecureTokenStorage _tokenStorage;
  final VaultRotationCryptoService _crypto;
  final VaultProtocolEnvelopeService _envelopes;
  final Future<SodiumSumo> Function() _sodiumLoader;
  _PendingVaultCreation? _pending;

  /// Retries reuse the exact challenge-bound ciphertext payload.
  @override
  Future<VaultEntity> create({
    required String name,
    String? description,
    String? icon,
    String? color,
    required Uint8List memberPrivateKey,
  }) async {
    _pending ??= await _prepare(
      name: name,
      description: description,
      icon: icon,
      color: color,
      memberPrivateKey: memberPrivateKey,
    );
    final pending = _pending!;
    final response = await _remote.createEncryptedVault(pending.payload);
    final result = VaultEntity(
      id: response['id'] as String,
      name: pending.display.name,
      description: pending.display.description,
      icon: pending.display.icon,
      color: pending.display.color,
      grantMode: GrantMode.granular,
      createdAt: DateTime.parse(response['createdAt'] as String),
      updatedAt: DateTime.parse(response['updatedAt'] as String),
      entryCount: 0,
      activeGrantCount: 0,
      memberCount: 1,
    );
    _pending = null;
    return result;
  }

  Future<_PendingVaultCreation> _prepare({
    required String name,
    String? description,
    String? icon,
    String? color,
    required Uint8List memberPrivateKey,
  }) async {
    if (memberPrivateKey.length != 32 || name.isEmpty) {
      throw const FormatException('Invalid Vault creation input');
    }
    final token = await _tokenStorage.accessToken;
    final organizationId = token == null
        ? null
        : JwtClaims.organizationIdFrom(token);
    final account = await _accountRemote.getAccount();
    final memberKeyVersion = account.memberKeyVersion;
    if (organizationId == null ||
        memberKeyVersion == null ||
        memberKeyVersion < 1) {
      throw const FormatException('Missing current Member key context');
    }
    final challenge = await _remote.issueVaultCreationChallenge();
    final vaultId = challenge['vaultId'] as String;
    final keys = await _crypto.generateKeys();
    Uint8List? memberPublicKey;
    Uint8List? metadataBytes;
    Uint8List? metadataKey;
    try {
      final sodium = await _sodiumLoader();
      final secret = SecureKey.fromList(sodium, memberPrivateKey);
      try {
        memberPublicKey = sodium.crypto.scalarmult.base(n: secret);
      } finally {
        secret.dispose();
      }
      metadataBytes = VaultProtocolBytes.utf8Encode(
        canonicalizeVaultJson({
          'name': name,
          'description': ?description,
          'iconReference': ?icon,
          'color': ?color,
        }),
      );
      metadataKey = deriveVaultProjectionKey(
        keys.vaultKey,
        VaultKdfContext(
          purpose: VaultKdfPurpose.memberVaultMetadata,
          resourceKind: 1,
          organizationId: organizationId,
          vaultId: vaultId,
          keyVersion: 1,
          memberKeyGeneration: 1,
        ),
      );
      final metadataContext = <String, Object?>{
        'organizationId': organizationId,
        'vaultId': vaultId,
        'metadataRevision': '1',
        'header': _header(1, 1, '1'),
      };
      final encryptedMetadata = await _envelopes.encrypt(
        profile: VaultAadProfile.memberVaultMetadata,
        context: metadataContext,
        plaintext: metadataBytes,
        key: metadataKey,
      );
      final recipient = RotationMemberRecipient(
        memberId: account.userId,
        recipientKeyVersion: memberKeyVersion,
        recipientKeyFingerprint: VaultProtocolBytes.base64UrlEncode(
          vaultPublicKeyFingerprint(
            VaultPublicKeyKind.memberX25519,
            memberPublicKey,
          ),
        ),
        x25519PublicKey: VaultProtocolBytes.base64UrlEncode(memberPublicKey),
      );
      final creatorKey = await _crypto.sealMemberVaultKey(
        recipient: recipient,
        organizationId: organizationId,
        vaultId: vaultId,
        vkVersion: 1,
        memberKeyGeneration: 1,
        vaultKey: keys.vaultKey,
      );
      final discovery = await _crypto.encryptKeyMaterial(
        source: {
          'organizationId': organizationId,
          'vaultId': vaultId,
          'discoveryKeyRevision': '0',
        },
        profile: VaultAadProfile.vaultDiscoveryKey,
        plaintext: keys.vdk,
        targetVaultKey: keys.vaultKey,
        targetVersion: 1,
        targetGeneration: 1,
        targetVaultKeyVersion: 1,
      );
      final privateKeys = <Map<String, dynamic>>[];
      for (final pair in [
        (1, keys.agentMessagePrivateKey),
        (2, keys.manifestSigningSeed),
      ]) {
        privateKeys.add(
          await _crypto.encryptKeyMaterial(
            source: {
              'organizationId': organizationId,
              'vaultId': vaultId,
              'privateKeyKind': pair.$1,
              'privateKeyRevision': '0',
            },
            profile: VaultAadProfile.vaultPrivateKey,
            plaintext: pair.$2,
            targetVaultKey: keys.vaultKey,
            targetVersion: 1,
            targetGeneration: 1,
            targetVaultKeyVersion: 1,
          ),
        );
      }
      return _PendingVaultCreation(
        payload: {
          'vaultId': vaultId,
          'memberVaultMetadata': {
            ...metadataContext,
            'header': {
              ...metadataContext['header']! as Map,
              'nonce': encryptedMetadata['nonce'],
            },
            'ciphertext': encryptedMetadata['ciphertext'],
          },
          'currentKeyEpoch': {
            'vaultKeyVersion': 1,
            'vdkVersion': 1,
            'agentMessageKeyVersion': 1,
            'manifestSigningKeyVersion': 1,
          },
          'creatorVaultKey': creatorKey,
          'discoveryKey': discovery,
          'vaultPrivateKeys': privateKeys,
        },
        display: VaultEntity(
          id: vaultId,
          name: name,
          description: description,
          icon: icon,
          color: color,
          grantMode: GrantMode.granular,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          entryCount: 0,
          activeGrantCount: 0,
          memberCount: 1,
        ),
      );
    } finally {
      keys.dispose();
      memberPublicKey?.fillRange(0, memberPublicKey.length, 0);
      metadataBytes?.fillRange(0, metadataBytes.length, 0);
      metadataKey?.fillRange(0, metadataKey.length, 0);
    }
  }

  Map<String, Object?> _header(
    int resourceKind,
    int projectionKind,
    String revision,
  ) => {
    'protocolVersion': 2,
    'algorithmSuite': 1,
    'resourceKind': resourceKind,
    'projectionKind': projectionKind,
    'resourceRevision': revision,
    'keyVersion': 1,
    'memberKeyGeneration': 1,
    'nonce': '',
  };
}
