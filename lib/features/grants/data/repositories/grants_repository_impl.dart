import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/crypto/vault_session_store.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/grant.dart';
import '../../domain/exceptions/grants_exceptions.dart';
import '../../domain/repositories/grants_repository.dart';
import '../datasources/grants_remote_datasource.dart';
import '../models/grant_model.dart';
import '../services/grant_reason_resolver.dart';

/// Concrete implementation of [GrantsRepository].
///
/// Wraps [GrantsRemoteDatasource] and translates DioExceptions into typed
/// [GrantsException]s so the presentation layer can render localized
/// errors. Maps DTOs to domain entities at the boundary.
class GrantsRepositoryImpl implements GrantsRepository {
  GrantsRepositoryImpl(
    this._dataSource, {
    GrantReasonResolver? reasonResolver,
    VaultSessionStore? vaultSessionStore,
  }) : _reasonResolver = reasonResolver,
       _vaultSessionStore = vaultSessionStore;

  final GrantsRemoteDatasource _dataSource;
  final GrantReasonResolver? _reasonResolver;
  final VaultSessionStore? _vaultSessionStore;

  @override
  Future<GrantListPage> listGrants(
    String vaultId, {
    String? status,
    String? agentId,
    String? cursor,
    int pageSize = 20,
  }) async {
    try {
      AppLogger.d('Grants', 'GET /api/vaults/$vaultId/grants');
      final page = await _dataSource.listGrants(
        vaultId,
        status: status,
        agentId: agentId,
        cursor: cursor,
        pageSize: pageSize,
      );
      return GrantListPage(
        grants: await _toEntities(page.grants),
        nextCursor: page.nextCursor,
      );
    } on DioException catch (e, s) {
      AppLogger.e('Grants', 'listGrants failed', error: e, stackTrace: s);
      throw GrantsException(_classifyError(e));
    }
  }

  @override
  Future<GrantListPage> listOrgGrants({
    String? status,
    String? agentId,
    String? vaultId,
    String? entryId,
    String? query,
    String? cursor,
    int pageSize = 50,
  }) async {
    try {
      AppLogger.d('Grants', 'GET /api/grants');
      final page = await _dataSource.listOrgGrants(
        status: status,
        agentId: agentId,
        vaultId: vaultId,
        entryId: entryId,
        query: query,
        cursor: cursor,
        pageSize: pageSize,
      );
      return GrantListPage(
        grants: await _toEntities(page.grants),
        nextCursor: page.nextCursor,
      );
    } on DioException catch (e, s) {
      AppLogger.e('Grants', 'listOrgGrants failed', error: e, stackTrace: s);
      throw GrantsException(_classifyError(e));
    }
  }

  @override
  Future<Grant> getGrant(String vaultId, String grantId) async {
    try {
      AppLogger.d('Grants', 'GET /api/vaults/$vaultId/grants/$grantId');
      final model = await _dataSource.getGrant(vaultId, grantId);
      return (await _toEntities([model])).single;
    } on DioException catch (e, s) {
      AppLogger.e('Grants', 'getGrant failed', error: e, stackTrace: s);
      throw GrantsException(_classifyError(e));
    }
  }

  @override
  Future<void> revokeGrant(String vaultId, String grantId) async {
    try {
      AppLogger.d('Grants', 'DELETE /api/vaults/$vaultId/grants/$grantId');
      await _dataSource.revokeGrant(vaultId, grantId);
    } on DioException catch (e, s) {
      AppLogger.e('Grants', 'revokeGrant failed', error: e, stackTrace: s);
      throw GrantsException(_classifyError(e));
    }
  }

  Future<List<Grant>> _toEntities(List<GrantModel> models) async {
    final resolver = _reasonResolver;
    final session = _vaultSessionStore;
    if (resolver == null || session == null || models.isEmpty) {
      return models.map((model) => model.toEntity()).toList(growable: false);
    }

    Uint8List? memberPrivateKey;
    try {
      memberPrivateKey = session.copyMemberPrivateKey();
      final reasons = await resolver.resolve(
        grants: models,
        memberPrivateKey: memberPrivateKey,
      );
      return models
          .map((model) => model.toEntity(resolvedReason: reasons[model.id]))
          .toList(growable: false);
    } catch (error) {
      // History remains usable when the Vault is locked or one reason cannot
      // be opened. Do not log error payloads: crypto failures may retain input.
      AppLogger.w(
        'Grants',
        'Grant reason projection unavailable (${error.runtimeType})',
      );
      return models.map((model) => model.toEntity()).toList(growable: false);
    } finally {
      memberPrivateKey?.fillRange(0, memberPrivateKey.length, 0);
    }
  }

  /// Maps a [DioException] to a typed [GrantsErrorKind].
  GrantsErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return GrantsErrorKind.networkError;
    }

    return switch (e.response?.statusCode) {
      404 => GrantsErrorKind.notFound,
      403 => GrantsErrorKind.forbidden,
      400 || 409 => GrantsErrorKind.validation,
      _ => GrantsErrorKind.unknown,
    };
  }
}
