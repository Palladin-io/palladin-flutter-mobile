// Offline preview boundaries. All values below are synthetic and RAM-only.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'asset_adapters.dart';

import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/custom_field.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_repository.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_list_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_creation_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_settings_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_history_service.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_detail_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/create_vault_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_list_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/global_entries_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/create_entry_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/edit_entry_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_history_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_archive_cubit.dart';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_sharing_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_selection_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_creation.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_list.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_share_creation_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/recently_deleted_cubit.dart';

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

mixin _Unsupported {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Offline Vault preview does not support ${invocation.memberName}',
  );
}

final vaultPreview = VaultPreviewMemory();

class VaultPreviewMemory implements MemberIndexReader, MemberEntryListLoader {
  final updates = StreamController<String>.broadcast();
  final vaults = <String, VaultEntity>{};
  final records = <String, EntryEntity>{};
  final payloads = <String, Map<String, dynamic>>{};
  final history = <String, List<CanonicalEntrySnapshot>>{};
  final policies = <String, Map<String, dynamic>>{};
  final agentLabels = <String, String>{};
  int serial = 0;

  VaultPreviewMemory() {
    final date = DateTime.utc(2026, 11, 12, 10);
    for (final item in [
      ('vault-personal', 'Personal', 'person'),
      ('vault-work', 'Work', 'work'),
    ]) {
      vaults[item.$1] = VaultEntity(
        id: item.$1,
        name: item.$2,
        description: item.$2 == 'Personal'
            ? 'Everyday accounts and private notes'
            : 'Shared tools for the design team',
        icon: item.$3,
        grantMode: GrantMode.granular,
        createdAt: date,
        updatedAt: date,
        entryCount: 2,
        activeGrantCount: 2,
        memberCount: item.$2 == 'Personal' ? 1 : 3,
      );
    }
    for (final item in [
      ('entry-github', 'GitHub', 'github.com', 'vault-work'),
      ('entry-google', 'Google', 'google.com', 'vault-personal'),
      ('entry-notion', 'Notion', 'notion.so', 'vault-work'),
    ]) {
      put(
        id: item.$1,
        vaultId: item.$4,
        label: item.$2,
        type: EntryType.credential,
        payload: {
          'v': 2,
          'type': 'CREDENTIAL',
          'username': 'alex@example.test',
          'password': 'Preview-only-example-42!',
          'url': 'https://${item.$3}',
          'notes': 'Synthetic account for the offline design preview.',
        },
        icon: 'language',
      );
    }
    for (var revision = 2; revision <= 3; revision++) {
      put(
        id: 'entry-github',
        vaultId: 'vault-work',
        label: 'GitHub',
        type: EntryType.credential,
        icon: 'language',
        payload: {
          ...payloads['entry-github']!,
          'notes': revision == 2
              ? 'Personal development account.'
              : 'Development account with two-factor authentication.',
          if (revision == 3)
            'fields': [
              {
                'id': 'demo-signin-google',
                'label': 'Google',
                'type': 'palladin.signin.v1',
                'value': {
                  'provider': 'google',
                  'account': 'alex@example.test',
                  'entry': null,
                },
              },
              {
                'id': 'demo-totp',
                'label': 'GitHub 2FA',
                'type': 'totp',
                'value': {
                  'secret': 'JBSWY3DPEHPK3PXP',
                  'algorithm': 'SHA1',
                  'digits': 6,
                  'period': 30,
                  'issuer': 'GitHub',
                  'account': 'alex@example.test',
                },
              },
            ],
        },
      );
    }
    put(
      id: 'entry-api',
      vaultId: 'vault-personal',
      label: 'Development API',
      type: EntryType.key,
      payload: {
        'v': 2,
        'type': 'KEY',
        'value': 'DEMO-NOT-A-REAL-API-KEY',
        'notes': 'Local sandbox only',
      },
      icon: 'key',
    );
    put(
      id: 'entry-archived',
      vaultId: 'vault-work',
      label: 'Previous workspace',
      type: EntryType.credential,
      payload: {
        'v': 2,
        'type': 'CREDENTIAL',
        'username': 'demo@example.test',
        'password': 'Preview-only',
      },
      lifecycle: MemberEntryState.archived,
    );
  }

  EntryEntity put({
    required String id,
    required String vaultId,
    required String label,
    required EntryType type,
    required Map<String, dynamic> payload,
    String? description,
    String? icon,
    MemberEntryState lifecycle = MemberEntryState.active,
  }) {
    final previous = records[id];
    final entry = EntryEntity(
      id: id,
      vaultId: vaultId,
      label: label,
      description: description ?? '',
      icon: icon,
      type: type,
      username: payload['username'] as String?,
      urlDomain: Uri.tryParse(payload['url'] as String? ?? '')?.host,
      createdAt: previous?.createdAt ?? DateTime.utc(2026, 11, 12, 10),
      updatedAt: DateTime.now(),
      currentRevision: '${int.parse(previous?.currentRevision ?? '0') + 1}',
      lifecycleState: lifecycle,
    );
    records[id] = entry;
    payloads[id] = _copy(payload);
    history.putIfAbsent(id, () => []).insert(0, snapshot(id));
    final vault = vaults[vaultId]!;
    vaults[vaultId] = VaultEntity(
      id: vault.id,
      name: vault.name,
      description: vault.description,
      icon: vault.icon,
      color: vault.color,
      grantMode: vault.grantMode,
      createdAt: vault.createdAt,
      updatedAt: vault.updatedAt,
      entryCount: records.values
          .where(
            (e) =>
                e.vaultId == vaultId &&
                e.lifecycleState == MemberEntryState.active,
          )
          .length,
      activeGrantCount: vault.activeGrantCount,
      memberCount: vault.memberCount,
    );
    updates.add(vaultId);
    return entry;
  }

  CanonicalEntrySnapshot snapshot(String id) {
    final e = records[id]!;
    return CanonicalEntrySnapshot(
      entry: {
        'id': id,
        'vaultId': e.vaultId,
        'organizationId': 'demo-org',
        'currentRevision': e.currentRevision,
        'currentKeyVersion': 1,
        'updatedAt': e.updatedAt.toIso8601String(),
      },
      secret: {
        'memberLabel': e.label,
        'agentLabel': agentLabels[id] ?? e.label,
        'description': e.description ?? '',
        'iconReference': e.icon ?? '',
        'entryType': e.type.toWire(),
        'agentVisibilityPolicy': _copy(
          policies[id] ??
              {'discoverable': false, 'fields': <String, dynamic>{}},
        ),
      },
      payload: _copy(payloads[id]!),
    );
  }

  void lifecycle(String id, MemberEntryState state) {
    final e = records[id]!;
    put(
      id: id,
      vaultId: e.vaultId,
      label: e.label,
      type: e.type,
      payload: payloads[id]!,
      description: e.description,
      icon: e.icon,
      lifecycle: state,
    );
  }

  @override
  List<MemberIndexEntry> entries(String vaultId) => records.values
      .where((e) => e.vaultId == vaultId)
      .map(
        (e) => MemberIndexEntry(
          entryId: e.id,
          entryType: e.type.toWire(),
          memberLabel: e.label,
          searchFields: [e.label, e.username ?? '', e.urlDomain ?? ''],
          revision: e.currentRevision,
          state: e.lifecycleState,
          username: e.username,
          iconReference: e.icon,
          autofillDomains: e.urlDomain == null ? [] : [e.urlDomain!],
        ),
      )
      .toList();
  @override
  Future<List<MemberIndexEntry>> load({
    required String vaultId,
    required Uint8List memberPrivateKey,
  }) async => entries(vaultId);
  @override
  Future<void> waitForCurrent(String vaultId) async {}
  @override
  void lock() {} // No key, storage, or background work exists in this fixture.
}

class _EntryRepository with _Unsupported implements EntryRepository {
  @override
  Future<List<EntryEntity>> listEntries(String vaultId) async => vaultPreview
      .records
      .values
      .where(
        (e) =>
            e.vaultId == vaultId && e.lifecycleState == MemberEntryState.active,
      )
      .toList();
  @override
  Future<void> deleteEntry({
    required String vaultId,
    required String entryId,
  }) async => vaultPreview.lifecycle(entryId, MemberEntryState.deleted);
  @override
  Future<RevealedEntry> revealEntry({
    required String vaultId,
    required String entryId,
    required Uint8List privateKey,
    String? wrappedVK,
  }) async => RevealedEntry(
    entry: vaultPreview.records[entryId]!,
    payload: _copy(vaultPreview.payloads[entryId]!),
  );
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
  }) async => vaultPreview.put(
    id: 'entry-preview-${++vaultPreview.serial}',
    vaultId: vaultId,
    label: label,
    description: description,
    icon: icon,
    type: type,
    payload: payload,
  );
}

class _VaultRepository with _Unsupported implements VaultRepository {
  @override
  Future<void> deleteVault(String id) async {
    vaultPreview.vaults.remove(id);
    vaultPreview.records.removeWhere((_, e) => e.vaultId == id);
    vaultPreview.updates.add(id);
  }
}

class _VaultList with _Unsupported implements VaultListCryptoService {
  @override
  Future<DecryptedVaultList> load(Uint8List memberPrivateKey) async =>
      DecryptedVaultList(
        vaults: vaultPreview.vaults.values.toList(),
        corruptIds: [],
      );
  @override
  Future<VaultEntity> loadOne(
    String vaultId,
    Uint8List memberPrivateKey,
  ) async => vaultPreview.vaults[vaultId]!;
  @override
  void lock() {}
}

class _VaultCreator implements VaultCreator {
  @override
  Future<VaultEntity> create({
    required String name,
    String? description,
    String? icon,
    String? color,
    required Uint8List memberPrivateKey,
  }) async {
    final e = VaultEntity(
      id: 'vault-preview-${++vaultPreview.serial}',
      name: name,
      description: description,
      icon: icon,
      color: color,
      grantMode: GrantMode.granular,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      entryCount: 0,
      activeGrantCount: 0,
      memberCount: 1,
    );
    vaultPreview.vaults[e.id] = e;
    return e;
  }
}

class _VaultSettings with _Unsupported implements VaultSettingsService {
  @override
  Future<VaultEntity> update({
    required VaultEntity expected,
    required String name,
    required String description,
    required String icon,
    required String color,
    required Uint8List memberPrivateKey,
    String? localIconPath,
  }) async {
    if (localIconPath != null) {
      throw UnsupportedError('Image upload is unavailable offline');
    }
    final e = VaultEntity(
      id: expected.id,
      name: name,
      description: description,
      icon: icon,
      color: color,
      grantMode: expected.grantMode,
      createdAt: expected.createdAt,
      updatedAt: DateTime.now(),
      entryCount: expected.entryCount,
      activeGrantCount: expected.activeGrantCount,
      memberCount: expected.memberCount,
    );
    vaultPreview.vaults[e.id] = e;
    getIt<VaultListCubit>().updateVault(e);
    return e;
  }
}

class _LocalEntries with _Unsupported implements LocalCurrentEntryService {
  @override
  Future<CanonicalEntrySnapshot> reveal({
    required EntryEntity expected,
    required Uint8List memberPrivateKey,
  }) async => vaultPreview.snapshot(expected.id);
}

class _Canonical with _Unsupported implements CanonicalEntryDetailService {
  @override
  Future<CanonicalEntrySnapshot> reveal({
    required EntryEntity expected,
    required Uint8List memberPrivateKey,
  }) async => vaultPreview.snapshot(expected.id);
  @override
  Future<EntryEntity> update({
    required CanonicalEntrySnapshot snapshot,
    required EntryEntity expected,
    required String label,
    required String description,
    required String icon,
    String? color,
    required EntryType type,
    required Map<String, dynamic> content,
    required Uint8List memberPrivateKey,
    AgentVisibilityPolicy? agentVisibilityPolicy,
    String? agentLabel,
  }) async {
    if (agentVisibilityPolicy != null) {
      vaultPreview.policies[expected.id] = agentVisibilityPolicy.toJson();
    }
    if (agentLabel != null) vaultPreview.agentLabels[expected.id] = agentLabel;
    return vaultPreview.put(
      id: expected.id,
      vaultId: expected.vaultId,
      label: label,
      description: description,
      icon: icon,
      type: type,
      payload: content,
    );
  }

  @override
  Future<void> restoreArchived({
    required String vaultId,
    required MemberIndexEntry archived,
    required Uint8List memberPrivateKey,
  }) async => vaultPreview.lifecycle(archived.entryId, MemberEntryState.active);
  @override
  Future<void> restoreRecoverable({
    required String vaultId,
    required MemberIndexEntry entry,
    required Uint8List memberPrivateKey,
  }) async => vaultPreview.lifecycle(entry.entryId, MemberEntryState.active);
  @override
  Future<void> purgeDeleted({
    required String vaultId,
    required String entryId,
  }) async {
    vaultPreview.records.remove(entryId);
    vaultPreview.payloads.remove(entryId);
    vaultPreview.history.remove(entryId);
    vaultPreview.updates.add(vaultId);
  }
}

class _History with _Unsupported implements EntryHistoryService {
  @override
  Future<EntryHistoryPage> loadPage(
    EntryEntity entry, {
    String? beforeRevision,
  }) async => EntryHistoryPage(
    items: vaultPreview.history[entry.id]!
        .map(
          (s) => EntryHistoryVersion(
            revision: s.entry['currentRevision'] as String,
            changedAt: DateTime.parse(s.entry['updatedAt'] as String),
            changedByType: 'Member',
            changedById: 'demo-user',
            actorName: 'Alex Morgan',
            operation: s.entry['currentRevision'] == '1'
                ? 'Created'
                : 'Updated',
            encrypted: {},
          ),
        )
        .toList(),
    nextCursor: null,
  );
  @override
  Future<CanonicalEntryHistorySnapshot> reveal({
    required EntryEntity entry,
    required EntryHistoryVersion version,
    required Uint8List privateKey,
  }) async {
    final s = vaultPreview.history[entry.id]!.firstWhere(
      (s) => s.entry['currentRevision'] == version.revision,
    );
    return CanonicalEntryHistorySnapshot(
      secret: _copy(s.secret),
      payload: _copy(s.payload),
    );
  }

  @override
  Future<EntryEntity> restore({
    required EntryEntity entry,
    required CanonicalEntryHistorySnapshot selected,
    required Uint8List privateKey,
  }) async => vaultPreview.put(
    id: entry.id,
    vaultId: entry.vaultId,
    label: selected.secret['memberLabel'] as String,
    type: EntryTypeExtension.fromWire(selected.secret['entryType'] as int),
    payload: selected.payload,
  );
  @override
  void clearSessionCache() {}
}

Future<void> registerVaultPreview() async {
  await registerAssetPreview();
  Future<void> replace<T extends Object>(T value) async {
    if (getIt.isRegistered<T>()) await getIt.unregister<T>();
    getIt.registerSingleton<T>(value);
  }

  Future<void> factory<T extends Object>(T Function() create) async {
    if (getIt.isRegistered<T>()) await getIt.unregister<T>();
    getIt.registerFactory<T>(create);
  }

  await replace<MemberSyncSessionAuthorityProvider>(
    MemberSyncSessionAuthorityProvider.independent(
      readClaims: () async => const MemberSyncSessionAuthority(
        principalId: 'demo-user',
        organizationId: 'demo-org',
        organizationMembershipGeneration: '1',
        offlinePolicy: '24h',
        offlinePolicyVersion: 1,
      ),
      sessionRevision: () => 1,
    ),
  );
  final sharing = _SharingRemote();
  await replace<EntrySharingRemoteDatasource>(sharing);
  await replace<EntryShareCreationCubitFactory>(
    ({required expected, required sessionReader, required sourceReader}) =>
        _ShareCreation(expected, sharing),
  );
  final entries = _EntryRepository();
  final vaults = _VaultRepository();
  final list = _VaultList();
  final local = _LocalEntries();
  final canonical = _Canonical();
  final settings = _VaultSettings();
  await replace<EntryRepository>(entries);
  await replace<VaultRepository>(vaults);
  await replace<VaultListCryptoService>(list);
  await replace<VaultSettingsService>(settings);
  await replace<LocalCurrentEntryService>(local);
  await replace<CanonicalEntryDetailService>(canonical);
  await replace<VaultListCubit>(
    VaultListCubit(repository: vaults, listService: list),
  );
  await factory<VaultDetailCubit>(
    () => VaultDetailCubit(
      repository: vaults,
      listService: list,
      settingsService: settings,
    ),
  );
  await factory<CreateVaultCubit>(
    () => CreateVaultCubit(creationService: _VaultCreator()),
  );
  await factory<CreateEntryCubit>(() => CreateEntryCubit(repository: entries));
  await factory<EditEntryCubit>(
    () => EditEntryCubit(
      repository: entries,
      canonicalService: canonical,
      localCurrentEntry: local,
    ),
  );
  await factory<GlobalEntriesCubit>(
    () => GlobalEntriesCubit(
      index: vaultPreview,
      loader: vaultPreview,
      indexUpdates: vaultPreview.updates.stream,
      localEntries: local,
    ),
  );
  await factory<EntryHistoryCubit>(() => EntryHistoryCubit(_History()));
  if (getIt.isRegistered<EntryListCubit>()) {
    await getIt.unregister<EntryListCubit>();
  }
  getIt.registerFactoryParam<EntryListCubit, String, String?>(
    (id, vk) => EntryListCubit(
      repository: entries,
      vaultId: id,
      wrappedVK: vk,
      indexLoader: vaultPreview,
    ),
  );
  if (getIt.isRegistered<EntryArchiveCubit>()) {
    await getIt.unregister<EntryArchiveCubit>();
  }
  getIt.registerFactoryParam<EntryArchiveCubit, String, void>(
    (id, _) => EntryArchiveCubit(
      vaultId: id,
      index: vaultPreview,
      sync: vaultPreview,
      restorer: canonical,
    ),
  );
  if (getIt.isRegistered<RecentlyDeletedCubit>()) {
    await getIt.unregister<RecentlyDeletedCubit>();
  }
  getIt.registerFactoryParam<RecentlyDeletedCubit, String, void>(
    (id, _) => RecentlyDeletedCubit(
      vaultId: id,
      remote: _EntryRemote(),
      index: vaultPreview,
      sync: vaultPreview,
      lifecycle: canonical,
    ),
  );
}

class _EntryRemote with _Unsupported implements EntryRemoteDatasource {
  @override
  Future<Map<String, dynamic>> listRecentlyDeleted(
    String vaultId, {
    String? cursor,
    int pageSize = 100,
  }) async => {
    'items': vaultPreview.records.values
        .where(
          (e) =>
              e.vaultId == vaultId &&
              e.lifecycleState == MemberEntryState.deleted,
        )
        .map(
          (e) => {
            'id': e.id,
            'state': 'deleted',
            'deletedAt': e.updatedAt.toIso8601String(),
            'retentionExpiresAt': e.updatedAt
                .add(const Duration(days: 30))
                .toIso8601String(),
          },
        )
        .toList(),
    'nextCursor': null,
  };
}

class _SharingRemote with _Unsupported implements EntrySharingRemoteDatasource {
  final shares = <String, List<EntryShareListItem>>{};
  List<EntryShareListItem> _items(String id) => shares.putIfAbsent(
    id,
    () => [
      EntryShareListItem(
        shareId: 'preview-share-0001',
        status: 'active',
        expiresAt: DateTime.now().add(const Duration(days: 3)),
        maximumReceipts: 5,
        deliveryCount: 1,
        firstDeliveredAt: DateTime.now().subtract(const Duration(hours: 2)),
        lastDeliveredAt: DateTime.now().subtract(const Duration(hours: 2)),
        firstConfirmedAt: null,
        notifyOnFirstReceipt: true,
        recipientMode: 'anyoneWithLink',
        recipientEmail: null,
        protection: 'password',
        sourceChanged: false,
      ),
    ],
  );
  @override
  Future<EntrySharesPage> list(
    String vaultId,
    String entryId, {
    String? cursor,
    required CancelToken cancelToken,
  }) async => EntrySharesPage(items: _items(entryId), nextCursor: null);
  void _replace(
    String entryId,
    String shareId, {
    String? status,
    String? protection,
  }) {
    final rows = _items(entryId);
    final i = rows.indexWhere((e) => e.shareId == shareId);
    final e = rows[i];
    rows[i] = EntryShareListItem(
      shareId: e.shareId,
      status: status ?? e.status,
      expiresAt: e.expiresAt,
      maximumReceipts: e.maximumReceipts,
      deliveryCount: e.deliveryCount,
      firstDeliveredAt: e.firstDeliveredAt,
      lastDeliveredAt: e.lastDeliveredAt,
      firstConfirmedAt: e.firstConfirmedAt,
      notifyOnFirstReceipt: e.notifyOnFirstReceipt,
      recipientMode: e.recipientMode,
      recipientEmail: e.recipientEmail,
      protection: protection ?? e.protection,
      sourceChanged: e.sourceChanged,
    );
  }

  @override
  Future<void> revoke(
    String vaultId,
    String entryId,
    String shareId, {
    required CancelToken cancelToken,
  }) async => _replace(entryId, shareId, status: 'revoked');
  @override
  Future<void> changeProtection(
    String vaultId,
    String entryId,
    String shareId, {
    required EntryShareProtection protection,
    required String? protectionSecret,
    required CancelToken cancelToken,
  }) async => _replace(entryId, shareId, protection: protection.name);
}

class _ShareCreation extends Cubit<EntryShareCreationState>
    with _Unsupported
    implements EntryShareCreationCubit {
  _ShareCreation(this.entry, this.remote)
    : super(const EntryShareCreationState());
  final EntryEntity entry;
  final _SharingRemote remote;
  @override
  Future<void> load() async {
    final snapshot = vaultPreview.snapshot(entry.id);
    try {
      emit(
        EntryShareCreationState(
          phase: EntryShareCreationPhase.ready,
          selection: const EntryShareSelectionService().project(snapshot),
        ),
      );
    } finally {
      snapshot.clear();
    }
  }

  @override
  Future<void> create({required EntryShareCreationOptions options}) async {
    final recipients = options.recipientEmails.isEmpty
        ? <String?>[null]
        : options.recipientEmails;
    final links = <CreatedEntryShareLink>[];
    for (final recipient in recipients) {
      final id =
          '00000000-0000-4000-8000-${(++vaultPreview.serial).toString().padLeft(12, '0')}';
      // Deliberately non-functional synthetic capability, never sent to a service.
      final synthetic = base64UrlEncode(Uint8List(32)).replaceAll('=', '');
      links.add(
        CreatedEntryShareLink(
          shareId: id,
          fragment: '#v=1&key=$synthetic&access=$synthetic',
          recipientEmail: recipient,
        ),
      );
      remote
          ._items(entry.id)
          .add(
            EntryShareListItem(
              shareId: id,
              status: 'active',
              expiresAt: DateTime.now().add(
                Duration(hours: options.lifetimeHours),
              ),
              maximumReceipts: options.maximumReceipts,
              deliveryCount: 0,
              firstDeliveredAt: null,
              lastDeliveredAt: null,
              firstConfirmedAt: null,
              notifyOnFirstReceipt: options.notifyOnFirstReceipt,
              recipientMode: options.recipientMode.name,
              recipientEmail: recipient,
              protection: options.protection.name,
              sourceChanged: false,
            ),
          );
    }
    emit(
      EntryShareCreationState(
        phase: EntryShareCreationPhase.created,
        shareId: links.first.shareId,
        fragment: links.first.fragment,
        links: links,
      ),
    );
  }

  @override
  bool get hasMultipleRequestedRecipients => state.links.length > 1;
  @override
  Future<bool> revalidate() async =>
      !isClosed && state.phase != EntryShareCreationPhase.unavailable;
  @override
  Future<String?> fragmentForCopy([int index = 0]) async =>
      state.links.elementAtOrNull(index)?.fragment;
  @override
  void clear({EntryShareCreationFailure? failure}) => emit(
    EntryShareCreationState(
      phase: EntryShareCreationPhase.unavailable,
      failure: failure,
    ),
  );
}
