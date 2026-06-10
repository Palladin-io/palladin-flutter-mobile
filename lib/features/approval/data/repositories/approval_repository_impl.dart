import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../vault/data/datasources/entry_remote_datasource.dart';
import '../../../vault/data/datasources/vault_remote_datasource.dart';
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
  })  : _approval = approvalDatasource,
        _entries = entryDatasource,
        _vaults = vaultDatasource,
        _crypto = cryptoService;

  final ApprovalRemoteDatasource _approval;
  final EntryRemoteDatasource _entries;
  final VaultRemoteDatasource _vaults;
  final GrantCryptoService _crypto;

  @override
  Future<List<PendingGrant>> listPendingGrants() async {
    try {
      AppLogger.d('Approval', 'GET /api/dashboard/pending-grants');
      final models = await _approval.listPendingGrants();
      return models.map((m) => m.toEntity()).toList(growable: false);
    } on DioException catch (e, s) {
      AppLogger.e('Approval', 'listPendingGrants failed',
          error: e, stackTrace: s);
      throw ApprovalException(_classifyError(e));
    }
  }

  @override
  Future<void> approveGrant({
    required PendingGrant grant,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) async {
    // 1. + 2. Fetch the entry blob and the sealed VK (server round-trips).
    final String wrappedVK;
    final String entryBlob;
    final String entryNonce;
    try {
      AppLogger.d('Approval', 'Fetching entry + wrappedVK for approval');
      final detail = await _entries.getEntry(grant.vaultId, grant.entryId);
      wrappedVK = await _vaults.getVaultWrappedKey(grant.vaultId);
      entryBlob = detail.content.encryptedBlob;
      entryNonce = detail.content.nonce;
    } on DioException catch (e, s) {
      AppLogger.e('Approval', 'approve fetch failed', error: e, stackTrace: s);
      throw ApprovalException(_classifyError(e));
    }

    // 3. Produce the envelope on-device (zero-knowledge).
    final GrantEnvelope envelope;
    try {
      envelope = await _crypto.produceGrantEnvelope(
        wrappedVK: wrappedVK,
        privateKey: privateKey,
        entryBlob: entryBlob,
        entryNonce: entryNonce,
        agentPublicKey: grant.agentPublicKey,
      );
    } on ApprovalException {
      rethrow; // already typed (cryptoFailure)
    } catch (e, s) {
      AppLogger.e('Approval', 'envelope production failed',
          error: e, stackTrace: s);
      throw const ApprovalException(ApprovalErrorKind.cryptoFailure);
    }

    // 4. Submit. The XOR mapping (expiresAt XOR queryLimit) lives in the
    // tested GrantLimit.toWire() so the invariant is enforced in one place.
    final wire = limit.toWire();
    try {
      await _approval.approveGrant(
        vaultId: grant.vaultId,
        grantId: grant.grantId,
        entryId: grant.entryId,
        envelope: envelope,
        expiresAt: wire.expiresAt,
        queryLimit: wire.queryLimit,
        methods: serializeGrantMethods(methods),
      );
    } on DioException catch (e, s) {
      AppLogger.e('Approval', 'approve submit failed', error: e, stackTrace: s);
      throw ApprovalException(_classifyError(e));
    }
  }

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
      AppLogger.e('Approval', 're-grant fetch entry failed',
          error: e, stackTrace: s);
      throw ApprovalException(_classifyError(e));
    } catch (e, s) {
      AppLogger.e('Approval', 're-grant envelope failed',
          error: e, stackTrace: s);
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
      AppLogger.e('Approval', 're-grant submit failed', error: e, stackTrace: s);
      throw ApprovalException(_classifyError(e));
    }
  }

  @override
  Future<void> denyGrant({
    required PendingGrant grant,
    String? reason,
  }) async {
    try {
      AppLogger.d('Approval', 'PUT deny grantId=${grant.grantId}');
      await _approval.denyGrant(
        vaultId: grant.vaultId,
        grantId: grant.grantId,
        reason: reason,
      );
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
      400 || 409 => ApprovalErrorKind.validation,
      _ => ApprovalErrorKind.unknown,
    };
  }
}
