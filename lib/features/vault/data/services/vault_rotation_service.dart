import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../datasources/vault_rotation_remote_datasource.dart';
import '../models/vault_rotation_models.dart';
import 'vault_protocol/vault_protocol_aad.dart';
import 'vault_protocol/vault_protocol_bytes.dart';
import 'vault_rotation_crypto_service.dart';

final class VaultRotationException implements Exception {
  const VaultRotationException(this.code);
  final String code;
  @override
  String toString() => 'VaultRotationException($code)';
}

final class _RotationSecrets {
  _RotationSecrets({
    required this.currentVaultKey,
    required this.targetVaultKey,
    required this.currentVdk,
    required this.targetVdk,
    required this.targetMessagePrivateKey,
    required this.targetSigningSeed,
    required this.pendingDiscoveryKey,
    required this.pendingPrivateKeys,
  });

  final Uint8List currentVaultKey;
  final Uint8List targetVaultKey;
  final Uint8List currentVdk;
  final Uint8List targetVdk;
  final Uint8List targetMessagePrivateKey;
  final Uint8List targetSigningSeed;
  final Map<String, dynamic>? pendingDiscoveryKey;
  final List<Map<String, dynamic>> pendingPrivateKeys;

  void dispose() {
    for (final key in [
      currentVaultKey,
      targetVaultKey,
      currentVdk,
      targetVdk,
      targetMessagePrivateKey,
      targetSigningSeed,
    ]) {
      key.fillRange(0, key.length, 0);
    }
  }
}

final class _RotationLease {
  _RotationLease(this.claim, this.claimedAt);
  VaultRotationClaimModel claim;
  DateTime claimedAt;
  String get token => claim.fencingToken;
}

/// Resumes server-owned pending rotations after unlock without persisting keys
/// or plaintext progress. Cancellation safely pauses at network/batch bounds.
final class VaultRotationService {
  VaultRotationService({
    required VaultRotationRemoteDatasource remote,
    required VaultRotationCryptoService crypto,
    DateTime Function()? now,
  }) : _remote = remote,
       _crypto = crypto,
       _now = now ?? DateTime.now;

  static const _leaseRenewAfter = Duration(seconds: 55);
  static const _maximumCommitReconciliations = 3;

  final VaultRotationRemoteDatasource _remote;
  final VaultRotationCryptoService _crypto;
  final DateTime Function() _now;
  CancelToken? _activeToken;
  Future<void>? _activeRun;

  bool get isRunning => _activeRun != null;

  /// Starts one process-local worker. Repeated unlock notifications share it.
  Future<void> resumeAfterUnlock({
    required String memberId,
    required Uint8List memberPrivateKey,
  }) async {
    final current = _activeRun;
    if (current != null) {
      if (_activeToken?.isCancelled != true) return current;
      try {
        await current;
      } on DioException catch (error) {
        if (!CancelToken.isCancel(error)) rethrow;
      }
    }
    return _activeRun ??= _run(memberId, memberPrivateKey).whenComplete(() {
      _activeRun = null;
      _activeToken = null;
    });
  }

  /// Cancels in-flight HTTP work. Service-owned secrets are wiped by finally.
  void pause() => _activeToken?.cancel('Vault rotation paused');

  Future<void> _run(String memberId, Uint8List memberPrivateKey) async {
    final token = CancelToken();
    _activeToken = token;
    final rotations = await _remote.listPending(token);
    for (final rotation in rotations) {
      if (token.cancelError case final cancellation?) throw cancellation;
      await _runRotation(rotation, memberId, memberPrivateKey, token);
    }
  }

  Future<void> _runRotation(
    VaultRotationModel listed,
    String memberId,
    Uint8List memberPrivateKey,
    CancelToken token,
  ) async {
    final lease = _RotationLease(
      await _remote.claim(listed.vaultId, listed.id, token),
      _now(),
    );
    if (!listed.samePlan(lease.claim.rotation)) {
      throw const VaultRotationException('rotation-plan-changed');
    }
    final secrets = await _loadSecrets(lease.claim, memberPrivateKey);
    var seedEstablished =
        lease.claim.pendingMemberVaultKey != null ||
        lease.claim.pendingDiscoveryKey != null ||
        lease.claim.pendingVaultPrivateKeys.isNotEmpty;
    try {
      if (listed.rotates('VaultKey')) {
        final self = await _findMember(
          listed,
          lease,
          memberId,
          memberPrivateKey,
          secrets,
          seedEstablished,
          token,
        );
        final envelope = await _crypto.sealMemberVaultKey(
          recipient: self,
          organizationId:
              lease.claim.currentMemberVaultKey['organizationId']! as String,
          vaultId: listed.vaultId,
          vkVersion: listed.targetKeyEpoch.vaultKeyVersion,
          memberKeyGeneration: listed.targetMemberKeyGeneration,
          vaultKey: secrets.targetVaultKey,
        );
        await _remote.prepare(listed.vaultId, listed.id, lease.token, {
          'memberVaultKeys': [envelope],
          if (secrets.pendingDiscoveryKey != null)
            'discoveryKey': secrets.pendingDiscoveryKey,
          'vaultPrivateKeys': secrets.pendingPrivateKeys,
        }, token);
      } else if (!seedEstablished) {
        await _remote.prepare(listed.vaultId, listed.id, lease.token, {
          if (secrets.pendingDiscoveryKey != null)
            'discoveryKey': secrets.pendingDiscoveryKey,
          'vaultPrivateKeys': secrets.pendingPrivateKeys,
        }, token);
      }
      seedEstablished = true;
      for (
        var attempt = 0;
        attempt < _maximumCommitReconciliations;
        attempt += 1
      ) {
        await _prepareAll(
          listed,
          lease,
          memberPrivateKey,
          secrets,
          seedEstablished,
          token,
        );
        await _renew(lease, memberPrivateKey, secrets, seedEstablished, token);
        final committed = await _remote.commit(
          listed.vaultId,
          listed.id,
          lease.token,
          token,
        );
        if (committed.committed) return;
      }
      throw const VaultRotationException('rotation-remained-dirty');
    } finally {
      secrets.dispose();
    }
  }

  Future<_RotationSecrets> _loadSecrets(
    VaultRotationClaimModel claim,
    Uint8List memberPrivateKey,
  ) async {
    final rotation = claim.rotation;
    final currentVaultKey = await _crypto.openMemberVaultKey(
      claim.currentMemberVaultKey,
      memberPrivateKey,
    );
    final generated = await _crypto.generateKeys();
    Uint8List? targetVaultKey;
    Uint8List? currentVdk;
    Uint8List? targetVdk;
    Uint8List? targetMessage;
    Uint8List? targetSigning;
    try {
      targetVaultKey = claim.pendingMemberVaultKey != null
          ? await _crypto.openMemberVaultKey(
              claim.pendingMemberVaultKey!,
              memberPrivateKey,
            )
          : Uint8List.fromList(
              rotation.rotates('VaultKey')
                  ? generated.vaultKey
                  : currentVaultKey,
            );
      currentVdk = await _crypto.openDiscoveryKey(
        claim.currentDiscoveryKey,
        currentVaultKey,
      );
      targetVdk = claim.pendingDiscoveryKey != null
          ? await _crypto.openDiscoveryKey(
              claim.pendingDiscoveryKey!,
              targetVaultKey,
            )
          : Uint8List.fromList(
              rotation.rotates('Vdk') ? generated.vdk : currentVdk,
            );
      final currentPrivate = {
        for (final item in claim.currentVaultPrivateKeys)
          item['privateKeyKind']! as int: item,
      };
      final pendingPrivate = {
        for (final item in claim.pendingVaultPrivateKeys)
          item['privateKeyKind']! as int: item,
      };
      Future<Uint8List> targetPrivate(
        int kind,
        bool rotates,
        Uint8List generatedKey,
      ) async {
        if (pendingPrivate[kind] case final pending?) {
          return _crypto.openPrivateKey(pending, targetVaultKey!);
        }
        if (rotates) return Uint8List.fromList(generatedKey);
        final current = currentPrivate[kind];
        if (current == null) {
          throw const VaultRotationException(
            'current-vault-private-key-missing',
          );
        }
        return _crypto.openPrivateKey(current, currentVaultKey);
      }

      targetMessage = await targetPrivate(
        1,
        rotation.rotates('AgentMessage'),
        generated.agentMessagePrivateKey,
      );
      targetSigning = await targetPrivate(
        2,
        rotation.rotates('ManifestSigning'),
        generated.manifestSigningSeed,
      );
      final rewrapAll = rotation.rotates('VaultKey');
      final pendingDiscovery =
          claim.pendingDiscoveryKey ??
          ((rewrapAll || rotation.rotates('Vdk'))
              ? await _crypto.encryptKeyMaterial(
                  source: claim.currentDiscoveryKey,
                  profile: VaultAadProfile.vaultDiscoveryKey,
                  plaintext: targetVdk,
                  targetVaultKey: targetVaultKey,
                  targetVersion: rotation.targetKeyEpoch.vdkVersion,
                  targetGeneration: rotation.targetMemberKeyGeneration,
                  targetVaultKeyVersion:
                      rotation.targetKeyEpoch.vaultKeyVersion,
                )
              : null);
      final pendingKeys = <Map<String, dynamic>>[];
      for (final kind in [1, 2]) {
        if (pendingPrivate[kind] case final pending?) {
          pendingKeys.add(pending);
          continue;
        }
        final rotates = kind == 1
            ? rotation.rotates('AgentMessage')
            : rotation.rotates('ManifestSigning');
        if (!rewrapAll && !rotates) continue;
        pendingKeys.add(
          await _crypto.encryptKeyMaterial(
            source: currentPrivate[kind]!,
            profile: VaultAadProfile.vaultPrivateKey,
            plaintext: kind == 1 ? targetMessage : targetSigning,
            targetVaultKey: targetVaultKey,
            targetVersion: kind == 1
                ? rotation.targetKeyEpoch.agentMessageKeyVersion
                : rotation.targetKeyEpoch.manifestSigningKeyVersion,
            targetGeneration: rotation.targetMemberKeyGeneration,
            targetVaultKeyVersion: rotation.targetKeyEpoch.vaultKeyVersion,
          ),
        );
      }
      return _RotationSecrets(
        currentVaultKey: currentVaultKey,
        targetVaultKey: targetVaultKey,
        currentVdk: currentVdk,
        targetVdk: targetVdk,
        targetMessagePrivateKey: targetMessage,
        targetSigningSeed: targetSigning,
        pendingDiscoveryKey: pendingDiscovery,
        pendingPrivateKeys: pendingKeys,
      );
    } catch (_) {
      currentVaultKey.fillRange(0, currentVaultKey.length, 0);
      for (final key in [
        targetVaultKey,
        currentVdk,
        targetVdk,
        targetMessage,
        targetSigning,
      ]) {
        key?.fillRange(0, key.length, 0);
      }
      rethrow;
    } finally {
      generated.dispose();
    }
  }

  Future<void> _prepareAll(
    VaultRotationModel rotation,
    _RotationLease lease,
    Uint8List memberPrivateKey,
    _RotationSecrets secrets,
    bool seedEstablished,
    CancelToken token,
  ) async {
    if (rotation.rotates('VaultKey')) {
      String? cursor;
      do {
        await _renew(lease, memberPrivateKey, secrets, seedEstablished, token);
        final page = await _remote.members(
          rotation.vaultId,
          rotation.id,
          lease.token,
          cursor,
          token,
        );
        final envelopes = <Map<String, dynamic>>[];
        for (final recipient in page.items) {
          envelopes.add(
            await _crypto.sealMemberVaultKey(
              recipient: recipient,
              organizationId:
                  lease.claim.currentMemberVaultKey['organizationId']!
                      as String,
              vaultId: rotation.vaultId,
              vkVersion: rotation.targetKeyEpoch.vaultKeyVersion,
              memberKeyGeneration: rotation.targetMemberKeyGeneration,
              vaultKey: secrets.targetVaultKey,
            ),
          );
        }
        if (envelopes.isNotEmpty) {
          await _remote.prepare(rotation.vaultId, rotation.id, lease.token, {
            'memberVaultKeys': envelopes,
          }, token);
        }
        cursor = page.nextAfterId;
      } while (cursor != null);

      final metadata = await _remote.vaultMetadata(rotation.vaultId, token);
      final rotatedMetadata = await _crypto.rotateProjection(
        profile: VaultAadProfile.memberVaultMetadata,
        source: metadata,
        currentBaseKey: secrets.currentVaultKey,
        targetBaseKey: secrets.targetVaultKey,
        targetKeyVersion: rotation.targetKeyEpoch.vaultKeyVersion,
        targetGeneration: rotation.targetMemberKeyGeneration,
      );
      await _remote.prepare(rotation.vaultId, rotation.id, lease.token, {
        'memberVaultMetadata': rotatedMetadata,
      }, token);

      String? afterId;
      int? afterVersion;
      do {
        await _renew(lease, memberPrivateKey, secrets, seedEstablished, token);
        final page = await _remote.entryKeys(
          rotation.vaultId,
          rotation.id,
          lease.token,
          afterId,
          afterVersion,
          token,
        );
        final keys = <Map<String, dynamic>>[];
        for (final source in page.items) {
          keys.add(
            await _crypto.rewrapEntryKey(
              source,
              secrets.currentVaultKey,
              secrets.targetVaultKey,
              rotation.targetMemberKeyGeneration,
              rotation.targetKeyEpoch.vaultKeyVersion,
            ),
          );
        }
        if (keys.isNotEmpty) {
          await _remote.prepare(rotation.vaultId, rotation.id, lease.token, {
            'entryKeys': keys,
          }, token);
        }
        afterId = page.nextAfterId;
        afterVersion = page.nextAfterVersion;
      } while (afterId != null);

      String? afterGrantId;
      do {
        await _renew(lease, memberPrivateKey, secrets, seedEstablished, token);
        final page = await _remote.fullGrants(
          rotation.vaultId,
          rotation.id,
          lease.token,
          afterGrantId,
          token,
        );
        final wrappers = <Map<String, Object?>>[];
        for (final recipient in page.items) {
          wrappers.add(
            await _crypto.sealAgentVaultKey(
              recipient: recipient,
              organizationId:
                  lease.claim.currentMemberVaultKey['organizationId']!
                      as String,
              vaultId: rotation.vaultId,
              vaultKeyVersion: rotation.targetKeyEpoch.vaultKeyVersion,
              vaultKey: secrets.targetVaultKey,
            ),
          );
        }
        if (wrappers.isNotEmpty) {
          await _remote.prepare(rotation.vaultId, rotation.id, lease.token, {
            'agentWrappedVaultKeys': wrappers,
          }, token);
        }
        afterGrantId = page.nextAfterId;
      } while (afterGrantId != null);
    }

    if (rotation.rotates('Vdk')) {
      String? cursor;
      do {
        await _renew(lease, memberPrivateKey, secrets, seedEstablished, token);
        final page = await _remote.discoveries(
          rotation.vaultId,
          rotation.id,
          lease.token,
          cursor,
          token,
        );
        final items = <Map<String, dynamic>>[];
        for (final source in page.items) {
          items.add({
            'sourceRevision': source.sourceRevision,
            'envelope': await _crypto.rotateProjection(
              profile: VaultAadProfile.agentDiscovery,
              source: source.envelope,
              currentBaseKey: secrets.currentVdk,
              targetBaseKey: secrets.targetVdk,
              targetKeyVersion: rotation.targetKeyEpoch.vdkVersion,
              targetGeneration: rotation.targetMemberKeyGeneration,
            ),
          });
        }
        if (items.isNotEmpty) {
          await _remote.prepare(rotation.vaultId, rotation.id, lease.token, {
            'entryDiscoveries': items,
          }, token);
        }
        cursor = page.nextAfterId;
      } while (cursor != null);
    }

    if (rotation.rotates('Vdk') ||
        rotation.rotates('AgentMessage') ||
        rotation.rotates('ManifestSigning')) {
      String? cursor;
      do {
        await _renew(lease, memberPrivateKey, secrets, seedEstablished, token);
        final page = await _remote.agents(rotation.vaultId, cursor, token);
        final items = <Map<String, dynamic>>[];
        for (final agent in page.items) {
          items.add(
            await _crypto.createAgentMaterial(
              agent: agent,
              organizationId:
                  lease.claim.currentMemberVaultKey['organizationId']!
                      as String,
              vaultId: rotation.vaultId,
              epoch: rotation.targetKeyEpoch,
              vdk: secrets.targetVdk,
              messagePrivateKey: secrets.targetMessagePrivateKey,
              signingSeed: secrets.targetSigningSeed,
            ),
          );
        }
        if (items.isNotEmpty) {
          await _remote.prepare(rotation.vaultId, rotation.id, lease.token, {
            'agentDiscoveries': items,
          }, token);
        }
        cursor = page.nextAfterId;
      } while (cursor != null);
    }
  }

  Future<RotationMemberRecipient> _findMember(
    VaultRotationModel rotation,
    _RotationLease lease,
    String memberId,
    Uint8List memberPrivateKey,
    _RotationSecrets secrets,
    bool seedEstablished,
    CancelToken token,
  ) async {
    String? cursor;
    do {
      await _renew(lease, memberPrivateKey, secrets, seedEstablished, token);
      final page = await _remote.members(
        rotation.vaultId,
        rotation.id,
        lease.token,
        cursor,
        token,
      );
      for (final item in page.items) {
        if (item.memberId == memberId) return item;
      }
      cursor = page.nextAfterId;
    } while (cursor != null);
    throw const VaultRotationException('rotation-claimant-not-recipient');
  }

  Future<void> _renew(
    _RotationLease lease,
    Uint8List memberPrivateKey,
    _RotationSecrets secrets,
    bool seedEstablished,
    CancelToken token,
  ) async {
    if (_now().difference(lease.claimedAt) < _leaseRenewAfter) return;
    final renewed = await _remote.claim(
      lease.claim.rotation.vaultId,
      lease.claim.rotation.id,
      token,
    );
    if (!lease.claim.rotation.samePlan(renewed.rotation)) {
      throw const VaultRotationException('rotation-plan-changed');
    }
    if (seedEstablished && renewed.preparedMaterialReset) {
      throw const VaultRotationException('rotation-seed-reset');
    }
    if (seedEstablished) {
      await _verifySeeds(renewed, memberPrivateKey, secrets);
    }
    lease
      ..claim = renewed
      ..claimedAt = _now();
  }

  Future<void> _verifySeeds(
    VaultRotationClaimModel claim,
    Uint8List memberPrivateKey,
    _RotationSecrets secrets,
  ) async {
    final opened = <Uint8List>[];
    try {
      if (claim.rotation.rotates('VaultKey')) {
        if (claim.pendingMemberVaultKey == null) {
          throw const VaultRotationException('pending-vault-key-missing');
        }
        opened.add(
          await _crypto.openMemberVaultKey(
            claim.pendingMemberVaultKey!,
            memberPrivateKey,
          ),
        );
        _assertSame(opened.last, secrets.targetVaultKey);
      }
      if (claim.rotation.rotates('VaultKey') || claim.rotation.rotates('Vdk')) {
        if (claim.pendingDiscoveryKey == null) {
          throw const VaultRotationException('pending-vdk-missing');
        }
        opened.add(
          await _crypto.openDiscoveryKey(
            claim.pendingDiscoveryKey!,
            secrets.targetVaultKey,
          ),
        );
        _assertSame(opened.last, secrets.targetVdk);
      }
      final pending = {
        for (final item in claim.pendingVaultPrivateKeys)
          item['privateKeyKind']! as int: item,
      };
      for (final kind in [1, 2]) {
        final rotates = kind == 1
            ? claim.rotation.rotates('AgentMessage')
            : claim.rotation.rotates('ManifestSigning');
        if (!claim.rotation.rotates('VaultKey') && !rotates) continue;
        if (pending[kind] case final envelope?) {
          opened.add(
            await _crypto.openPrivateKey(envelope, secrets.targetVaultKey),
          );
          _assertSame(
            opened.last,
            kind == 1
                ? secrets.targetMessagePrivateKey
                : secrets.targetSigningSeed,
          );
        } else {
          throw const VaultRotationException('pending-private-key-missing');
        }
      }
    } finally {
      for (final key in opened) {
        key.fillRange(0, key.length, 0);
      }
    }
  }

  void _assertSame(Uint8List left, Uint8List right) {
    if (!VaultProtocolBytes.constantTimeEquals(left, right)) {
      throw const VaultRotationException('rotation-seed-changed');
    }
  }
}
