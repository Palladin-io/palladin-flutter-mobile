import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../../core/crypto/vault_session_store.dart';
import '../../../autofill/data/autofill_mutation_notifier.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/import_draft.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../../domain/repositories/entry_repository.dart';
import '../datasources/entry_remote_datasource.dart';
import '../datasources/vault_remote_datasource.dart';
import '../models/entry_v2_contracts.dart';
import '../services/entry_crypto_service.dart';
import '../services/entry_v2_crypto_service.dart';
import '../../domain/entities/vault_plaintext.dart';

/// Concrete implementation of [EntryRepository].
///
/// Responsibilities:
///   * Translates DioExceptions into typed [EntryException]s so the
///     presentation layer can render localized error messages.
///   * Owns the wrappedVK lifecycle — fetches it from the vault
///     datasource, hands it to [EntryCryptoService.unwrapVK] to derive
///     the VK, and zeroes the plaintext VK in `finally`.
///   * Never lets plaintext VK leak above the data layer.
class EntryRepositoryImpl implements EntryRepository {
  EntryRepositoryImpl({
    required this.entryDatasource,
    required this.vaultDatasource,
    required this.cryptoService,
    this.entryV2CryptoService,
    this.sessionStore,
    this.autoFillMutationNotifier,
  });

  final EntryRemoteDatasource entryDatasource;
  final VaultRemoteDatasource vaultDatasource;
  final EntryCryptoService cryptoService;
  final EntryV2CryptoService? entryV2CryptoService;
  final VaultSessionStore? sessionStore;
  final AutoFillMutationNotifier? autoFillMutationNotifier;

  @override
  Future<List<EntryEntity>> listEntries(String vaultId) async {
    Uint8List? vaultKey;
    try {
      AppLogger.d('Entry', 'GET /api/vaults/$vaultId/entries');
      final session = sessionStore?.session(vaultId);
      final v2Crypto = entryV2CryptoService;
      if (session == null || v2Crypto == null) {
        throw const EntryException(EntryErrorKind.cryptoFailure);
      }
      vaultKey = session.copyVaultKey();
      final rows = await entryDatasource.listEntriesV2(vaultId);
      final result = <EntryEntity>[];
      for (final row in rows) {
        final index = await v2Crypto.openMemberIndex(
          envelope: Map<String, dynamic>.from(row['memberIndex'] as Map),
          vaultKey: vaultKey,
        );
        final icon = index['icon'];
        result.add(
          EntryEntity(
            id: row['id'] as String,
            vaultId: vaultId,
            label: index['memberLabel'] as String,
            description: index['description'] as String?,
            icon: icon is Map && icon['kind'] == 'glyph'
                ? icon['value'] as String?
                : null,
            type: switch (index['entryType']) {
              'key' => EntryType.key,
              'credential' => EntryType.credential,
              'script' => EntryType.script,
              _ => throw const EntryException(EntryErrorKind.cryptoFailure),
            },
            urlDomain: index['urlDomain'] as String?,
            createdAt: DateTime.parse(row['createdAt'] as String),
            updatedAt: DateTime.parse(row['updatedAt'] as String),
          ),
        );
      }
      return result;
    } on DioException catch (e, s) {
      AppLogger.e('Entry', 'listEntries failed', error: e, stackTrace: s);
      throw EntryException(_classifyError(e));
    } finally {
      vaultKey?.fillRange(0, vaultKey.length, 0);
    }
  }

  @override
  Future<void> deleteEntry({
    required String vaultId,
    required String entryId,
  }) async {
    try {
      AppLogger.d('Entry', 'DELETE /api/vaults/$vaultId/entries/$entryId');
      await entryDatasource.deleteEntry(vaultId, entryId);
      autoFillMutationNotifier?.notifyChanged();
    } on DioException catch (e, s) {
      AppLogger.e('Entry', 'deleteEntry failed', error: e, stackTrace: s);
      throw EntryException(_classifyError(e));
    }
  }

  @override
  Future<RevealedEntry> revealEntry({
    required String vaultId,
    required String entryId,
    required Uint8List privateKey,
    String? wrappedVK,
  }) async {
    AppLogger.d('Entry', 'Revealing entry id=$entryId');
    Uint8List? vaultKey;
    try {
      final session = sessionStore?.session(vaultId);
      final v2Crypto = entryV2CryptoService;
      if (session == null || v2Crypto == null) {
        throw const EntryException(EntryErrorKind.cryptoFailure);
      }
      vaultKey = session.copyVaultKey();
      final detail = await entryDatasource.getEntryV2(vaultId, entryId);
      final secret = await v2Crypto.openMemberSecret(
        entryKey: Map<String, dynamic>.from(detail['entryKey'] as Map),
        memberSecret: Map<String, dynamic>.from(detail['memberSecret'] as Map),
        vaultKey: vaultKey,
      );
      return RevealedEntry(
        entry: _entityFromSecret(
          vaultId: vaultId,
          detail: detail,
          secret: secret,
        ),
        payload: _legacyPayload(secret),
      );
    } finally {
      if (vaultKey != null) {
        vaultKey.fillRange(0, vaultKey.length, 0);
      }
    }
  }

  EntryEntity _entityFromSecret({
    required String vaultId,
    required Map<String, dynamic> detail,
    required Map<String, dynamic> secret,
  }) {
    final type = _entryType(secret['entryType']);
    final content = Map<String, dynamic>.from(secret['content'] as Map);
    final icon = secret['icon'];
    return EntryEntity(
      id: detail['id'] as String,
      vaultId: vaultId,
      label: secret['memberLabel'] as String,
      description: secret['description'] as String?,
      icon: icon is Map && icon['kind'] == 'glyph'
          ? icon['value'] as String?
          : null,
      type: type,
      urlDomain: type == EntryType.credential
          ? content['urlDomain'] as String?
          : null,
      createdAt: DateTime.parse(detail['createdAt'] as String),
      updatedAt: DateTime.parse(detail['updatedAt'] as String),
    );
  }

  Map<String, dynamic> _legacyPayload(Map<String, dynamic> secret) {
    final type = _entryType(secret['entryType']);
    final content = Map<String, dynamic>.from(secret['content'] as Map);
    final fields = (content['customFields'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) {
          final field = Map<String, dynamic>.from(raw);
          return <String, dynamic>{
            'id': (field['id'] as String).replaceFirst('custom:', ''),
            'label': field['label'],
            'type': field['kind'],
            'value': field['value'],
          };
        })
        .toList(growable: false);
    return switch (type) {
      EntryType.key => {
        'v': 2,
        'type': 'KEY',
        'value': content['value'],
        'notes': content['notes'],
        'fields': fields,
      },
      EntryType.credential => {
        'v': 2,
        'type': 'CREDENTIAL',
        'username': content['username'],
        'password': content['password'],
        'url': content['url'],
        'notes': content['notes'],
        'totp': content['totp'] is String
            ? content['totp']
            : content['totp'] == null
            ? null
            : jsonEncode(content['totp']),
        'fields': fields,
      },
      EntryType.script => {
        'v': 2,
        'type': 'SCRIPT',
        'script': content['source'],
        'interpreter': content['interpreter'],
        'notes': content['notes'],
        'refs': (content['refs'] as List<dynamic>? ?? const [])
            .map((raw) {
              final ref = Map<String, dynamic>.from(raw as Map);
              return {
                'env': ref['env'],
                'vaultId': ref['vaultId'],
                'entryId': ref['entryId'],
                'field': ref['fieldId'],
              };
            })
            .toList(growable: false),
        'fields': fields,
      },
    };
  }

  EntryType _entryType(Object? value) => switch (value) {
    'key' => EntryType.key,
    'credential' => EntryType.credential,
    'script' => EntryType.script,
    _ => throw const EntryException(EntryErrorKind.cryptoFailure),
  };

  @override
  Future<EntryEntity> createEntryEncrypted({
    required String vaultId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required Map<String, dynamic> payload,
    String? urlDomain,
    required Uint8List privateKey,
    String? wrappedVK,
    List<AgentField>? agentFields,
  }) async {
    AppLogger.d('Entry', 'Creating protocol-v2 entry in vault $vaultId');
    final session = sessionStore?.session(vaultId);
    final v2Crypto = entryV2CryptoService;
    if (session == null || v2Crypto == null) {
      throw const EntryException(EntryErrorKind.cryptoFailure);
    }
    final vaultKey = session.copyVaultKey();
    final discoveryKey = session.copyVaultDiscoveryKey();
    try {
      final challenges = await entryDatasource.issueCreationChallenges(vaultId);
      if (challenges.length != 1) {
        throw const EntryException(EntryErrorKind.cryptoFailure);
      }
      final challenge = challenges.single;
      final secret = _memberSecret(
        label: label,
        description: description,
        icon: icon,
        type: type,
        payload: payload,
        urlDomain: urlDomain,
      );
      final envelopes = await v2Crypto.seal(
        organizationId: session.organizationId,
        vaultId: vaultId,
        entryId: challenge.entryId,
        revision: 1,
        vaultKeyVersion: session.epoch.vaultKeyVersion,
        vdkVersion: session.epoch.vdkVersion,
        memberKeyGeneration: session.memberKeyGeneration,
        operation: 1,
        secret: secret,
        vaultKey: vaultKey,
        vaultDiscoveryKey: discoveryKey,
      );
      final response = await entryDatasource.createEntryV2(
        vaultId,
        CreateEntryV2Request(
          vaultId: vaultId,
          entryId: challenge.entryId,
          envelopes: envelopes,
        ),
      );
      autoFillMutationNotifier?.notifyChanged();
      final now = DateTime.now().toUtc();
      return EntryEntity(
        id: (response['id'] as String?) ?? challenge.entryId,
        vaultId: vaultId,
        label: label,
        description: description,
        icon: icon,
        type: type,
        urlDomain: urlDomain,
        createdAt: now,
        updatedAt: now,
      );
    } finally {
      vaultKey.fillRange(0, vaultKey.length, 0);
      discoveryKey.fillRange(0, discoveryKey.length, 0);
    }
  }

  MemberSecret _memberSecret({
    required String label,
    required String? description,
    required String? icon,
    required EntryType type,
    required Map<String, dynamic> payload,
    String? urlDomain,
  }) {
    final sourceFields = CustomField.listFromPayload(payload);
    final fields = sourceFields
        .map(
          (field) => VaultCustomField(
            id: field.id,
            label: field.label,
            kind: field.rawType,
            value: field.value,
          ),
        )
        .toList(growable: false);
    final content = switch (type) {
      EntryType.key => KeySecretContent(
        value: (payload['value'] as String?) ?? '',
        notes: payload['notes'] as String?,
        customFields: fields,
      ),
      EntryType.credential => CredentialSecretContent(
        username: (payload['username'] as String?) ?? '',
        password: (payload['password'] as String?) ?? '',
        url: payload['url'] as String?,
        urlDomain: urlDomain ?? payload['urlDomain'] as String?,
        totp: payload['totp'] is Map
            ? Map<String, Object?>.from(payload['totp'] as Map)
            : null,
        notes: payload['notes'] as String?,
        customFields: fields,
      ),
      EntryType.script => ScriptSecretContent(
        source: (payload['source'] as String?) ?? '',
        interpreter: (payload['interpreter'] as String?) ?? '',
        refs: (payload['refs'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((value) => Map<String, Object?>.from(value))
            .toList(growable: false),
        notes: payload['notes'] as String?,
        customFields: fields,
      ),
    };
    final discoverable = sourceFields.any(
      (field) => field.agentVisible && field.type.canBeAgentVisible,
    );
    final access = <String, AgentFieldAccess>{
      'memberLabel': AgentFieldAccess.never,
      'agentLabel': discoverable
          ? AgentFieldAccess.discovery
          : AgentFieldAccess.never,
      'description': AgentFieldAccess.never,
      'icon': AgentFieldAccess.never,
      'color': AgentFieldAccess.never,
      'entryType': discoverable
          ? AgentFieldAccess.discovery
          : AgentFieldAccess.never,
      for (final id in content.fieldValues().keys) id: AgentFieldAccess.never,
      for (var index = 0; index < fields.length; index++)
        fields[index].fieldId:
            sourceFields[index].agentVisible &&
                sourceFields[index].type.canBeAgentVisible
            ? AgentFieldAccess.discovery
            : AgentFieldAccess.never,
    };
    return MemberSecret(
      entryType: switch (type) {
        EntryType.key => VaultEntryType.key,
        EntryType.credential => VaultEntryType.credential,
        EntryType.script => VaultEntryType.script,
      },
      memberLabel: label,
      agentLabel: discoverable ? label : null,
      description: description,
      icon: icon == null ? null : GlyphVaultIcon(icon),
      color: null,
      discoverable: discoverable,
      content: content,
      agentFieldAccess: access,
    );
  }

  @override
  Future<EntryEntity> updateEntryEncrypted({
    required String vaultId,
    required String entryId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required Map<String, dynamic> payload,
    String? urlDomain,
    required Uint8List privateKey,
    String? wrappedVK,
    required DateTime createdAt,
    List<AgentField>? agentFields,
  }) async {
    AppLogger.d('Entry', 'Updating protocol-v2 entry id=$entryId');
    Uint8List? vaultKey;
    Uint8List? discoveryKey;
    try {
      final session = sessionStore?.session(vaultId);
      final v2Crypto = entryV2CryptoService;
      if (session == null || v2Crypto == null) {
        throw const EntryException(EntryErrorKind.cryptoFailure);
      }
      vaultKey = session.copyVaultKey();
      discoveryKey = session.copyVaultDiscoveryKey();
      final current = await entryDatasource.getEntryV2(vaultId, entryId);
      final baseRevision = current['currentRevision'] as String;
      final nextRevision = int.parse(baseRevision) + 1;
      final secret = _memberSecret(
        label: label,
        description: description,
        icon: icon,
        type: type,
        payload: payload,
        urlDomain: urlDomain,
      );
      final envelopes = await v2Crypto.seal(
        organizationId: session.organizationId,
        vaultId: vaultId,
        entryId: entryId,
        revision: nextRevision,
        vaultKeyVersion: session.epoch.vaultKeyVersion,
        vdkVersion: session.epoch.vdkVersion,
        memberKeyGeneration: session.memberKeyGeneration,
        operation: 2,
        secret: secret,
        vaultKey: vaultKey,
        vaultDiscoveryKey: discoveryKey,
      );
      final grantEnvelopes = await _grantEnvelopes(
        session: session,
        entryId: entryId,
        revision: nextRevision,
        secret: secret.toJson(),
      );
      try {
        await entryDatasource.updateEntryV2(
          vaultId,
          entryId,
          UpdateEntryV2Request(
            vaultId: vaultId,
            entryId: entryId,
            baseRevision: baseRevision,
            envelopes: envelopes,
            agentDiscoveryChanged: true,
            grantEnvelopes: grantEnvelopes,
          ),
        );
        autoFillMutationNotifier?.notifyChanged();
      } on DioException catch (e, s) {
        AppLogger.e('Entry', 'updateEntry failed', error: e, stackTrace: s);
        throw EntryException(_classifyError(e));
      }
      // Build entity locally — PUT returns 204 No Content. Preserve the
      // original [createdAt] (passed in by the caller) so editing an entry
      // does not overwrite its creation timestamp. `updatedAt` is set to
      // `now()` as a best-effort optimistic value — close enough for UI
      // ordering, and a subsequent list refresh will overwrite it with the
      // server-truthy value.
      return EntryEntity(
        id: entryId,
        vaultId: vaultId,
        label: label,
        description: description,
        icon: icon,
        type: type,
        urlDomain: urlDomain,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
    } finally {
      if (vaultKey != null) {
        vaultKey.fillRange(0, vaultKey.length, 0);
      }
      discoveryKey?.fillRange(0, discoveryKey.length, 0);
    }
  }

  @override
  Future<ImportResult> importEntriesEncrypted({
    required String vaultId,
    required String format,
    required List<ImportEntryDraft> creates,
    required List<ImportEntryOverwrite> overwrites,
    required Uint8List privateKey,
    String? wrappedVK,
    int chunkSize = 500,
    void Function(int done, int total)? onProgress,
  }) async {
    AppLogger.d(
      'Entry',
      'Importing ${creates.length} new + ${overwrites.length} overwrites into $vaultId',
    );
    final total = creates.length + overwrites.length;
    var done = 0;
    var mutated = false;

    void markMutated() {
      if (!mutated) {
        // A multi-step import can continue for a long time after its first
        // successful write. Revoke the old cache immediately; the finally
        // block rebuilds it once all successful writes are visible.
        autoFillMutationNotifier?.notifyInvalidated();
      }
      mutated = true;
    }

    Uint8List? vaultKey;
    Uint8List? discoveryKey;
    try {
      final session = sessionStore?.session(vaultId);
      final v2Crypto = entryV2CryptoService;
      if (session == null || v2Crypto == null) {
        throw const EntryException(EntryErrorKind.cryptoFailure);
      }
      vaultKey = session.copyVaultKey();
      discoveryKey = session.copyVaultDiscoveryKey();

      final activeFullGrants = creates.isEmpty
          ? const <Map<String, dynamic>>[]
          : (await entryDatasource.listActiveGrants(vaultId))
              .where((grant) => (grant['type'] ?? grant['mode']) == 'full')
              .toList(growable: false);

      var createdCount = 0;
      for (var start = 0; start < creates.length; start += chunkSize) {
        final end = (start + chunkSize).clamp(0, creates.length);
        final chunk = creates.sublist(start, end);
        final challenges = await entryDatasource.issueCreationChallenges(
          vaultId,
          count: chunk.length,
        );
        if (challenges.length != chunk.length) {
          throw const EntryException(EntryErrorKind.cryptoFailure);
        }
        final items = <Map<String, Object?>>[];
        for (var index = 0; index < chunk.length; index++) {
          final draft = chunk[index];
          final entryId = challenges[index].entryId;
          final envelopes = await v2Crypto.seal(
            organizationId: session.organizationId,
            vaultId: vaultId,
            entryId: entryId,
            revision: 1,
            vaultKeyVersion: session.epoch.vaultKeyVersion,
            vdkVersion: session.epoch.vdkVersion,
            memberKeyGeneration: session.memberKeyGeneration,
            operation: 1,
            secret: _memberSecret(
              label: draft.label,
              description: draft.description,
              icon: null,
              type: draft.type,
              payload: draft.payload,
              urlDomain: draft.urlDomain,
            ),
            vaultKey: vaultKey,
            vaultDiscoveryKey: discoveryKey,
          );
          final secret = _memberSecret(
            label: draft.label,
            description: draft.description,
            icon: null,
            type: draft.type,
            payload: draft.payload,
            urlDomain: draft.urlDomain,
          );
          final grantEnvelopes = await _grantEnvelopes(
            session: session,
            entryId: entryId,
            revision: 1,
            secret: secret.toJson(),
            grants: activeFullGrants,
          );
          items.add({
            'entryId': entryId,
            'entryKey': envelopes.entryKey,
            'memberIndex': envelopes.memberIndex,
            'memberSecret': envelopes.memberSecret,
            'agentDiscovery': envelopes.agentDiscovery,
            'grantEnvelopes': grantEnvelopes,
          });
        }
        try {
          createdCount += await entryDatasource.importEntriesV2(
            vaultId,
            format: format,
            entries: items,
          );
          markMutated();
        } on DioException catch (e, s) {
          AppLogger.e(
            'Entry',
            'importEntries chunk failed',
            error: e,
            stackTrace: s,
          );
          throw EntryException(_classifyError(e));
        }
        done += chunk.length;
        onProgress?.call(done, total);
      }

      var updatedCount = 0;
      for (final overwrite in overwrites) {
        try {
          markMutated();
          await updateEntryEncrypted(
            vaultId: vaultId,
            entryId: overwrite.entryId,
            label: overwrite.label,
            description: overwrite.description,
            type: overwrite.type,
            payload: overwrite.payload,
            urlDomain: overwrite.urlDomain,
            privateKey: privateKey,
            createdAt: overwrite.createdAt,
          );
          updatedCount++;
        } on DioException catch (e, s) {
          AppLogger.e(
            'Entry',
            'import overwrite failed',
            error: e,
            stackTrace: s,
          );
          throw EntryException(_classifyError(e));
        }
        done++;
        onProgress?.call(done, total);
      }

      AppLogger.i(
        'Entry',
        'Import done: created=$createdCount updated=$updatedCount',
      );
      return ImportResult(
        createdCount: createdCount,
        updatedCount: updatedCount,
      );
    } finally {
      if (mutated) autoFillMutationNotifier?.notifyChanged();
      if (vaultKey != null) {
        vaultKey.fillRange(0, vaultKey.length, 0);
      }
      discoveryKey?.fillRange(0, discoveryKey.length, 0);
    }
  }

  @override
  Future<List<RevealedEntry>> revealAllEntries({
    required String vaultId,
    required Uint8List privateKey,
    String? wrappedVK,
  }) async {
    AppLogger.d('Entry', 'Revealing all entries in $vaultId for export');
    final summaries = await listEntries(vaultId);
    final revealed = <RevealedEntry>[];
    for (final summary in summaries) {
      revealed.add(
        await revealEntry(
          vaultId: vaultId,
          entryId: summary.id,
          privateKey: privateKey,
        ),
      );
    }
    return revealed;
  }

  @override
  Future<List<RevealedEntry>> revealAutoFillCredentials({
    required String vaultId,
    required Uint8List privateKey,
    String? wrappedVK,
  }) async {
    final summaries = await listEntries(vaultId);
    final candidates = summaries
        .where(
          (entry) =>
              entry.type == EntryType.credential &&
              (entry.urlDomain?.trim().isNotEmpty ?? false),
        )
        .toList(growable: false);
    if (candidates.isEmpty) return const [];

    final revealed = <RevealedEntry>[];
    for (final summary in candidates) {
      revealed.add(
        await revealEntry(
          vaultId: vaultId,
          entryId: summary.id,
          privateKey: privateKey,
        ),
      );
    }
    return revealed;
  }

  @override
  Future<void> logExportAudit({
    required String vaultId,
    required String format,
    required int entryCount,
  }) async {
    try {
      await entryDatasource.logExportAudit(vaultId, format, entryCount);
    } on DioException catch (e) {
      // Best-effort — the export already succeeded, so a failed audit
      // record must not surface to the user.
      AppLogger.w('Entry', 'export-audit failed (non-fatal)', error: e);
    }
  }

  Future<List<Map<String, Object?>>> _grantEnvelopes({
    required UnlockedVaultSession session,
    required String entryId,
    required int revision,
    required Map<String, dynamic> secret,
    List<Map<String, dynamic>>? grants,
  }) async {
    final active =
        grants ?? await entryDatasource.listActiveGrants(session.vaultId);
    final covering = active.where((grant) {
      final type = grant['type'] ?? grant['mode'];
      return type == 'full' || grant['entryId'] == entryId;
    });
    final result = <Map<String, Object?>>[];
    for (final grant in covering) {
      final grantId = grant['id'] as String;
      final agentId = grant['agentId'] as String?;
      final publicKeyText = grant['agentPublicKey'] as String?;
      final keyVersion = (grant['recipientAgentKeyVersion'] as num?)?.toInt();
      if (agentId == null || publicKeyText == null || keyVersion == null) {
        throw const EntryException(EntryErrorKind.cryptoFailure);
      }
      final scopes = (grant['entryScopes'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .where((scope) => scope['entryId'] == entryId)
          .toList(growable: false);
      final fieldIds =
          scopes
              .expand(
                (scope) => scope['fieldIds'] as List<dynamic>? ?? const [],
              )
              .whereType<String>()
              .toSet()
              .toList()
            ..sort();
      if (fieldIds.isEmpty) {
        fieldIds.addAll(
          Map<String, dynamic>.from(secret['agentFieldAccess'] as Map).entries
              .where(
                (entry) => const {
                  'onGrantValue',
                  'onGrantDerived',
                  'onGrantRuntime',
                }.contains(entry.value),
              )
              .map((entry) => entry.key),
        );
        fieldIds.sort();
      }
      if (fieldIds.isEmpty) {
        throw const EntryException(EntryErrorKind.cryptoFailure);
      }
      final publicKey = Uint8List.fromList(base64Decode(publicKeyText));
      try {
        final queryLimit = grant['queryLimit'] as int?;
        final queryCount = grant['queryCount'] as int? ?? 0;
        result.add(
          await entryV2CryptoService!.sealGrant(
            organizationId: session.organizationId,
            vaultId: session.vaultId,
            entryId: entryId,
            grantId: grantId,
            agentId: agentId,
            entryRevision: revision,
            memberKeyGeneration: session.memberKeyGeneration,
            agentPublicKey: publicKey,
            recipientKeyVersion: keyVersion,
            approvedMethods: _grantMethodBits(grant['methods']),
            fieldIds: fieldIds,
            grantPayload: VaultPlaintextProjector.grantPayloadFromJson(
              secret,
              fieldIds.toSet(),
            ),
            expiresAt: grant['expiresAt'] == null
                ? null
                : DateTime.parse(grant['expiresAt'] as String),
            remainingUses: queryLimit == null ? null : queryLimit - queryCount,
          ),
        );
      } finally {
        publicKey.fillRange(0, publicKey.length, 0);
      }
    }
    return result;
  }

  int _grantMethodBits(Object? raw) {
    if (raw is num) return raw.toInt();
    final names = (raw as String? ?? '')
        .split(',')
        .map((value) => value.trim().toLowerCase())
        .toSet();
    return (names.contains('get') ? 1 : 0) |
        (names.contains('exec') ? 2 : 0) |
        (names.contains('inject') ? 4 : 0);
  }

  /// Maps a [DioException] to a typed [EntryErrorKind].
  EntryErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return EntryErrorKind.networkError;
    }

    final status = e.response?.statusCode;
    return switch (status) {
      404 => EntryErrorKind.notFound,
      403 => EntryErrorKind.forbidden,
      400 => EntryErrorKind.validation,
      _ => EntryErrorKind.unknown,
    };
  }
}
