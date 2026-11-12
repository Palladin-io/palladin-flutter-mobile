import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../grants/data/datasources/grants_remote_datasource.dart';
import '../../unlock/data/services/identity_kdf_service.dart';
import '../../unlock/data/services/unlock_crypto_service.dart';
import '../../vault/data/datasources/entry_remote_datasource.dart';
import '../../vault/data/datasources/member_sync_remote_datasource.dart';
import '../../vault/data/datasources/vault_remote_datasource.dart';
import '../../vault/data/models/member_sync_models.dart';
import '../../vault/data/services/canonical_entry_detail_service.dart';
import '../../vault/data/services/entry_v2_crypto_service.dart';
import '../../vault/data/services/local_current_entry_service.dart';
import '../../vault/data/services/member_sync_cache.dart';
import '../../vault/data/services/member_sync_service.dart';
import '../../vault/data/services/member_sync_session_authority_provider.dart';
import '../../vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import '../../vault/data/services/vault_rotation_crypto_service.dart';
import '../../vault/domain/entities/vault_performance_budget.dart';
import 'autofill_credential_source.dart';
import 'autofill_extension_session.dart';
import 'autofill_mutation_notifier.dart';
import 'autofill_request_controller.dart';

enum IosMemberSourceFailure { unavailable, invalidated, networkDisabled }

final class IosMemberSourceException implements Exception {
  const IosMemberSourceException(this.kind);
  final IosMemberSourceFailure kind;
}

/// A read-only canonical-source session for one native credential request.
/// No app bootstrap, account storage, analytics or network client is started.
final class IosMemberSourceRuntime {
  IosMemberSourceRuntime._(this._database, this._memberSync, this._offlineDio);

  final Database _database;
  final MemberSyncService _memberSync;
  final Dio _offlineDio;
  late final AutoFillExtensionSession session;
  bool _closed = false;
  int _revision = 0;

  static Future<IosMemberSourceRuntime> open({
    required Map<dynamic, dynamic> arguments,
    required Future<bool> Function() validateNative,
    required Future<void> Function(Map<String, Object?>) completeNative,
    EntryV2CryptoService? entryCrypto,
  }) async {
    final incomingKey = arguments.remove('masterKey');
    final password = arguments.remove('masterPassword');
    Database? database;
    IosMemberSourceRuntime? runtime;
    UnlockResult? unlocked;
    Dio? offlineDio;
    try {
      if (!await validateNative()) {
        throw const IosMemberSourceException(
          IosMemberSourceFailure.invalidated,
        );
      }
      final databasePath = arguments['databasePath'];
      if (databasePath is! String ||
          !path.isAbsolute(databasePath) ||
          path.basename(databasePath) != 'vault_member_sync.db' ||
          await FileSystemEntity.type(databasePath, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const IosMemberSourceException(
          IosMemberSourceFailure.unavailable,
        );
      }
      database = await openDatabase(
        databasePath,
        readOnly: true,
        singleInstance: false,
      );
      if (await database.getVersion() != 2) {
        throw const IosMemberSourceException(
          IosMemberSourceFailure.unavailable,
        );
      }
      final request = AutoFillRequest.parse(arguments['request'] as Map);
      final rawClaims = arguments['claims'] as Map;
      final claims = MemberSyncSessionAuthority(
        principalId: rawClaims['principalId'] as String,
        organizationId: rawClaims['organizationId'] as String,
        organizationMembershipGeneration:
            rawClaims['organizationMembershipGeneration'] as String,
        offlinePolicy: rawClaims['offlinePolicy'] as String,
        offlinePolicyVersion: rawClaims['offlinePolicyVersion'] as int,
      );
      final account = arguments['accountUnlock'] as Map;
      if (account['accountId'] != claims.principalId ||
          ((incomingKey is Uint8List) == (password is String))) {
        throw const IosMemberSourceException(
          IosMemberSourceFailure.unavailable,
        );
      }
      final unlock = UnlockCryptoService();
      if (incomingKey is Uint8List) {
        if (incomingKey.length != 32) {
          throw const IosMemberSourceException(
            IosMemberSourceFailure.unavailable,
          );
        }
        unlocked = await unlock.decryptWithMasterKey(
          masterKey: incomingKey,
          encryptedPrivateKeyBase64: account['encryptedPrivateKey'] as String,
        );
      } else {
        unlocked = await unlock.deriveAndDecrypt(
          masterPassword: password as String,
          accountId: account['accountId'] as String,
          kdf: IdentityKdfMetadata.fromJson(
            Map<String, dynamic>.from(account['kdf'] as Map),
          ),
          encryptedPrivateKeyBase64: account['encryptedPrivateKey'] as String,
        );
      }
      final crypto = entryCrypto ?? EntryV2CryptoService();
      final vaultKeys = VaultRotationCryptoService();
      final cache = SqliteMemberSyncCache(
        databaseLoader: () async => database!,
      );
      final sync = MemberSyncService(
        remote: const _OfflineMemberRemote(),
        cache: cache,
        entryCrypto: crypto,
        vaultKeys: vaultKeys,
      );
      offlineDio = Dio()..httpClientAdapter = _OfflineHttpAdapter();
      runtime = IosMemberSourceRuntime._(database, sync, offlineDio);
      final owner = runtime;
      Future<bool> validate() async {
        if (owner._closed || !await validateNative() || owner._closed) {
          owner._invalidate();
          return false;
        }
        return true;
      }

      final authority = MemberSyncSessionAuthorityProvider.independent(
        readClaims: () async {
          if (!await validate()) {
            throw const IosMemberSourceException(
              IosMemberSourceFailure.invalidated,
            );
          }
          return claims;
        },
        sessionRevision: () => owner._revision,
      );
      final localEntries = LocalCurrentEntryService(
        reader: sync,
        authorityProvider: authority,
        vaultKeys: vaultKeys,
        entryCrypto: crypto,
        canonicalAdapter: CanonicalEntryDetailService(
          entries: EntryRemoteDatasource(offlineDio),
          vaults: VaultRemoteDatasource(offlineDio),
          keys: vaultKeys,
          envelopes: VaultProtocolEnvelopeService(),
          grants: GrantsRemoteDatasource(offlineDio),
          entryV2: crypto,
          autoFillMutationNotifier: AutoFillMutationNotifier(),
        ),
      );
      final vaultIds = await sync.unlockAllCached(
        memberPrivateKey: unlocked.privateKey,
        authority: await authority.current(),
      );
      if (!await validate()) {
        throw const IosMemberSourceException(
          IosMemberSourceFailure.invalidated,
        );
      }
      owner.session = AutoFillExtensionSession(
        request: request,
        source: AutoFillCredentialSource(
          memberIndex: sync,
          localEntries: localEntries,
        ),
        vaultIds: vaultIds,
        memberPrivateKey: unlocked.privateKey,
        validateNative: validate,
        completeNative: completeNative,
        clearRuntime: owner._invalidate,
      );
      return owner;
    } catch (_) {
      runtime?._invalidate();
      await database?.close();
      offlineDio?.close(force: true);
      throw const IosMemberSourceException(IosMemberSourceFailure.unavailable);
    } finally {
      if (incomingKey is Uint8List) {
        incomingKey.fillRange(0, incomingKey.length, 0);
      }
      unlocked?.masterKey.fillRange(0, unlocked.masterKey.length, 0);
      unlocked?.privateKey.fillRange(0, unlocked.privateKey.length, 0);
    }
  }

  void _invalidate() {
    if (_closed) return;
    _closed = true;
    _revision++;
    _memberSync.lock();
  }

  Future<void> close() async {
    session.close();
    _invalidate();
    await _database.close();
    _offlineDio.close(force: true);
  }
}

final class _OfflineMemberRemote implements MemberSyncRemote {
  const _OfflineMemberRemote();
  @override
  Future<MemberSnapshotPage> snapshot({
    required String vaultId,
    String? cursor,
    int pageSize = VaultPerformanceBudget.memberSyncPageItems,
  }) async => throw const IosMemberSourceException(
    IosMemberSourceFailure.networkDisabled,
  );
  @override
  Future<MemberDeltaResult> delta({
    required String vaultId,
    String? afterSequence,
    String? continuationCursor,
    int pageSize = VaultPerformanceBudget.memberSyncPageItems,
  }) async => throw const IosMemberSourceException(
    IosMemberSourceFailure.networkDisabled,
  );
}

final class _OfflineHttpAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw const IosMemberSourceException(
    IosMemberSourceFailure.networkDisabled,
  );
}
