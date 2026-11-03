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
import '../services/grant_entry_label_resolver.dart';
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
    GrantEntryLabelResolver? entryLabelResolver,
    VaultSessionStore? vaultSessionStore,
  }) : _reasonResolver = reasonResolver,
       _entryLabelResolver = entryLabelResolver,
       _vaultSessionStore = vaultSessionStore;

  final GrantsRemoteDatasource _dataSource;
  final GrantReasonResolver? _reasonResolver;
  final GrantEntryLabelResolver? _entryLabelResolver;
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
  Future<Grant> getGrant(String vaultId, String grantId) =>
      _getGrant(vaultId, grantId);

  Future<Grant> _getGrant(
    String vaultId,
    String grantId, {
    GrantReasonResolver? reasons,
    GrantEntryLabelResolver? entryLabels,
    bool Function()? isCurrent,
  }) async {
    if (isCurrent?.call() == false) {
      throw StateError('Grant presentation invalidated');
    }
    try {
      AppLogger.d('Grants', 'GET /api/vaults/$vaultId/grants/$grantId');
      final model = await _dataSource.getGrant(vaultId, grantId);
      if (isCurrent?.call() == false) {
        throw StateError('Grant presentation invalidated');
      }
      final result = (await _toEntities(
        [model],
        reasons: reasons,
        entryLabels: entryLabels,
      )).single;
      if (isCurrent?.call() == false) {
        throw StateError('Grant presentation invalidated');
      }
      return result;
    } on DioException catch (e, s) {
      AppLogger.e('Grants', 'getGrant failed', error: e, stackTrace: s);
      throw GrantsException(_classifyError(e));
    }
  }

  @override
  Future<T> withPresentationReads<T>(
    Future<T> Function(GrantReader read) operation,
  ) async {
    final generation = _vaultSessionStore?.memberKeySessionGeneration;
    var active = true;
    final pending = <Future<void>>[];
    bool isCurrent() =>
        active && _vaultSessionStore?.memberKeySessionGeneration == generation;
    Future<T> withLabels(GrantReasonResolver? reasons) {
      Future<T> run(GrantEntryLabelResolver? labels) async {
        try {
          return await operation((vaultId, grantId) {
            final result = _getGrant(
              vaultId,
              grantId,
              reasons: reasons,
              entryLabels: labels,
              isCurrent: isCurrent,
            );
            pending.add(
              result.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
            );
            return result;
          });
        } finally {
          active = false;
          await Future.wait(pending);
        }
      }

      final labels = _entryLabelResolver;
      return labels == null ? run(null) : labels.withSharedReads(run);
    }

    final reasons = _reasonResolver;
    return await (reasons == null
        ? withLabels(null)
        : reasons.withSharedReads(withLabels));
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

  Future<List<Grant>> _toEntities(
    List<GrantModel> models, {
    GrantReasonResolver? reasons,
    GrantEntryLabelResolver? entryLabels,
  }) async {
    final session = _vaultSessionStore;
    if (session == null || models.isEmpty) {
      return models.map((model) => model.toEntity()).toList(growable: false);
    }

    Uint8List? memberPrivateKey;
    int? memberKeySessionGeneration;
    var resolvedReasons = const <String, String>{};
    var resolvedEntryLabels = const <GrantEntryLabelTarget, String>{};
    try {
      memberKeySessionGeneration = session.memberKeySessionGeneration;
      memberPrivateKey = session.copyMemberPrivateKey();
      final reasonResolver = reasons ?? _reasonResolver;
      if (reasonResolver != null) {
        try {
          resolvedReasons = await reasonResolver.resolve(
            grants: models,
            memberPrivateKey: memberPrivateKey,
          );
        } catch (error) {
          AppLogger.w(
            'Grants',
            'Grant reason projection unavailable (${error.runtimeType})',
          );
        }
      }
      final entryLabelResolver = entryLabels ?? _entryLabelResolver;
      if (entryLabelResolver != null) {
        try {
          resolvedEntryLabels = await entryLabelResolver.resolve(
            grants: models,
            memberPrivateKey: memberPrivateKey,
            isSessionCurrent: () =>
                session.memberKeySessionGeneration ==
                memberKeySessionGeneration,
          );
        } catch (_) {
          AppLogger.w('Grants', 'Grant Entry label projection unavailable');
        }
      }
    } catch (_) {
      AppLogger.w('Grants', 'Local Grant presentation unavailable');
    } finally {
      memberPrivateKey?.fillRange(0, memberPrivateKey.length, 0);
    }
    final projectionIsCurrent =
        memberKeySessionGeneration != null &&
        session.memberKeySessionGeneration == memberKeySessionGeneration;
    return models
        .map((model) {
          final entryTarget = GrantEntryLabelResolver.targetFor(model);
          return model.toEntity(
            resolvedReason: projectionIsCurrent
                ? resolvedReasons[model.id]
                : null,
            resolvedEntryLabel: !projectionIsCurrent || entryTarget == null
                ? null
                : resolvedEntryLabels[entryTarget],
          );
        })
        .toList(growable: false);
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
