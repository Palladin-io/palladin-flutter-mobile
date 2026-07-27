import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../../core/crypto/vault_session_store.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../autofill/data/autofill_mutation_notifier.dart';
import '../../../unlock/data/datasources/account_remote_datasource.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/entities/vault_plaintext.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../../domain/repositories/vault_repository.dart';
import '../datasources/vault_remote_datasource.dart';
import '../models/create_vault_request.dart' show UpdateVaultRequest;
import '../services/vault_crypto_service.dart';

/// Concrete implementation of [VaultRepository].
///
/// Wraps [VaultRemoteDatasource] and translates DioExceptions into
/// typed [VaultException]s with semantic [VaultErrorKind] values so
/// the presentation layer can render localized error messages.
class VaultRepositoryImpl implements VaultRepository {
  VaultRepositoryImpl(
    this._datasource, {
    this.authRepository,
    this.accountDatasource,
    this.cryptoService,
    this.sessionStore,
    this.autoFillMutationNotifier,
  });

  final VaultRemoteDatasource _datasource;
  final AuthRepository? authRepository;
  final AccountRemoteDatasource? accountDatasource;
  final VaultCryptoService? cryptoService;
  final VaultSessionStore? sessionStore;
  final AutoFillMutationNotifier? autoFillMutationNotifier;

  @override
  Future<List<VaultEntity>> listVaults() async {
    try {
      AppLogger.d('Vault', 'GET /api/vaults');
      final models = await _datasource.listVaults();
      final privateKey = sessionStore?.copyMemberPrivateKey();
      if (privateKey == null || cryptoService == null || sessionStore == null) {
        throw const VaultException(VaultErrorKind.unknown);
      }
      try {
        final result = <VaultEntity>[];
        for (final model in models) {
          result.add(await _openProjection(model, privateKey));
        }
        return result;
      } finally {
        privateKey.fillRange(0, privateKey.length, 0);
      }
    } on DioException catch (e, s) {
      AppLogger.e('Vault', 'listVaults failed', error: e, stackTrace: s);
      throw VaultException(_classifyError(e));
    }
  }

  @override
  Future<VaultEntity> getVault(String id) async {
    try {
      AppLogger.d('Vault', 'GET /api/vaults/$id');
      final model = await _datasource.getVault(id);
      final privateKey = sessionStore?.copyMemberPrivateKey();
      if (privateKey == null) {
        throw const VaultException(VaultErrorKind.unknown);
      }
      try {
        return await _openProjection(model, privateKey);
      } finally {
        privateKey.fillRange(0, privateKey.length, 0);
      }
    } on DioException catch (e, s) {
      AppLogger.e('Vault', 'getVault failed', error: e, stackTrace: s);
      throw VaultException(_classifyError(e));
    }
  }

  Future<VaultEntity> _openProjection(
    Map<String, dynamic> model,
    Uint8List privateKey,
  ) async {
    final opened = await cryptoService!.openVaultProjection(
      json: model,
      memberPrivateKey: privateKey,
    );
    try {
      sessionStore!.install(
        organizationId: opened.organizationId,
        vaultId: opened.vaultId,
        vaultKey: opened.vaultKey,
        vaultDiscoveryKey: opened.vaultDiscoveryKey,
        epoch: VaultKeyEpoch(
          vaultKeyVersion: opened.epoch.vaultKeyVersion,
          vdkVersion: opened.epoch.vdkVersion,
          agentMessageKeyVersion: opened.epoch.agentMessageKeyVersion,
          manifestSigningKeyVersion: opened.epoch.manifestSigningKeyVersion,
        ),
        memberKeyGeneration: opened.memberKeyGeneration,
        wrapper: opened.wrapper,
      );
      final icon = opened.metadata.icon;
      return VaultEntity(
        id: opened.vaultId,
        name: opened.metadata.name,
        description: opened.metadata.description,
        icon: icon is GlyphVaultIcon ? icon.value : null,
        color: opened.metadata.color,
        grantMode: opened.metadata.grantMode == 'full'
            ? GrantMode.full
            : GrantMode.granular,
        createdAt: DateTime.parse(model['createdAt'] as String),
        updatedAt: DateTime.parse(model['updatedAt'] as String),
        entryCount: (model['entryCount'] as int?) ?? 0,
        activeGrantCount: (model['activeGrantCount'] as int?) ?? 0,
        memberCount: (model['memberCount'] as int?) ?? 1,
      );
    } finally {
      opened.vaultKey.fillRange(0, opened.vaultKey.length, 0);
      opened.vaultDiscoveryKey?.fillRange(
        0,
        opened.vaultDiscoveryKey!.length,
        0,
      );
    }
  }

  @override
  Future<VaultEntity> createVault({
    required String name,
    String? description,
    String? icon,
    String? color,
    required GrantMode grantMode,
    required Uint8List privateKey,
  }) async {
    CreatedVaultBundle? bundle;
    try {
      AppLogger.d('Vault', 'POST /api/vaults');
      final organizationId = await authRepository?.getOrganizationId();
      final account = await accountDatasource?.getAccount();
      final memberId = account?.userId;
      final memberKeyVersion = account?.memberKeyVersion;
      if (organizationId == null ||
          memberId == null ||
          memberKeyVersion == null) {
        throw const VaultException(VaultErrorKind.unknown);
      }
      final challenge = await _datasource.issueCreationChallenge();
      final crypto = cryptoService;
      final sessions = sessionStore;
      if (crypto == null || sessions == null) {
        throw const VaultException(VaultErrorKind.unknown);
      }
      bundle = await crypto.createVaultBundle(
        organizationId: organizationId,
        memberId: memberId,
        memberKeyVersion: memberKeyVersion,
        vaultId: challenge.vaultId,
        memberPrivateKey: privateKey,
        name: name,
        description: description,
        icon: icon,
        color: color,
        grantMode: grantMode,
      );
      final response = await _datasource.createVault(bundle.request);
      sessions.install(
        organizationId: organizationId,
        vaultId: challenge.vaultId,
        vaultKey: bundle.vaultKey,
        vaultDiscoveryKey: bundle.vaultDiscoveryKey,
        epoch: const VaultKeyEpoch(
          vaultKeyVersion: 1,
          vdkVersion: 1,
          agentMessageKeyVersion: 1,
          manifestSigningKeyVersion: 1,
        ),
        memberKeyGeneration: 1,
        wrapper: MemberVaultKeyWrapperMetadata(
          wrapperSuiteId: 'palladin-x25519-sealed-box-v1',
          wrappedKeyVersion: 1,
          memberKeyGeneration: 1,
          recipientKeyVersion: memberKeyVersion,
          recipientFingerprint: bundle.memberFingerprint,
        ),
      );
      autoFillMutationNotifier?.notifyChanged();
      return VaultEntity(
        id: challenge.vaultId,
        name: bundle.metadata.name,
        description: bundle.metadata.description,
        icon: icon,
        color: bundle.metadata.color,
        grantMode: grantMode,
        createdAt: DateTime.parse(response['createdAt'] as String),
        updatedAt: DateTime.parse(response['updatedAt'] as String),
        entryCount: 0,
        activeGrantCount: 0,
        memberCount: 1,
      );
    } on DioException catch (e, s) {
      AppLogger.e('Vault', 'createVault failed', error: e, stackTrace: s);
      throw VaultException(_classifyError(e));
    } finally {
      bundle?.vaultKey.fillRange(0, bundle.vaultKey.length, 0);
      bundle?.vaultDiscoveryKey.fillRange(
        0,
        bundle.vaultDiscoveryKey.length,
        0,
      );
    }
  }

  @override
  Future<void> updateVault(
    String id, {
    String? name,
    String? description,
    String? icon,
    String? color,
    GrantMode? grantMode,
  }) async {
    try {
      AppLogger.d('Vault', 'PUT /api/vaults/$id');
      await _datasource.updateVault(
        id,
        UpdateVaultRequest(
          name: name,
          description: description,
          icon: icon,
          color: color,
          grantMode: grantMode,
        ),
      );
    } on DioException catch (e, s) {
      AppLogger.e('Vault', 'updateVault failed', error: e, stackTrace: s);
      throw VaultException(_classifyError(e));
    }
  }

  @override
  Future<void> deleteVault(String id) async {
    try {
      AppLogger.d('Vault', 'DELETE /api/vaults/$id');
      await _datasource.deleteVault(id);
      autoFillMutationNotifier?.notifyChanged();
    } on DioException catch (e, s) {
      AppLogger.e('Vault', 'deleteVault failed', error: e, stackTrace: s);
      throw VaultException(_classifyError(e));
    }
  }

  /// Maps a [DioException] to a typed [VaultErrorKind].
  ///
  /// 403 responses are inspected to disambiguate plan-limit and
  /// full-mode-not-allowed errors via the `errorCode` / `code` field
  /// returned by the .NET API. Falls back to plain [VaultErrorKind.forbidden]
  /// when the body has no machine-readable hint.
  VaultErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return VaultErrorKind.networkError;
    }

    final status = e.response?.statusCode;
    if (status == 404) {
      return VaultErrorKind.notFound;
    }
    if (status == 403) {
      final code = _extractErrorCode(e.response?.data);
      if (code == null) return VaultErrorKind.forbidden;
      if (code.contains('plan') && code.contains('limit')) {
        return VaultErrorKind.planLimitReached;
      }
      if (code.contains('full') && code.contains('mode')) {
        return VaultErrorKind.fullModeNotAllowed;
      }
      return VaultErrorKind.forbidden;
    }

    return VaultErrorKind.unknown;
  }

  /// Extracts a normalized lowercase error code from a 403 response
  /// body. Backend conventions vary — checks both `errorCode` and
  /// `code` and falls back to a `message` substring scan so the
  /// classification is resilient to small backend changes.
  String? _extractErrorCode(dynamic body) {
    if (body is Map<String, dynamic>) {
      final code = body['errorCode'] ?? body['code'] ?? body['error'];
      if (code is String) return code.toLowerCase();
      final message = body['message'] ?? body['detail'];
      if (message is String) return message.toLowerCase();
    }
    if (body is String) return body.toLowerCase();
    return null;
  }
}
