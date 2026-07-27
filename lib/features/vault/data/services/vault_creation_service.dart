import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/jwt_claims.dart';
import '../../../unlock/data/datasources/account_remote_datasource.dart';
import '../../domain/entities/vault_entity.dart';
import '../datasources/vault_remote_datasource.dart';
import 'vault_protocol/vault_protocol_bytes.dart';
import 'vault_protocol/vault_protocol_fingerprint.dart';
import 'vault_crypto_service.dart';

final class _PendingVaultCreation {
  _PendingVaultCreation({
    required this.payload,
    required this.display,
    required this.memberPublicKeyFingerprint,
  });
  final Map<String, dynamic> payload;
  final VaultEntity display;
  final String memberPublicKeyFingerprint;

  bool matchesDisplay({
    required String name,
    String? description,
    String? icon,
    String? color,
  }) =>
      display.name == name &&
      display.description == description &&
      display.icon == icon &&
      display.color == color;
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
    required VaultCryptoService crypto,
    Future<SodiumSumo> Function()? sodiumLoader,
  }) : _remote = remote,
       _accountRemote = accountRemote,
       _tokenStorage = tokenStorage,
       _crypto = crypto,
       _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final VaultRemoteDatasource _remote;
  final AccountRemoteDatasource _accountRemote;
  final SecureTokenStorage _tokenStorage;
  final VaultCryptoService _crypto;
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
    final existing = _pending;
    if (existing != null &&
        (!existing.matchesDisplay(
              name: name,
              description: description,
              icon: icon,
              color: color,
            ) ||
            !await _matchesMemberKey(existing, memberPrivateKey))) {
      _pending = null;
    }
    _pending ??= await _prepare(
      name: name,
      description: description,
      icon: icon,
      color: color,
      memberPrivateKey: memberPrivateKey,
    );
    final pending = _pending!;
    final Map<String, dynamic> response;
    try {
      response = await _remote.createEncryptedVault(pending.payload);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        _pending = null;
      }
      rethrow;
    }
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
    CreatedVaultBundle? bundle;
    try {
      bundle = await _crypto.createVaultBundle(
        organizationId: organizationId,
        memberId: account.userId,
        memberKeyVersion: memberKeyVersion,
        vaultId: vaultId,
        memberPrivateKey: memberPrivateKey,
        name: name,
        description: description,
        icon: icon,
        color: color,
        grantMode: GrantMode.granular,
      );
      return _PendingVaultCreation(
        payload: Map<String, dynamic>.from(bundle.request.toJson()),
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
        memberPublicKeyFingerprint: bundle.memberFingerprint,
      );
    } finally {
      bundle?.vaultKey.fillRange(0, bundle.vaultKey.length, 0);
      bundle?.vaultDiscoveryKey.fillRange(
        0,
        bundle.vaultDiscoveryKey.length,
        0,
      );
    }
  }

  Future<bool> _matchesMemberKey(
    _PendingVaultCreation pending,
    Uint8List memberPrivateKey,
  ) async {
    if (memberPrivateKey.length != 32) return false;
    Uint8List? publicKey;
    try {
      final sodium = await _sodiumLoader();
      final secret = SecureKey.fromList(sodium, memberPrivateKey);
      try {
        publicKey = sodium.crypto.scalarmult.base(n: secret);
      } finally {
        secret.dispose();
      }
      final fingerprint = VaultProtocolBytes.base64UrlEncode(
        vaultPublicKeyFingerprint(VaultPublicKeyKind.memberX25519, publicKey),
      );
      return fingerprint == pending.memberPublicKeyFingerprint;
    } finally {
      publicKey?.fillRange(0, publicKey.length, 0);
    }
  }
}
