import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/crypto/vault_session_store.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../grants/domain/entities/grant_method.dart';
import '../../../vault/data/datasources/entry_remote_datasource.dart';
import '../../../vault/data/services/entry_v2_crypto_service.dart';
import '../../../vault/domain/entities/vault_plaintext.dart';
import '../../domain/entities/pending_grant.dart';
import '../../domain/exceptions/approval_exceptions.dart';
import '../../domain/repositories/approval_repository.dart';
import '../datasources/approval_remote_datasource.dart';

/// Canonical protocol-v2 Grant orchestration. Plaintext and Vault keys remain
/// in process memory and every secret copy is wiped on all exit paths.
class ApprovalRepositoryImpl implements ApprovalRepository {
  ApprovalRepositoryImpl({
    required ApprovalRemoteDatasource approvalDatasource,
    required EntryRemoteDatasource entryDatasource,
    required EntryV2CryptoService cryptoService,
    required VaultSessionStore sessionStore,
  }) : _approval = approvalDatasource,
       _entries = entryDatasource,
       _crypto = cryptoService,
       _sessions = sessionStore;

  final ApprovalRemoteDatasource _approval;
  final EntryRemoteDatasource _entries;
  final EntryV2CryptoService _crypto;
  final VaultSessionStore _sessions;

  @override
  Future<List<PendingGrant>> listPendingGrants() async {
    try {
      return (await _approval.listPendingGrants())
          .map((model) => model.toEntity())
          .toList(growable: false);
    } on DioException catch (error, stackTrace) {
      AppLogger.e(
        'Approval',
        'listPendingGrants failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw ApprovalException(_classifyError(error));
    }
  }

  @override
  Future<void> approveGrant({
    required PendingGrant grant,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) async {
    final wire = limit.toWire();
    try {
      final material = await _entryMaterial(grant.vaultId, grant.entryId);
      final fieldIds = grant.fieldIds.isEmpty
          ? _grantFieldIds(material.secret)
          : grant.fieldIds;
      final envelope = await _seal(
        material: material,
        grantId: grant.grantId,
        agentId: grant.agentId,
        agentPublicKey: grant.agentPublicKey,
        recipientKeyVersion: grant.recipientAgentKeyVersion,
        methods: methods,
        fieldIds: fieldIds,
        expiresAt: wire.expiresAt,
        remainingUses: wire.queryLimit,
      );
      await _approval.approveGrant(
        vaultId: grant.vaultId,
        grantId: grant.grantId,
        grantEntry: envelope,
        expiresAt: wire.expiresAt,
        queryLimit: wire.queryLimit,
        methods: serializeGrantMethods(methods),
      );
    } on DioException catch (error, stackTrace) {
      AppLogger.e(
        'Approval',
        'approve failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw ApprovalException(_classifyError(error));
    } on ApprovalException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.e(
        'Approval',
        'canonical approval failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw const ApprovalException(ApprovalErrorKind.cryptoFailure);
    }
  }

  @override
  Future<void> createGrant({
    required String vaultId,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required bool isFull,
    String? entryId,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) async {
    if (!isFull && entryId == null) {
      throw const ApprovalException(ApprovalErrorKind.validation);
    }
    final ids = isFull
        ? (await _entries.listEntriesV2(
            vaultId,
          )).map((row) => row['id'] as String).toList(growable: false)
        : <String>[entryId!];
    if (ids.isEmpty) {
      throw const ApprovalException(ApprovalErrorKind.validation);
    }

    final grantId = _uuidV4();
    final wire = limit.toWire();
    try {
      final envelopes = <Map<String, Object?>>[];
      for (final id in ids) {
        final material = await _entryMaterial(vaultId, id);
        final fieldIds = _grantFieldIds(material.secret);
        envelopes.add(
          await _seal(
            material: material,
            grantId: grantId,
            agentId: agentId,
            agentPublicKey: agentPublicKey,
            recipientKeyVersion: recipientKeyVersion,
            methods: methods,
            fieldIds: fieldIds,
            expiresAt: wire.expiresAt,
            remainingUses: wire.queryLimit,
          ),
        );
      }
      await _approval.createGrant(
        grantId: grantId,
        vaultId: vaultId,
        agentId: agentId,
        type: isFull ? 'full' : 'granular',
        entryId: isFull ? null : entryId,
        entries: envelopes,
        expiresAt: wire.expiresAt,
        queryLimit: wire.queryLimit,
        methods: serializeGrantMethods(methods),
      );
    } on DioException catch (error, stackTrace) {
      AppLogger.e(
        'Approval',
        'create grant failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw ApprovalException(_classifyError(error));
    } on ApprovalException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.e(
        'Approval',
        'canonical create grant failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw const ApprovalException(ApprovalErrorKind.cryptoFailure);
    }
  }

  @override
  Future<void> denyGrant({required PendingGrant grant, String? reason}) async {
    try {
      await _approval.denyGrant(
        vaultId: grant.vaultId,
        grantId: grant.grantId,
        reason: reason,
      );
    } on DioException catch (error) {
      throw ApprovalException(_classifyError(error));
    }
  }

  Future<_EntryMaterial> _entryMaterial(String vaultId, String entryId) async {
    final UnlockedVaultSession session;
    try {
      session = _sessions.session(vaultId);
    } on StateError {
      throw const ApprovalException(ApprovalErrorKind.vaultLocked);
    }
    final key = session.copyVaultKey();
    try {
      final detail = await _entries.getEntryV2(vaultId, entryId);
      final secret = await _crypto.openMemberSecret(
        entryKey: Map<String, dynamic>.from(detail['entryKey'] as Map),
        memberSecret: Map<String, dynamic>.from(detail['memberSecret'] as Map),
        vaultKey: key,
      );
      return _EntryMaterial(
        organizationId: session.organizationId,
        vaultId: vaultId,
        entryId: entryId,
        revision: int.parse(detail['currentRevision'] as String),
        memberKeyGeneration: session.memberKeyGeneration,
        secret: secret,
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<Map<String, Object?>> _seal({
    required _EntryMaterial material,
    required String grantId,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required List<GrantMethod> methods,
    required List<String> fieldIds,
    required String? expiresAt,
    required int? remainingUses,
  }) async {
    if (fieldIds.isEmpty) {
      throw const ApprovalException(ApprovalErrorKind.validation);
    }
    final publicKey = Uint8List.fromList(base64Decode(agentPublicKey));
    try {
      return await _crypto.sealGrant(
        organizationId: material.organizationId,
        vaultId: material.vaultId,
        entryId: material.entryId,
        grantId: grantId,
        agentId: agentId,
        entryRevision: material.revision,
        memberKeyGeneration: material.memberKeyGeneration,
        agentPublicKey: publicKey,
        recipientKeyVersion: recipientKeyVersion,
        approvedMethods: _methodBits(methods),
        fieldIds: fieldIds,
        grantPayload: VaultPlaintextProjector.grantPayloadFromJson(
          material.secret,
          fieldIds.toSet(),
        ),
        expiresAt: expiresAt == null ? null : DateTime.parse(expiresAt),
        remainingUses: remainingUses,
      );
    } finally {
      publicKey.fillRange(0, publicKey.length, 0);
    }
  }

  List<String> _grantFieldIds(Map<String, dynamic> secret) =>
      (Map<String, dynamic>.from(secret['agentFieldAccess'] as Map).entries
          .where(
            (entry) => const {
              'onGrantValue',
              'onGrantDerived',
              'onGrantRuntime',
            }.contains(entry.value),
          )
          .map((entry) => entry.key)
          .toList()
        ..sort());

  int _methodBits(List<GrantMethod> methods) =>
      methods.fold(0, (bits, method) => bits | (1 << method.index));

  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  ApprovalErrorKind _classifyError(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.error is SocketException) {
      return ApprovalErrorKind.networkError;
    }
    return switch (error.response?.statusCode) {
      404 => ApprovalErrorKind.notFound,
      403 => ApprovalErrorKind.forbidden,
      400 || 409 => ApprovalErrorKind.validation,
      _ => ApprovalErrorKind.unknown,
    };
  }
}

final class _EntryMaterial {
  const _EntryMaterial({
    required this.organizationId,
    required this.vaultId,
    required this.entryId,
    required this.revision,
    required this.memberKeyGeneration,
    required this.secret,
  });
  final String organizationId;
  final String vaultId;
  final String entryId;
  final int revision;
  final int memberKeyGeneration;
  final Map<String, dynamic> secret;
}
