import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../../../core/crypto/envelope/envelope_contract.dart';
import '../../../../core/crypto/kem/xwing.dart';
import '../../../../core/crypto/recipient_key_wrapper.dart';
import '../../../../core/crypto/sodium_provider.dart';
import '../datasources/vault_remote_datasource.dart';
import '../datasources/vault_rotation_remote_datasource.dart';
import 'vault_crypto_service.dart';
import 'vault_rotation_crypto_service.dart';
import 'vault_rotation_service.dart';

/// Publishes an active-suite Vault Agent message key for one Vault through
/// the agent-message-only `ProtocolMigration` rotation: the new private key
/// under the unchanged VK, its public anchor and a successor manifest per
/// Agent. Agents still on a read-only key are skipped; Discovery
/// reconciliation provisions them after they rotate. Pending reasons sealed
/// to the old key are invalidated by the backend at commit.
class AgentMessageKeyMigrationService {
  AgentMessageKeyMigrationService({
    required this._rotations,
    required this._vaults,
    required this._vaultCrypto,
    required this._rotationCrypto,
    Future<SodiumSumo> Function()? sodiumLoader,
  }) : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final VaultRotationRemoteDatasource _rotations;
  final VaultRemoteDatasource _vaults;
  final VaultCryptoService _vaultCrypto;
  final VaultRotationCryptoService _rotationCrypto;
  final Future<SodiumSumo> Function() _sodiumLoader;

  /// Whether the encrypted Vault response still names a non-active message
  /// key suite (absent = legacy).
  static bool needsMigration(Map<String, dynamic> vault) =>
      WrapperSuite.tryParse(vault['vaultAgentMessageKeySuiteId']) !=
      WrapperSuite.active;

  /// Returns false when the backend reports the key already current (409).
  Future<bool> migrate({
    required String vaultId,
    required Uint8List memberPrivateKey,
    CancelToken? cancelToken,
  }) async {
    final token = cancelToken ?? CancelToken();
    final rotation = await _rotations.startAgentMessageKeyMigration(
      vaultId,
      token,
    );
    if (rotation == null) return false;
    if (rotation.scope.length != 1 || !rotation.rotates('AgentMessage')) {
      throw const VaultRotationException('rotation-plan-changed');
    }
    final claim = await _rotations.claim(vaultId, rotation.id, token);
    if (!rotation.samePlan(claim.rotation)) {
      throw const VaultRotationException('rotation-plan-changed');
    }
    final vault = await _vaults.getEncryptedVault(vaultId);
    final opened = await _vaultCrypto.openVaultProjection(
      json: vault,
      memberPrivateKey: memberPrivateKey,
    );
    Uint8List? signingSeed;
    Uint8List? messageSeed;
    try {
      final vdk = opened.vaultDiscoveryKey;
      final base = rotation.baseKeyEpoch;
      final current = opened.epoch;
      if (vdk == null ||
          opened.organizationId != claim.organizationId ||
          current.vaultKeyVersion != base.vaultKeyVersion ||
          current.vdkVersion != base.vdkVersion ||
          current.agentMessageKeyVersion != base.agentMessageKeyVersion ||
          current.manifestSigningKeyVersion != base.manifestSigningKeyVersion) {
        throw const VaultRotationException('rotation-plan-changed');
      }
      final target = rotation.targetKeyEpoch;
      final currentMessage =
          VaultRotationCryptoService.requirePrivateKeyEnvelope(
            envelopes: vault['vaultPrivateKeys'],
            purpose: 'vaultAgentMessagePrivateKey',
            keyVersion: base.agentMessageKeyVersion,
          );
      signingSeed = await _rotationCrypto
          .openCanonicalManifestSigningPrivateKey(
            VaultRotationCryptoService.requirePrivateKeyEnvelope(
              envelopes: vault['vaultPrivateKeys'],
              purpose: 'vaultManifestSigningPrivateKey',
              keyVersion: base.manifestSigningKeyVersion,
            ),
            opened.vaultKey,
            expectedKeyVersion: base.manifestSigningKeyVersion,
          );
      messageSeed = XWing(await _sodiumLoader()).generateSeed();
      final privateKeyEnvelope = await _vaultCrypto.sealVaultPrivateKey(
        organizationId: opened.organizationId,
        vaultId: vaultId,
        purpose: EnvelopePurpose.agentMessagePrivateByVk,
        resourceRevision:
            int.parse(
              (currentMessage['descriptor'] as Map)['resourceRevision']
                  as String,
            ) +
            1,
        keyVersion: target.agentMessageKeyVersion,
        memberKeyGeneration: opened.memberKeyGeneration,
        vaultKeyVersion: base.vaultKeyVersion,
        privateKey: messageSeed,
        vaultKey: opened.vaultKey,
      );
      final anchors = await _rotationCrypto.createPublicTrustAnchors(
        agentMessagePrivateKey: messageSeed,
        agentMessageKeySuite: WrapperSuite.active,
        manifestSigningPrivateKey: signingSeed,
        agentMessageKeyVersion: target.agentMessageKeyVersion,
        manifestSigningKeyVersion: target.manifestSigningKeyVersion,
      );
      final discoveries = <Map<String, dynamic>>[];
      String? cursor;
      do {
        final page = await _rotations.agents(vaultId, cursor, token);
        for (final agent in page.items) {
          try {
            discoveries.add(
              await _rotationCrypto.createAgentMaterial(
                agent: agent,
                organizationId: opened.organizationId,
                vaultId: vaultId,
                epoch: target,
                vdk: vdk,
                messagePrivateKey: messageSeed,
                messageKeySuite: WrapperSuite.active,
                signingSeed: signingSeed,
              ),
            );
          } on KeyMigrationPendingException {
            continue;
          }
        }
        cursor = page.nextAfterId;
      } while (cursor != null);
      await _rotations.prepare(vaultId, rotation.id, claim.fencingToken, {
        'vaultPrivateKeys': [privateKeyEnvelope],
        'vaultAgentMessagePublicKey': anchors['agentMessage'],
        'agentDiscoveries': discoveries,
      }, token);
      final committed = await _rotations.commit(
        vaultId,
        rotation.id,
        claim.fencingToken,
        token,
      );
      if (!committed.committed) {
        throw const VaultRotationException('rotation-remained-dirty');
      }
      return true;
    } finally {
      opened.vaultKey.fillRange(0, opened.vaultKey.length, 0);
      opened.vaultDiscoveryKey?.fillRange(
        0,
        opened.vaultDiscoveryKey!.length,
        0,
      );
      signingSeed?.fillRange(0, signingSeed.length, 0);
      messageSeed?.fillRange(0, messageSeed.length, 0);
    }
  }
}
