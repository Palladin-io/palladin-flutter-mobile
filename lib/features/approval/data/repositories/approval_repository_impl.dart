import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../vault/data/datasources/entry_remote_datasource.dart';
import '../../../vault/data/datasources/vault_remote_datasource.dart';
import '../../../vault/data/services/canonical_entry_detail_service.dart';
import '../../../vault/data/datasources/agent_discovery_remote_datasource.dart';
import '../../../vault/domain/entities/agent_visibility_policy.dart';
import '../../../vault/domain/entities/entry_entity.dart';
import '../../../grants/domain/entities/grant_method.dart';
import '../../domain/entities/pending_grant.dart';
import '../../domain/exceptions/approval_exceptions.dart';
import '../../domain/repositories/approval_repository.dart';
import '../datasources/approval_remote_datasource.dart';
import '../services/grant_crypto_service.dart';

/// Concrete [ApprovalRepository].
///
/// Orchestrates the GRANULAR approval pipeline:
///   1. fetch the entry's encrypted blob (`GET .../entries/{id}`),
///   2. fetch the vault's sealed VK (`GET /api/vaults/{id}`),
///   3. produce the envelope on-device ([GrantCryptoService]),
///   4. submit it (`PUT .../approve`).
///
/// Reuses the vault feature's entry + vault datasources rather than
/// duplicating those routes. Translates wire / crypto failures into typed
/// [ApprovalException]s. No secret material is logged.
class ApprovalRepositoryImpl implements ApprovalRepository {
  ApprovalRepositoryImpl({
    required ApprovalRemoteDatasource approvalDatasource,
    required EntryRemoteDatasource entryDatasource,
    required VaultRemoteDatasource vaultDatasource,
    required GrantCryptoService cryptoService,
    required CanonicalEntryDetailService canonicalEntries,
    required AgentDiscoveryRemote discovery,
  }) : _approval = approvalDatasource,
       _entries = entryDatasource,
       _vaults = vaultDatasource,
       _crypto = cryptoService,
       _canonicalEntries = canonicalEntries,
       _discovery = discovery;

  final ApprovalRemoteDatasource _approval;
  final EntryRemoteDatasource _entries;
  final VaultRemoteDatasource _vaults;
  final GrantCryptoService _crypto;
  final CanonicalEntryDetailService _canonicalEntries;
  final AgentDiscoveryRemote _discovery;

  @override
  Future<List<PendingGrant>> listPendingGrants() async {
    try {
      AppLogger.d('Approval', 'GET /api/dashboard/pending-grants');
      final result = <PendingGrant>[];
      final seen = <String>{};
      String? cursor;
      do {
        final page = await _approval.listPendingGrants(cursor: cursor);
        result.addAll(page.items.map((model) => model.toEntity()));
        if (result.length > 2000) {
          throw const FormatException('Pending grant list exceeds limit');
        }
        cursor = page.nextCursor;
        if (cursor != null && !seen.add(cursor)) {
          throw const FormatException('Pending grant cursor did not advance');
        }
      } while (cursor != null);
      return List.unmodifiable(result);
    } on DioException catch (e) {
      AppLogger.w('Approval', 'pending grant list request failed');
      throw ApprovalException(_classifyError(e));
    }
  }

  @override
  Future<void> approveGrant({
    required PendingGrant grant,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
    required List<String> fieldIds,
    required String reviewedEntryRevision,
  }) async {
    CanonicalEntrySnapshot? snapshot;
    try {
      final freshGrant = (await _approval.getGrant(
        grant.vaultId,
        grant.grantId,
      )).toEntity();
      if (freshGrant.encryptedReason.requestRevision !=
          grant.encryptedReason.requestRevision) {
        throw const ApprovalException(ApprovalErrorKind.conflict);
      }
      snapshot = await _canonicalEntries.reveal(
        expected: EntryEntity(
          id: grant.entryId,
          vaultId: grant.vaultId,
          label: '',
          type: EntryType.key,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        memberPrivateKey: privateKey,
      );
      if (snapshot.entry['currentRevision'] != reviewedEntryRevision) {
        throw const ApprovalException(ApprovalErrorKind.conflict);
      }
      final vault = await _vaults.getEncryptedVault(grant.vaultId);
      final candidates = (await _discovery.list(grant.vaultId))
          .where((item) => item.agentId == grant.agentId && item.isCurrent)
          .toList(growable: false);
      if (candidates.length != 1) {
        throw const FormatException('Agent identity unavailable');
      }
      final candidate = candidates.single;
      final type = EntryTypeExtension.fromWire(
        snapshot.secret['entryType'] as int,
      );
      final policy = AgentVisibilityPolicy.fromJson(
        type,
        Map<String, dynamic>.from(
          snapshot.secret['agentVisibilityPolicy'] as Map,
        ),
        content: snapshot.payload,
      );
      final approvedMethods = _methodBits(methods);
      final requestedMethods = grant.encryptedReason.requestedMethods;
      if (approvedMethods == 0 ||
          (approvedMethods & requestedMethods) != approvedMethods) {
        throw const FormatException('Approval methods exceed request');
      }
      final wire = limit.toWire();
      final grantEntry = await _crypto.produceProtocolEnvelope(
        organizationId: snapshot.entry['organizationId'] as String,
        vaultId: grant.vaultId,
        grantId: grant.grantId,
        agentId: grant.agentId,
        entryId: grant.entryId,
        entryRevision: reviewedEntryRevision,
        memberKeyGeneration: vault['memberKeyGeneration'] as int,
        recipientAgentKeyVersion: candidate.recipientKeyVersion,
        agentPublicKey: candidate.x25519PublicKey,
        approvedMethods: approvedMethods,
        type: type,
        agentLabel:
            snapshot.secret['agentLabel'] as String? ??
            snapshot.secret['memberLabel'] as String,
        description: snapshot.secret['description'] as String? ?? '',
        content: snapshot.payload,
        policy: policy,
        approvedFieldIds: fieldIds,
        expiresAt: wire.expiresAt,
        remainingUses: wire.queryLimit,
      );
      final latest = await _entries.getCanonicalEntry(
        grant.vaultId,
        grant.entryId,
      );
      if (latest['currentRevision'] != reviewedEntryRevision) {
        throw const ApprovalException(ApprovalErrorKind.conflict);
      }
      await _approval.approveGrant(
        vaultId: grant.vaultId,
        grantId: grant.grantId,
        grantEntry: grantEntry,
        expiresAt: wire.expiresAt,
        queryLimit: wire.queryLimit,
        methods: serializeGrantMethods(methods),
      );
    } on DioException catch (e) {
      throw ApprovalException(_classifyError(e));
    } on ApprovalException {
      rethrow;
    } catch (_) {
      throw const ApprovalException(ApprovalErrorKind.cryptoFailure);
    } finally {
      snapshot?.clear();
    }
  }

  int _methodBits(Iterable<GrantMethod> methods) => methods.fold(
    0,
    (bits, method) =>
        bits |
        switch (method) {
          GrantMethod.get => 1,
          GrantMethod.exec => 2,
          GrantMethod.inject => 4,
        },
  );

  @override
  Future<void> createGrant({
    required String vaultId,
    required String agentId,
    required String agentPublicKey,
    required bool isFull,
    String? entryId,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) async {
    // 1. Resolve which entries to wrap: every vault entry (full) or just one
    //    (granular). Fetch the sealed VK once.
    final String wrappedVK;
    final List<String> entryIds;
    try {
      AppLogger.d('Approval', 'Fetching entries + wrappedVK for re-grant');
      wrappedVK = await _vaults.getVaultWrappedKey(vaultId);
      if (isFull) {
        final entries = await _entries.listEntries(vaultId);
        entryIds = entries.map((e) => e.id).toList(growable: false);
      } else {
        entryIds = [entryId!];
      }
    } on DioException catch (e, s) {
      AppLogger.e('Approval', 're-grant fetch failed', error: e, stackTrace: s);
      throw ApprovalException(_classifyError(e));
    }

    if (entryIds.isEmpty) {
      throw const ApprovalException(ApprovalErrorKind.validation);
    }

    // 2. Produce one envelope per entry on-device (zero-knowledge).
    final wrapped = <({String entryId, GrantEnvelope envelope})>[];
    try {
      for (final id in entryIds) {
        final detail = await _entries.getEntry(vaultId, id);
        final envelope = await _crypto.produceGrantEnvelope(
          wrappedVK: wrappedVK,
          privateKey: privateKey,
          entryBlob: detail.content.encryptedBlob,
          entryNonce: detail.content.nonce,
          agentPublicKey: agentPublicKey,
        );
        wrapped.add((entryId: id, envelope: envelope));
      }
    } on ApprovalException {
      rethrow;
    } on DioException catch (e, s) {
      AppLogger.e(
        'Approval',
        're-grant fetch entry failed',
        error: e,
        stackTrace: s,
      );
      throw ApprovalException(_classifyError(e));
    } catch (e, s) {
      AppLogger.e(
        'Approval',
        're-grant envelope failed',
        error: e,
        stackTrace: s,
      );
      throw const ApprovalException(ApprovalErrorKind.cryptoFailure);
    }

    // 3. Submit the new grant.
    final wire = limit.toWire();
    try {
      await _approval.createGrant(
        vaultId: vaultId,
        agentId: agentId,
        type: isFull ? 'full' : 'granular',
        entryId: isFull ? null : entryId,
        entries: wrapped,
        expiresAt: wire.expiresAt,
        queryLimit: wire.queryLimit,
        methods: serializeGrantMethods(methods),
      );
    } on DioException catch (e, s) {
      AppLogger.e(
        'Approval',
        're-grant submit failed',
        error: e,
        stackTrace: s,
      );
      throw ApprovalException(_classifyError(e));
    }
  }

  @override
  Future<void> denyGrant({required PendingGrant grant}) async {
    try {
      AppLogger.d('Approval', 'PUT deny grantId=${grant.grantId}');
      await _approval.denyGrant(vaultId: grant.vaultId, grantId: grant.grantId);
    } on DioException catch (e, s) {
      AppLogger.e('Approval', 'deny failed', error: e, stackTrace: s);
      throw ApprovalException(_classifyError(e));
    }
  }

  ApprovalErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return ApprovalErrorKind.networkError;
    }
    return switch (e.response?.statusCode) {
      404 => ApprovalErrorKind.notFound,
      403 => ApprovalErrorKind.forbidden,
      400 => ApprovalErrorKind.validation,
      409 => ApprovalErrorKind.conflict,
      _ => ApprovalErrorKind.unknown,
    };
  }
}
