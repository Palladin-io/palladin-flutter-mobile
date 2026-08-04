import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/crypto/envelope/envelope_contract.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/member_index_entry.dart';
import '../../domain/entities/vault_performance_budget.dart';
import '../../domain/entities/vault_plaintext.dart';
import '../datasources/member_sync_remote_datasource.dart';
import '../models/member_sync_models.dart';
import 'entry_v2_crypto_service.dart';
import 'member_sync_cache.dart';

/// Result of a completed ciphertext synchronization.
final class MemberSyncResult {
  const MemberSyncResult({
    required this.sequence,
    required this.entryCount,
    required this.usedSnapshot,
  });

  final String sequence;
  final int entryCount;
  final bool usedSnapshot;
}

/// Coordinates bounded network sync, ciphertext persistence, and the unlocked
/// in-memory search index. Call [lock] whenever the Vault session is locked.
abstract interface class MemberIndexReader {
  Future<void> waitForCurrent(String vaultId);

  List<MemberIndexEntry> entries(String vaultId);
}

final class MemberSyncService implements MemberIndexReader {
  MemberSyncService({
    required MemberSyncRemote remote,
    required MemberSyncCache cache,
    required EntryV2CryptoService entryCrypto,
    this.maximumIndexedEntries = VaultPerformanceBudget.maximumIndexedEntries,
    this.decryptConcurrency =
        VaultPerformanceBudget.memberIndexDecryptConcurrency,
  }) : _remote = remote,
       _cache = cache,
       _entryCrypto = entryCrypto {
    if (maximumIndexedEntries < 1 || decryptConcurrency < 1) {
      throw ArgumentError('Member sync budgets must be positive');
    }
  }

  final MemberSyncRemote _remote;
  final MemberSyncCache _cache;
  final EntryV2CryptoService _entryCrypto;
  final int maximumIndexedEntries;
  final int decryptConcurrency;

  final Map<String, Map<String, MemberIndexEntry>> _indexes = {};
  final Map<String, Future<MemberSyncResult>> _running = {};
  final StreamController<String> _indexUpdates =
      StreamController<String>.broadcast();
  int _lockGeneration = 0;

  /// Emits a Vault id after its unlocked runtime index has been installed or
  /// refreshed. Consumers use this signal to refresh local presentation only;
  /// no plaintext leaves the service through the stream.
  Stream<String> get indexUpdates => _indexUpdates.stream;

  /// Synchronizes one Vault. Concurrent callers for the same Vault share work.
  Future<MemberSyncResult> synchronize({
    required String vaultId,
    required Uint8List vaultKey,
    required int minimumMemberKeyGeneration,
  }) {
    if (vaultKey.length != 32) {
      return Future.error(
        const FormatException('Vault key must be exactly 32 bytes'),
      );
    }
    final active = _running[vaultId];
    if (active != null) return active;
    final generation = _lockGeneration;
    late final Future<MemberSyncResult> operation;
    operation = (() async {
      try {
        final sequence = await _cache.sequence(vaultId);
        _requireCurrent(generation);
        if (sequence == null) {
          return _snapshot(
            vaultId,
            vaultKey,
            minimumMemberKeyGeneration,
            generation,
          );
        }
        return _delta(
          vaultId,
          sequence,
          vaultKey,
          minimumMemberKeyGeneration,
          generation,
        );
      } finally {
        if (identical(_running[vaultId], operation)) {
          _running.remove(vaultId);
        }
      }
    })();
    _running[vaultId] = operation;
    return operation;
  }

  /// Rebuilds the runtime index from the last complete ciphertext snapshot.
  Future<void> unlockCached({
    required String vaultId,
    required Uint8List vaultKey,
    required int minimumMemberKeyGeneration,
  }) => _unlockCached(
    vaultId: vaultId,
    vaultKey: vaultKey,
    minimumMemberKeyGeneration: minimumMemberKeyGeneration,
    generation: _lockGeneration,
  );

  Future<void> _unlockCached({
    required String vaultId,
    required Uint8List vaultKey,
    required int minimumMemberKeyGeneration,
    required int generation,
  }) async {
    final rebuilt = <String, MemberIndexEntry>{};
    await for (final page in _chunk(_cache.readHeads(vaultId), 100)) {
      _requireCurrent(generation);
      final decrypted = await _decryptPage(
        page,
        vaultId,
        vaultKey,
        minimumMemberKeyGeneration,
      );
      _requireCurrent(generation);
      for (final entry in decrypted) {
        rebuilt[entry.entryId] = entry;
        if (rebuilt.length > maximumIndexedEntries) {
          throw StateError('Vault local index exceeds the device budget');
        }
      }
    }
    _requireCurrent(generation);
    _indexes[vaultId] = rebuilt;
    _publishIndexUpdate(vaultId);
  }

  /// Searches only runtime plaintext and never accesses persistent storage.
  List<MemberIndexEntry> search(String query, {String? vaultId}) {
    final normalized = query.trim().toLowerCase();
    final candidates = vaultId == null
        ? _indexes.values.expand((index) => index.values)
        : (_indexes[vaultId]?.values ?? const <MemberIndexEntry>[]);
    if (normalized.isEmpty) return candidates.toList(growable: false);
    return candidates
        .where(
          (entry) =>
              entry.memberLabel.toLowerCase().contains(normalized) ||
              entry.searchFields.any(
                (field) => field.toLowerCase().contains(normalized),
              ),
        )
        .toList(growable: false);
  }

  /// Returns one immutable runtime-only Vault index for local UI filtering.
  @override
  Future<void> waitForCurrent(String vaultId) async {
    final running = _running[vaultId];
    if (running != null) await running;
  }

  /// Returns one immutable runtime-only Vault index for local UI filtering.
  @override
  List<MemberIndexEntry> entries(String vaultId) =>
      List.unmodifiable(_indexes[vaultId]?.values ?? const []);

  /// Drops every decrypted projection immediately on lock/session loss.
  void lock() {
    _lockGeneration++;
    _running.clear();
    _indexes.clear();
  }

  Future<MemberSyncResult> _snapshot(
    String vaultId,
    Uint8List vaultKey,
    int minimumGeneration,
    int generation,
  ) async {
    final stagedIndex = <String, MemberIndexEntry>{};
    final firstPage = await _remote.snapshot(vaultId: vaultId);
    _requireCurrent(generation);
    _validatePageCount(firstPage.items);
    final baseSequence = firstPage.snapshotBaseSequence;

    Stream<MemberSyncItemModel> pages() async* {
      var page = firstPage;
      while (true) {
        _requireCurrent(generation);
        if (baseSequence != page.snapshotBaseSequence ||
            page.items.any((item) => item.isTombstone)) {
          throw const FormatException('Inconsistent Member snapshot');
        }
        final decrypted = await _decryptPage(
          page.items,
          vaultId,
          vaultKey,
          minimumGeneration,
        );
        _requireCurrent(generation);
        for (final entry in decrypted) {
          stagedIndex[entry.entryId] = entry;
          if (stagedIndex.length > maximumIndexedEntries) {
            throw StateError('Vault local index exceeds the device budget');
          }
        }
        for (final item in page.items) {
          yield item;
        }
        final cursor = page.nextCursor;
        if (cursor == null) return;
        page = await _remote.snapshot(vaultId: vaultId, cursor: cursor);
        _requireCurrent(generation);
        _validatePageCount(page.items);
      }
    }

    await _cache.replaceSnapshot(vaultId, baseSequence, pages());
    _requireCurrent(generation);
    _indexes[vaultId] = stagedIndex;
    _publishIndexUpdate(vaultId);
    return MemberSyncResult(
      sequence: baseSequence,
      entryCount: stagedIndex.length,
      usedSnapshot: true,
    );
  }

  Future<MemberSyncResult> _delta(
    String vaultId,
    String afterSequence,
    Uint8List vaultKey,
    int minimumGeneration,
    int generation,
  ) async {
    if (!_indexes.containsKey(vaultId)) {
      await _unlockCached(
        vaultId: vaultId,
        vaultKey: vaultKey,
        minimumMemberKeyGeneration: minimumGeneration,
        generation: generation,
      );
      _requireCurrent(generation);
    }
    String? continuation;
    var applied = afterSequence;
    do {
      final result = await _remote.delta(
        vaultId: vaultId,
        afterSequence: continuation == null ? applied : null,
        continuationCursor: continuation,
      );
      _requireCurrent(generation);
      if (result is MemberDeltaResetRequired) {
        return _snapshot(vaultId, vaultKey, minimumGeneration, generation);
      }
      final page = (result as MemberDeltaSuccess).page;
      _validatePageCount(page.items);
      if (BigInt.parse(page.appliedThroughSequence) < BigInt.parse(applied) ||
          BigInt.parse(page.appliedThroughSequence) >
              BigInt.parse(page.deltaUpperBound)) {
        throw const FormatException('Non-monotonic Member delta');
      }
      final heads = page.items.where((item) => !item.isTombstone).toList();
      final decrypted = await _decryptPage(
        heads,
        vaultId,
        vaultKey,
        minimumGeneration,
      );
      _requireCurrent(generation);
      await _cache.applyDelta(vaultId, page.appliedThroughSequence, page.items);
      _requireCurrent(generation);
      final index = _indexes[vaultId]!;
      for (final item in page.items.where((item) => item.isTombstone)) {
        index.remove(item.entryId);
      }
      for (final entry in decrypted) {
        index[entry.entryId] = entry;
      }
      if (index.length > maximumIndexedEntries) {
        lock();
        throw StateError('Vault local index exceeds the device budget');
      }
      applied = page.appliedThroughSequence;
      continuation = page.continuationCursor;
    } while (continuation != null);

    _publishIndexUpdate(vaultId);

    return MemberSyncResult(
      sequence: applied,
      entryCount: _indexes[vaultId]!.length,
      usedSnapshot: false,
    );
  }

  void _validatePageCount(List<MemberSyncItemModel> items) {
    if (items.length > VaultPerformanceBudget.maximumMemberSyncPageItems) {
      throw const FormatException('Member sync page exceeds item limit');
    }
  }

  void _requireCurrent(int generation) {
    if (generation != _lockGeneration) {
      throw const _MemberSyncInvalidated();
    }
  }

  void _publishIndexUpdate(String vaultId) {
    if (!_indexUpdates.isClosed) _indexUpdates.add(vaultId);
  }

  Future<List<MemberIndexEntry>> _decryptPage(
    List<MemberSyncItemModel> items,
    String vaultId,
    Uint8List vaultKey,
    int minimumGeneration,
  ) async {
    final output = <MemberIndexEntry>[];
    final failures = <String, int>{};
    for (var offset = 0; offset < items.length; offset += decryptConcurrency) {
      final end = (offset + decryptConcurrency).clamp(0, items.length);
      output.addAll(
        await Future.wait(
          items.sublist(offset, end).map((item) async {
            try {
              return await _decrypt(item, vaultId, vaultKey, minimumGeneration);
            } on FormatException {
              failures.update(
                'head-binding',
                (value) => value + 1,
                ifAbsent: () => 1,
              );
              return _corrupt(item);
            } on VaultPlaintextFormatException catch (error) {
              final code = _plaintextFailureCode(error.message);
              failures.update(code, (value) => value + 1, ifAbsent: () => 1);
              return _corrupt(item);
            } on EnvelopeException catch (error) {
              final code = switch (error.kind) {
                EnvelopeErrorKind.authenticationFailed =>
                  'envelope-authentication',
                EnvelopeErrorKind.invalidDescriptor => 'envelope-descriptor',
                EnvelopeErrorKind.invalidPayload => 'envelope-payload',
                EnvelopeErrorKind.unsupportedProtocol => 'envelope-protocol',
                EnvelopeErrorKind.unsupportedSuite => 'envelope-suite',
              };
              failures.update(code, (value) => value + 1, ifAbsent: () => 1);
              return _corrupt(item);
            }
          }),
        ),
      );
    }
    if (failures.isNotEmpty) {
      final summary = failures.entries
          .map((entry) => '${entry.key}:${entry.value}')
          .join(',');
      AppLogger.w(
        'Entry',
        'MemberIndex validation rejected page projections [$summary]',
      );
    }
    return output;
  }

  String _plaintextFailureCode(String message) {
    if (message.contains('urlDomain')) return 'plaintext-url-domain';
    if (message.contains('icon')) return 'plaintext-icon';
    if (message.contains('color')) return 'plaintext-color';
    if (message.contains('customIndex')) return 'plaintext-custom-index';
    if (message.contains('entryType')) return 'plaintext-entry-type';
    if (message.contains('memberLabel')) return 'plaintext-member-label';
    if (message.contains('searchFields')) return 'plaintext-search-fields';
    if (message.contains('compact MemberIndex')) return 'plaintext-compact';
    if (message.contains('schema') || message.contains('keys')) {
      return 'plaintext-shape';
    }
    return 'plaintext-contract';
  }

  Future<MemberIndexEntry> _decrypt(
    MemberSyncItemModel item,
    String vaultId,
    Uint8List vaultKey,
    int minimumGeneration,
  ) async {
    final entryKey = item.entryKey!;
    final memberIndex = item.memberIndex!;
    Uint8List? entryDek;
    try {
      _validateHeadCoordinates(
        item,
        vaultId,
        entryKey,
        memberIndex,
        minimumGeneration,
      );
      entryDek = await _entryCrypto.openEntryDek(
        entryKey: entryKey,
        vaultKey: vaultKey,
      );
      if (entryDek.length != 32) {
        throw const FormatException('Unwrapped Entry DEK must be 32 bytes');
      }
      final decoded = await _entryCrypto.openMemberIndex(
        envelope: memberIndex,
        vaultKey: entryDek,
      );
      return _parseIndex(item, decoded);
    } finally {
      entryDek?.fillRange(0, entryDek.length, 0);
    }
  }

  void _validateHeadCoordinates(
    MemberSyncItemModel item,
    String vaultId,
    Map<String, dynamic> entryKey,
    Map<String, dynamic> memberIndex,
    int minimumGeneration,
  ) {
    Map<String, dynamic> descriptor(Map<String, dynamic> envelope) {
      final value = envelope['descriptor'];
      if (value is! Map) throw const FormatException('Missing descriptor');
      return Map<String, dynamic>.from(value);
    }

    final key = descriptor(entryKey);
    final index = descriptor(memberIndex);
    final keyScope = key['scope'];
    final indexScope = index['scope'];
    final generation = key['memberKeyGeneration'];
    if (keyScope is! Map ||
        indexScope is! Map ||
        keyScope['vaultId'] != vaultId ||
        indexScope['vaultId'] != vaultId ||
        keyScope['entryId'] != item.entryId ||
        indexScope['entryId'] != item.entryId ||
        index['resourceRevision'] != item.memberIndexRevision ||
        key['keyVersion'] != item.currentKeyVersion ||
        index['keyVersion'] != item.currentKeyVersion ||
        generation != index['memberKeyGeneration'] ||
        generation is! int ||
        generation < minimumGeneration) {
      throw const FormatException('Member sync head binding mismatch');
    }
  }

  MemberIndexEntry _parseIndex(
    MemberSyncItemModel item,
    Map<String, dynamic> json,
  ) {
    if (!json.containsKey('schema')) {
      return _parseCompactIndex(item, json);
    }
    final index = MemberIndex.fromJson(Map<String, Object?>.from(json));
    final fields = <String>[
      index.memberLabel,
      ?index.description,
      ?index.username,
      ?index.urlDomain,
      for (final field in index.customIndex) ...[field.label, field.value],
    ];
    return MemberIndexEntry(
      entryId: item.entryId,
      entryType: index.entryType.index,
      memberLabel: index.memberLabel,
      searchFields: fields,
      revision: item.memberIndexRevision!,
      state: _state(item.state),
      autofillDomains: index.urlDomain == null ? const [] : [index.urlDomain!],
      iconReference: switch (index.icon) {
        GlyphVaultIcon(:final value) => 'builtin:$value',
        EncryptedAssetVaultIcon(:final assetId) => 'asset:$assetId',
        final PublicAssetVaultIcon icon => icon.reference,
        null => null,
      },
    );
  }

  /// Parses the compact MemberIndex contract emitted by the active web Vault
  /// v2 writer. This is a closed protocol variant, not a permissive legacy
  /// fallback: unknown keys and values fail closed as corrupt projections.
  MemberIndexEntry _parseCompactIndex(
    MemberSyncItemModel item,
    Map<String, dynamic> json,
  ) {
    const requiredKeys = {'memberLabel', 'entryType', 'searchFields'};
    const allowedKeys = {...requiredKeys, 'iconReference', 'autofillDomains'};
    if (!json.keys.toSet().containsAll(requiredKeys) ||
        json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const VaultPlaintextFormatException(
        'Invalid compact MemberIndex fields.',
      );
    }

    final memberLabel = _boundedUtf8String(
      json['memberLabel'],
      maximumBytes: 256,
      field: 'memberLabel',
    );
    final entryType = json['entryType'];
    if (entryType is! int || entryType < 0 || entryType > 3) {
      throw const VaultPlaintextFormatException('Invalid entryType.');
    }
    final rawSearchFields = json['searchFields'];
    if (rawSearchFields is! List || rawSearchFields.length > 16) {
      throw const VaultPlaintextFormatException('Invalid searchFields.');
    }
    final searchFields = rawSearchFields
        .map(
          (value) => _boundedUtf8String(
            value,
            maximumBytes: 8192,
            field: 'searchFields',
          ),
        )
        .toList(growable: false);
    if (searchFields.fold<int>(
          0,
          (total, value) => total + utf8.encode(value).length,
        ) >
        8192) {
      throw const VaultPlaintextFormatException(
        'MemberIndex searchFields exceed protocol limit.',
      );
    }
    final iconReference = json['iconReference'] == null
        ? null
        : _boundedUtf8String(
            json['iconReference'],
            maximumBytes: 1024,
            field: 'iconReference',
          );
    final rawAutofillDomains = json['autofillDomains'];
    if (rawAutofillDomains != null &&
        (rawAutofillDomains is! List || rawAutofillDomains.length > 16)) {
      throw const VaultPlaintextFormatException('Invalid autofillDomains.');
    }
    final List<String> autofillDomains = rawAutofillDomains == null
        ? const <String>[]
        : (rawAutofillDomains as List)
              .map<String>(
                (value) => _boundedUtf8String(
                  value,
                  maximumBytes: 2048,
                  field: 'autofillDomains',
                ),
              )
              .toList(growable: false);

    return MemberIndexEntry(
      entryId: item.entryId,
      entryType: entryType,
      memberLabel: memberLabel,
      searchFields: searchFields,
      revision: item.memberIndexRevision!,
      state: _state(item.state),
      autofillDomains: autofillDomains,
      iconReference: iconReference,
    );
  }

  String _boundedUtf8String(
    Object? value, {
    required int maximumBytes,
    required String field,
  }) {
    if (value is! String || utf8.encode(value).length > maximumBytes) {
      throw VaultPlaintextFormatException('Invalid $field.');
    }
    return value;
  }

  MemberIndexEntry _corrupt(MemberSyncItemModel item) => MemberIndexEntry(
    entryId: item.entryId,
    entryType: 1,
    memberLabel: _shortId(item.entryId),
    searchFields: const [],
    revision: item.memberIndexRevision!,
    state: _state(item.state),
    corrupt: true,
  );

  MemberEntryState _state(Object? value) => switch (value) {
    'active' || 'Active' || 0 || 1 => MemberEntryState.active,
    'archived' || 'Archived' || 2 => MemberEntryState.archived,
    'deleted' || 'Deleted' || 3 => MemberEntryState.deleted,
    _ => throw const FormatException('Malformed Member Entry state'),
  };

  String _shortId(String value) => value.length <= 15
      ? value
      : '${value.substring(0, 8)}…${value.substring(value.length - 6)}';

  Stream<List<MemberSyncItemModel>> _chunk(
    Stream<MemberSyncItemModel> source,
    int size,
  ) async* {
    var page = <MemberSyncItemModel>[];
    await for (final item in source) {
      page.add(item);
      if (page.length == size) {
        yield page;
        page = <MemberSyncItemModel>[];
      }
    }
    if (page.isNotEmpty) yield page;
  }
}

final class _MemberSyncInvalidated implements Exception {
  const _MemberSyncInvalidated();
}
