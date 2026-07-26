import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../domain/entities/member_index_entry.dart';
import '../datasources/member_sync_remote_datasource.dart';
import '../models/member_sync_models.dart';
import 'member_sync_cache.dart';
import 'vault_protocol/vault_protocol_aad.dart';
import 'vault_protocol/vault_protocol_envelope_service.dart';
import 'vault_protocol/vault_protocol_kdf.dart';

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
final class MemberSyncService {
  MemberSyncService({
    required MemberSyncRemote remote,
    required MemberSyncCache cache,
    required VaultEnvelopeCryptography envelopes,
    this.maximumIndexedEntries = 20000,
    this.decryptConcurrency = 2,
  }) : _remote = remote,
       _cache = cache,
       _envelopes = envelopes {
    if (maximumIndexedEntries < 1 || decryptConcurrency < 1) {
      throw ArgumentError('Member sync budgets must be positive');
    }
  }

  final MemberSyncRemote _remote;
  final MemberSyncCache _cache;
  final VaultEnvelopeCryptography _envelopes;
  final int maximumIndexedEntries;
  final int decryptConcurrency;

  final Map<String, Map<String, MemberIndexEntry>> _indexes = {};
  final Map<String, Future<MemberSyncResult>> _running = {};

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
    return _running.putIfAbsent(vaultId, () async {
      try {
        final sequence = await _cache.sequence(vaultId);
        if (sequence == null) {
          return _snapshot(vaultId, vaultKey, minimumMemberKeyGeneration);
        }
        return _delta(vaultId, sequence, vaultKey, minimumMemberKeyGeneration);
      } finally {
        _running.remove(vaultId);
      }
    });
  }

  /// Rebuilds the runtime index from the last complete ciphertext snapshot.
  Future<void> unlockCached({
    required String vaultId,
    required Uint8List vaultKey,
    required int minimumMemberKeyGeneration,
  }) async {
    final rebuilt = <String, MemberIndexEntry>{};
    await for (final page in _chunk(_cache.readHeads(vaultId), 100)) {
      final decrypted = await _decryptPage(
        page,
        vaultId,
        vaultKey,
        minimumMemberKeyGeneration,
      );
      for (final entry in decrypted) {
        rebuilt[entry.entryId] = entry;
        if (rebuilt.length > maximumIndexedEntries) {
          throw StateError('Vault local index exceeds the device budget');
        }
      }
    }
    _indexes[vaultId] = rebuilt;
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
  List<MemberIndexEntry> entries(String vaultId) =>
      List.unmodifiable(_indexes[vaultId]?.values ?? const []);

  /// Drops every decrypted projection immediately on lock/session loss.
  void lock() => _indexes.clear();

  Future<MemberSyncResult> _snapshot(
    String vaultId,
    Uint8List vaultKey,
    int minimumGeneration,
  ) async {
    final stagedIndex = <String, MemberIndexEntry>{};
    final firstPage = await _remote.snapshot(vaultId: vaultId);
    final baseSequence = firstPage.snapshotBaseSequence;

    Stream<MemberSyncItemModel> pages() async* {
      var page = firstPage;
      while (true) {
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
      }
    }

    await _cache.replaceSnapshot(vaultId, baseSequence, pages());
    _indexes[vaultId] = stagedIndex;
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
  ) async {
    if (!_indexes.containsKey(vaultId)) {
      await unlockCached(
        vaultId: vaultId,
        vaultKey: vaultKey,
        minimumMemberKeyGeneration: minimumGeneration,
      );
    }
    String? continuation;
    var applied = afterSequence;
    do {
      final result = await _remote.delta(
        vaultId: vaultId,
        afterSequence: continuation == null ? applied : null,
        continuationCursor: continuation,
      );
      if (result is MemberDeltaResetRequired) {
        return _snapshot(vaultId, vaultKey, minimumGeneration);
      }
      final page = (result as MemberDeltaSuccess).page;
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
      await _cache.applyDelta(vaultId, page.appliedThroughSequence, page.items);
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

    return MemberSyncResult(
      sequence: applied,
      entryCount: _indexes[vaultId]!.length,
      usedSnapshot: false,
    );
  }

  Future<List<MemberIndexEntry>> _decryptPage(
    List<MemberSyncItemModel> items,
    String vaultId,
    Uint8List vaultKey,
    int minimumGeneration,
  ) async {
    final output = <MemberIndexEntry>[];
    for (var offset = 0; offset < items.length; offset += decryptConcurrency) {
      final end = (offset + decryptConcurrency).clamp(0, items.length);
      output.addAll(
        await Future.wait(
          items.sublist(offset, end).map((item) async {
            try {
              return await _decrypt(item, vaultId, vaultKey, minimumGeneration);
            } on FormatException {
              return _corrupt(item);
            }
          }),
        ),
      );
    }
    return output;
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
    Uint8List? memberIndexKey;
    Uint8List? plaintext;
    try {
      final expectedEntryKey = Map<String, Object?>.from(entryKey)
        ..['vaultId'] = vaultId
        ..['entryId'] = item.entryId
        ..['keyVersion'] = item.currentKeyVersion;
      entryDek = await _envelopes.decrypt(
        profile: VaultAadProfile.entryKeyWrapper,
        envelope: entryKey,
        key: vaultKey,
        expected: VaultEnvelopeExpectations(
          aadContext: expectedEntryKey,
          minimumMemberKeyGeneration: minimumGeneration,
        ),
      );
      if (entryDek.length != 32) {
        throw const FormatException('Unwrapped Entry DEK must be 32 bytes');
      }
      final header = Map<String, dynamic>.from(memberIndex['header'] as Map);
      final expectedMemberIndex = Map<String, Object?>.from(memberIndex)
        ..['vaultId'] = vaultId
        ..['entryId'] = item.entryId
        ..['memberIndexRevision'] = item.memberIndexRevision;
      memberIndexKey = deriveVaultProjectionKey(
        entryDek,
        VaultKdfContext(
          purpose: VaultKdfPurpose.memberIndex,
          resourceKind: 2,
          organizationId: memberIndex['organizationId']! as String,
          vaultId: memberIndex['vaultId']! as String,
          entryId: item.entryId,
          keyVersion: header['keyVersion']! as int,
          memberKeyGeneration: header['memberKeyGeneration']! as int,
        ),
      );
      plaintext = await _envelopes.decrypt(
        profile: VaultAadProfile.memberIndex,
        envelope: memberIndex,
        key: memberIndexKey,
        expected: VaultEnvelopeExpectations(
          aadContext: expectedMemberIndex,
          minimumMemberKeyGeneration: minimumGeneration,
        ),
      );
      if (plaintext.length > 32752) {
        throw const FormatException('Member index plaintext exceeds limit');
      }
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map) {
        throw const FormatException('Member index payload must be an object');
      }
      return _parseIndex(item, Map<String, dynamic>.from(decoded));
    } finally {
      entryDek?.fillRange(0, entryDek.length, 0);
      memberIndexKey?.fillRange(0, memberIndexKey.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  MemberIndexEntry _parseIndex(
    MemberSyncItemModel item,
    Map<String, dynamic> json,
  ) {
    const allowed = {
      'entryType',
      'iconReference',
      'memberLabel',
      'searchFields',
    };
    if (json.keys.any((key) => !allowed.contains(key)) ||
        json['entryType'] is! int ||
        json['memberLabel'] is! String ||
        json['searchFields'] is! List ||
        (json['iconReference'] != null && json['iconReference'] is! String)) {
      throw const FormatException('Malformed Member index payload');
    }
    final label = json['memberLabel']! as String;
    final fields = (json['searchFields']! as List)
        .map((value) {
          if (value is! String) {
            throw const FormatException('Search field must be a string');
          }
          return value;
        })
        .toList(growable: false);
    if (label.length > 512 ||
        fields.length > 64 ||
        fields.any((field) => field.length > 512)) {
      throw const FormatException('Member index exceeds local limits');
    }
    return MemberIndexEntry(
      entryId: item.entryId,
      entryType: json['entryType']! as int,
      memberLabel: label,
      searchFields: fields,
      revision: item.memberIndexRevision!,
      state: _state(item.state),
      iconReference: json['iconReference'] as String?,
    );
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
