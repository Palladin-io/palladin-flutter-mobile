import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../domain/entities/member_index_entry.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../domain/entities/vault_performance_budget.dart';
import '../../domain/entities/vault_plaintext.dart';
import '../datasources/member_sync_remote_datasource.dart';
import '../models/member_sync_models.dart';
import 'entry_v2_crypto_service.dart';
import 'member_sync_cache.dart';
import 'vault_rotation_crypto_service.dart';

/// Authenticated session claims used as independent authority for cached
/// access-context bindings. Values come from the current verified API token.
final class MemberSyncSessionAuthority {
  const MemberSyncSessionAuthority({
    required this.principalId,
    required this.organizationId,
    required this.organizationMembershipGeneration,
    required this.offlinePolicy,
    required this.offlinePolicyVersion,
  });

  final String principalId;
  final String organizationId;
  final String organizationMembershipGeneration;
  final String offlinePolicy;
  final int offlinePolicyVersion;
}

/// Complete opaque local current Entry generation exposed to CVT-561 and
/// local reveal. No plaintext or raw key is retained by this value.
final class LocalMemberEntryMaterial {
  const LocalMemberEntryMaterial({
    required this.item,
    required this.accessContext,
    required this.memberVaultKey,
    required this.readGeneration,
  });

  final MemberSyncItemModel item;
  final MemberOfflineAccessContext accessContext;
  final Map<String, dynamic> memberVaultKey;
  final int readGeneration;
}

/// Raised when a local ciphertext read loses its lock, lease, or access fence.
final class LocalMemberEntryReadInvalidatedException implements Exception {
  const LocalMemberEntryReadInvalidatedException();
}

/// Public ciphertext reader for one complete, active local Entry head.
abstract interface class LocalMemberEntryReader {
  Future<LocalMemberEntryMaterial?> readCurrent({
    required String vaultId,
    required String entryId,
    required MemberSyncSessionAuthority authority,
  });

  /// Revalidates the read fence after asynchronous decryption and immediately
  /// before plaintext is returned to a caller.
  Future<void> revalidateCurrent({
    required String vaultId,
    required String entryId,
    required LocalMemberEntryMaterial material,
    required MemberSyncSessionAuthority authority,
  });
}

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

/// Signals that the server returned heads from a newer Member key generation
/// than the encrypted Vault-key context used for this synchronization.
///
/// Callers must fetch a fresh authenticated Member Vault key context and retry
/// instead of advancing the ciphertext cache with projections that cannot be
/// authenticated by the stale key.
final class MemberVaultKeyContextStaleException implements Exception {
  const MemberVaultKeyContextStaleException({required this.requiredGeneration});

  final int requiredGeneration;
}

/// Coordinates bounded network sync, ciphertext persistence, and the unlocked
/// in-memory search index. Call [lock] whenever the Vault session is locked.
abstract interface class MemberIndexReader {
  Future<void> waitForCurrent(String vaultId);

  List<MemberIndexEntry> entries(String vaultId);
}

/// Signals complete local generations/deltas after both durable and runtime
/// candidate indexes are committed.
abstract interface class DurableMemberIndexUpdates {
  Stream<String> get durableUpdates;

  Future<void> waitForCurrent(String vaultId);
}

abstract interface class MemberSyncCoordinator implements MemberIndexReader {
  Future<MemberSyncResult> synchronize({
    required String vaultId,
    required Uint8List vaultKey,
    required int minimumMemberKeyGeneration,
    required MemberSyncSessionAuthority authority,
    required Map<String, dynamic> authoritativeMemberVaultKey,
  });

  Future<void> unlockCached({
    required String vaultId,
    required Uint8List memberPrivateKey,
    required MemberSyncSessionAuthority authority,
  });

  Future<List<String>> unlockAllCached({
    required Uint8List memberPrivateKey,
    required MemberSyncSessionAuthority authority,
  });

  Future<void> purgeVault(String vaultId);

  void lock();
}

final class MemberSyncService
    implements
        MemberSyncCoordinator,
        DurableMemberIndexUpdates,
        LocalMemberEntryReader,
        CurrentEntryCacheInvalidator {
  MemberSyncService({
    required MemberSyncRemote remote,
    required MemberSyncCache cache,
    required EntryV2CryptoService entryCrypto,
    required VaultRotationCryptoService vaultKeys,
    DateTime Function()? now,
    this.maximumIndexedEntries = VaultPerformanceBudget.maximumIndexedEntries,
    this.decryptConcurrency =
        VaultPerformanceBudget.memberIndexDecryptConcurrency,
    this.maximumSnapshotRestarts = 2,
  }) : _remote = remote,
       _cache = cache,
       _entryCrypto = entryCrypto,
       _vaultKeys = vaultKeys,
       _now = now ?? DateTime.now {
    if (maximumIndexedEntries < 1 ||
        decryptConcurrency < 1 ||
        maximumSnapshotRestarts < 0) {
      throw ArgumentError('Member sync budgets must be positive');
    }
  }

  final MemberSyncRemote _remote;
  final MemberSyncCache _cache;
  final EntryV2CryptoService _entryCrypto;
  final VaultRotationCryptoService _vaultKeys;
  final DateTime Function() _now;
  final int maximumIndexedEntries;
  final int decryptConcurrency;
  final int maximumSnapshotRestarts;

  final Map<String, Map<String, MemberIndexEntry>> _indexes = {};
  final Map<String, Future<MemberSyncResult>> _running = {};
  final StreamController<String> _indexUpdates =
      StreamController<String>.broadcast();
  final StreamController<String> _durableUpdates =
      StreamController<String>.broadcast();
  final Set<String> _connectedSessionVaults = {};
  final Set<String> _revokedVaults = {};
  final Set<String> _knownVaults = {};
  bool _profileQuarantined = false;
  final Map<String, Timer> _leaseTimers = {};
  final Map<String, Future<void>> _vaultCommitTails = {};
  int _lockGeneration = 0;
  int _sessionEpoch = 0;

  /// Emits a Vault id after its unlocked runtime index has been installed or
  /// refreshed. Consumers use this signal to refresh local presentation only;
  /// no plaintext leaves the service through the stream.
  Stream<String> get indexUpdates => _indexUpdates.stream;

  /// Emits only after a complete generation or delta is durably committed.
  @override
  Stream<String> get durableUpdates => _durableUpdates.stream;

  /// Synchronizes one Vault. Concurrent callers for the same Vault share work.
  @override
  Future<MemberSyncResult> synchronize({
    required String vaultId,
    required Uint8List vaultKey,
    required int minimumMemberKeyGeneration,
    required MemberSyncSessionAuthority authority,
    required Map<String, dynamic> authoritativeMemberVaultKey,
  }) {
    _knownVaults.add(vaultId);
    if (_profileQuarantined) {
      return Future.error(const MemberSyncProfileQuarantinedException());
    }
    if (vaultKey.length != 32) {
      return Future.error(
        const FormatException('Vault key must be exactly 32 bytes'),
      );
    }
    final active = _running[vaultId];
    if (active != null) return active;
    final generation = _lockGeneration;
    final core = _synchronizeWithBoundedSnapshots(
      vaultId: vaultId,
      vaultKey: vaultKey,
      minimumMemberKeyGeneration: minimumMemberKeyGeneration,
      authority: authority,
      authoritativeMemberVaultKey: authoritativeMemberVaultKey,
      generation: generation,
    );
    late final Future<MemberSyncResult> operation;
    operation = core.whenComplete(() {
      if (identical(_running[vaultId], operation)) {
        _running.remove(vaultId);
      }
    });
    _running[vaultId] = operation;
    return operation;
  }

  Future<MemberSyncResult> _synchronizeWithBoundedSnapshots({
    required String vaultId,
    required Uint8List vaultKey,
    required int minimumMemberKeyGeneration,
    required MemberSyncSessionAuthority authority,
    required Map<String, dynamic> authoritativeMemberVaultKey,
    required int generation,
  }) async {
    var forceSnapshot = false;
    var snapshotRestarts = 0;
    while (true) {
      try {
        if (forceSnapshot) {
          return await _snapshot(
            vaultId,
            vaultKey,
            minimumMemberKeyGeneration,
            authority,
            authoritativeMemberVaultKey,
            generation,
            invalidateActive: true,
          );
        }
        return await _synchronizeOnce(
          vaultId: vaultId,
          vaultKey: vaultKey,
          minimumMemberKeyGeneration: minimumMemberKeyGeneration,
          authority: authority,
          authoritativeMemberVaultKey: authoritativeMemberVaultKey,
          generation: generation,
        );
      } on _MemberSnapshotRestartRequired catch (error) {
        if (error.afterSnapshot) {
          if (snapshotRestarts >= maximumSnapshotRestarts) {
            _indexes.remove(vaultId);
            _publishIndexUpdate(vaultId);
            throw StateError('Member snapshot restart limit exceeded');
          }
          snapshotRestarts += 1;
        }
        forceSnapshot = true;
      }
    }
  }

  Future<MemberSyncResult> _synchronizeOnce({
    required String vaultId,
    required Uint8List vaultKey,
    required int minimumMemberKeyGeneration,
    required MemberSyncSessionAuthority authority,
    required Map<String, dynamic> authoritativeMemberVaultKey,
    required int generation,
  }) async {
    final cached = await _cache.state(vaultId);
    _requireCurrent(generation);
    if (cached == null) {
      return _snapshot(
        vaultId,
        vaultKey,
        minimumMemberKeyGeneration,
        authority,
        authoritativeMemberVaultKey,
        generation,
        invalidateActive: false,
      );
    }
    try {
      _validateCachedAuthority(
        vaultId: vaultId,
        state: cached,
        authority: authority,
        allowConnectedDisabledPolicy: true,
      );
    } on FormatException {
      await _purgeVault(vaultId, invalidateInFlight: false);
      return _snapshot(
        vaultId,
        vaultKey,
        minimumMemberKeyGeneration,
        authority,
        authoritativeMemberVaultKey,
        generation,
        invalidateActive: true,
      );
    }
    return _delta(
      vaultId,
      cached.sequence,
      vaultKey,
      minimumMemberKeyGeneration,
      authority,
      authoritativeMemberVaultKey,
      generation,
    );
  }

  /// Rebuilds the runtime index from the last complete ciphertext snapshot.
  @override
  Future<void> unlockCached({
    required String vaultId,
    required Uint8List memberPrivateKey,
    required MemberSyncSessionAuthority authority,
  }) async {
    _knownVaults.add(vaultId);
    final generation = _lockGeneration;
    if (_profileQuarantined || _revokedVaults.contains(vaultId)) return;
    final MemberSyncCacheState? state;
    try {
      state = await _cache.state(vaultId);
    } on MemberSyncProfileQuarantinedException {
      _profileQuarantined = true;
      return;
    }
    if (state == null) return;
    try {
      _validateCachedAuthority(
        vaultId: vaultId,
        state: state,
        authority: authority,
        allowConnectedDisabledPolicy: false,
      );
      final vaultKey = await _vaultKeys.openMemberVaultKey(
        state.memberVaultKey,
        memberPrivateKey,
        expectedOrganizationId: authority.organizationId,
        expectedVaultId: vaultId,
        expectedVaultKeyVersion: state.accessContext.vaultKeyVersion,
        expectedMemberKeyGeneration: state.accessContext.memberKeyGeneration,
      );
      try {
        await _unlockCached(
          vaultId: vaultId,
          organizationId: authority.organizationId,
          vaultKey: vaultKey,
          minimumMemberKeyGeneration: state.accessContext.memberKeyGeneration,
          expectedVaultKeyVersion: state.accessContext.vaultKeyVersion,
          generation: generation,
        );
        _scheduleLeaseExpiry(vaultId, state.accessContext);
      } finally {
        vaultKey.fillRange(0, vaultKey.length, 0);
      }
    } on _MemberSyncInvalidated {
      // lock() already revoked every runtime projection. Preserve this typed
      // session fence even if Vault-local durable cleanup would fail.
      rethrow;
    } on Object {
      await purgeVault(vaultId);
      rethrow;
    }
  }

  /// Rebuilds every complete persisted Vault generation without consulting
  /// the Vault-list or per-Vault HTTP endpoints.
  ///
  /// [unlockCached] still validates every generation independently against
  /// the authenticated [authority] before its local index becomes readable.
  @override
  Future<List<String>> unlockAllCached({
    required Uint8List memberPrivateKey,
    required MemberSyncSessionAuthority authority,
  }) async {
    if (memberPrivateKey.length != 32) {
      throw const FormatException('Member private key must be 32 bytes');
    }
    final sessionEpoch = _sessionEpoch;
    final vaultIds = await _cache.vaultIds();
    _requireSessionEpoch(sessionEpoch);
    final reopenedVaultIds = <String>[];
    for (final vaultId in vaultIds) {
      _requireSessionEpoch(sessionEpoch);
      try {
        await unlockCached(
          vaultId: vaultId,
          memberPrivateKey: memberPrivateKey,
          authority: authority,
        );
        _requireSessionEpoch(sessionEpoch);
        if (_indexes.containsKey(vaultId)) reopenedVaultIds.add(vaultId);
      } on _MemberSyncInvalidated {
        // Lock/session replacement invalidates the entire reopen operation.
        // Continuing would let later Vaults capture the new generation and
        // repopulate plaintext indexes after lock() cleared them.
        rethrow;
      } on Object {
        // unlockCached purges and revokes only the invalid Vault. Continue so
        // one corrupt or expired generation cannot suppress independent valid
        // offline Vaults from the exact native replacement.
      }
    }
    _requireSessionEpoch(sessionEpoch);
    return List<String>.unmodifiable(reopenedVaultIds);
  }

  Future<void> _unlockCached({
    required String vaultId,
    required String organizationId,
    required Uint8List vaultKey,
    required int minimumMemberKeyGeneration,
    required int expectedVaultKeyVersion,
    required int generation,
  }) async {
    final rebuilt = <String, MemberIndexEntry>{};
    await for (final page in _chunk(_cache.readHeads(vaultId), 100)) {
      _requireCurrent(generation);
      final decrypted = await _decryptPage(
        page,
        organizationId,
        vaultId,
        vaultKey,
        minimumMemberKeyGeneration,
        expectedVaultKeyVersion,
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
  @override
  void lock() {
    _sessionEpoch++;
    _lockGeneration++;
    _running.clear();
    _indexes.clear();
    _connectedSessionVaults.clear();
  }

  Future<MemberSyncResult> _snapshot(
    String vaultId,
    Uint8List vaultKey,
    int minimumGeneration,
    MemberSyncSessionAuthority authority,
    Map<String, dynamic> authoritativeMemberVaultKey,
    int generation, {
    required bool invalidateActive,
  }) async {
    final stagedIndex = <String, MemberIndexEntry>{};
    await _cache.beginSnapshot(vaultId, invalidateActive: invalidateActive);
    try {
      var page = await _remote.snapshot(vaultId: vaultId);
      _requireCurrent(generation);
      _validatePageCount(page.items);
      final baseSequence = page.snapshotBaseSequence;
      late MemberOfflineAccessContext accessContext;
      late Map<String, dynamic> memberVaultKey;
      MemberOfflineAccessContext? previousAccessContext;
      while (true) {
        _requireCurrent(generation);
        if (baseSequence != page.snapshotBaseSequence ||
            page.items.any((item) => item.isTombstone)) {
          throw const FormatException('Inconsistent Member snapshot');
        }
        _validateRemoteAuthority(
          vaultId: vaultId,
          context: page.accessContext,
          memberVaultKey: page.memberVaultKey,
          authority: authority,
          minimumMemberKeyGeneration: minimumGeneration,
          authoritativeMemberVaultKey: authoritativeMemberVaultKey,
        );
        _validateAccessContextContinuation(
          previousAccessContext,
          page.accessContext,
        );
        previousAccessContext = page.accessContext;
        accessContext = page.accessContext;
        memberVaultKey = page.memberVaultKey;
        _requireKeyContextCovers(page.items, minimumGeneration);
        final decrypted = await _decryptPage(
          page.items,
          authority.organizationId,
          vaultId,
          vaultKey,
          minimumGeneration,
          page.accessContext.vaultKeyVersion,
        );
        _requireCurrent(generation);
        for (final entry in decrypted) {
          stagedIndex[entry.entryId] = entry;
          if (stagedIndex.length > maximumIndexedEntries) {
            throw StateError('Vault local index exceeds the device budget');
          }
        }
        await _cache.appendSnapshot(vaultId, page.items);
        final cursor = page.nextCursor;
        if (cursor == null) break;
        page = await _remote.snapshot(vaultId: vaultId, cursor: cursor);
        _requireCurrent(generation);
        _validatePageCount(page.items);
      }
      final closed = await _closeSnapshotDelta(
        vaultId: vaultId,
        afterSequence: baseSequence,
        vaultKey: vaultKey,
        minimumGeneration: minimumGeneration,
        authority: authority,
        authoritativeMemberVaultKey: authoritativeMemberVaultKey,
        generation: generation,
        stagedIndex: stagedIndex,
        initialAccessContext: accessContext,
        initialMemberVaultKey: memberVaultKey,
      );
      return MemberSyncResult(
        sequence: closed,
        entryCount: stagedIndex.length,
        usedSnapshot: true,
      );
    } catch (_) {
      await _cache.discardSnapshot(vaultId);
      rethrow;
    }
  }

  Future<String> _closeSnapshotDelta({
    required String vaultId,
    required String afterSequence,
    required Uint8List vaultKey,
    required int minimumGeneration,
    required MemberSyncSessionAuthority authority,
    required Map<String, dynamic> authoritativeMemberVaultKey,
    required int generation,
    required Map<String, MemberIndexEntry> stagedIndex,
    required MemberOfflineAccessContext initialAccessContext,
    required Map<String, dynamic> initialMemberVaultKey,
  }) async {
    String? continuation;
    var applied = afterSequence;
    var accessContext = initialAccessContext;
    var memberVaultKey = initialMemberVaultKey;
    do {
      final result = await _remote.delta(
        vaultId: vaultId,
        afterSequence: continuation == null ? applied : null,
        continuationCursor: continuation,
      );
      _requireCurrent(generation);
      if (result is MemberDeltaResetRequired) {
        await _purgeVault(vaultId, invalidateInFlight: false);
        throw const _MemberSnapshotRestartRequired(afterSnapshot: true);
      }
      final page = (result as MemberDeltaSuccess).page;
      _validateDeltaPage(page, applied);
      _validateRemoteAuthority(
        vaultId: vaultId,
        context: page.accessContext,
        memberVaultKey: page.memberVaultKey,
        authority: authority,
        minimumMemberKeyGeneration: minimumGeneration,
        authoritativeMemberVaultKey: authoritativeMemberVaultKey,
      );
      _validateAccessContextContinuation(accessContext, page.accessContext);
      accessContext = page.accessContext;
      memberVaultKey = page.memberVaultKey;
      final heads = page.items.where((item) => !item.isTombstone).toList();
      _requireKeyContextCovers(heads, minimumGeneration);
      final decrypted = await _decryptPage(
        heads,
        authority.organizationId,
        vaultId,
        vaultKey,
        minimumGeneration,
        page.accessContext.vaultKeyVersion,
      );
      _requireCurrent(generation);
      await _cache.applyStagedDelta(vaultId, page.items);
      for (final item in page.items.where((item) => item.isTombstone)) {
        stagedIndex.remove(item.entryId);
      }
      for (final entry in decrypted) {
        stagedIndex[entry.entryId] = entry;
      }
      if (stagedIndex.length > maximumIndexedEntries) {
        throw StateError('Vault local index exceeds the device budget');
      }
      applied = page.appliedThroughSequence;
      continuation = page.continuationCursor;
    } while (continuation != null);

    final observed = _now().toUtc();
    await _commitCache(
      vaultId,
      generation,
      () => _cache.promoteSnapshot(
        vaultId,
        sequence: applied,
        accessContext: accessContext,
        memberVaultKey: memberVaultKey,
        maximumObservedWallTime: observed,
      ),
    );
    _requireCurrent(generation);
    _indexes[vaultId] = stagedIndex;
    _connectedSessionVaults.add(vaultId);
    _revokedVaults.remove(vaultId);
    _scheduleLeaseExpiry(vaultId, accessContext);
    _publishDurableUpdate(vaultId);
    _publishIndexUpdate(vaultId);
    return applied;
  }

  Future<MemberSyncResult> _delta(
    String vaultId,
    String afterSequence,
    Uint8List vaultKey,
    int minimumGeneration,
    MemberSyncSessionAuthority authority,
    Map<String, dynamic> authoritativeMemberVaultKey,
    int generation, {
    bool afterSnapshot = false,
  }) async {
    final cachedState = await _cache.state(vaultId);
    if (cachedState == null) {
      throw const FormatException('Missing active Member sync state');
    }
    if (!_indexes.containsKey(vaultId)) {
      await _unlockCached(
        vaultId: vaultId,
        organizationId: authority.organizationId,
        vaultKey: vaultKey,
        minimumMemberKeyGeneration: minimumGeneration,
        expectedVaultKeyVersion: cachedState.accessContext.vaultKeyVersion,
        generation: generation,
      );
      _requireCurrent(generation);
    }
    String? continuation;
    var applied = afterSequence;
    MemberOfflineAccessContext? previousAccessContext =
        cachedState.accessContext;
    do {
      final result = await _remote.delta(
        vaultId: vaultId,
        afterSequence: continuation == null ? applied : null,
        continuationCursor: continuation,
      );
      _requireCurrent(generation);
      if (result is MemberDeltaResetRequired) {
        await _purgeVault(vaultId, invalidateInFlight: false);
        throw _MemberSnapshotRestartRequired(afterSnapshot: afterSnapshot);
      }
      final page = (result as MemberDeltaSuccess).page;
      _validateDeltaPage(page, applied);
      _validateRemoteAuthority(
        vaultId: vaultId,
        context: page.accessContext,
        memberVaultKey: page.memberVaultKey,
        authority: authority,
        minimumMemberKeyGeneration: minimumGeneration,
        authoritativeMemberVaultKey: authoritativeMemberVaultKey,
      );
      _validateAccessContextContinuation(
        previousAccessContext,
        page.accessContext,
      );
      previousAccessContext = page.accessContext;
      final heads = page.items.where((item) => !item.isTombstone).toList();
      _requireKeyContextCovers(heads, minimumGeneration);
      final decrypted = await _decryptPage(
        heads,
        authority.organizationId,
        vaultId,
        vaultKey,
        minimumGeneration,
        page.accessContext.vaultKeyVersion,
      );
      _requireCurrent(generation);
      await _commitCache(
        vaultId,
        generation,
        () async => _cache.applyDelta(
          vaultId,
          sequence: page.appliedThroughSequence,
          items: page.items,
          accessContext: page.accessContext,
          memberVaultKey: page.memberVaultKey,
          maximumObservedWallTime: _maximumObservedWallTime(
            await _cache.state(vaultId),
          ),
        ),
      );
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
      // Consumers may rebuild native/search projections from this signal, so
      // publish only after both the durable delta and its current runtime index
      // are committed. No observer can see the previous candidate set.
      _publishDurableUpdate(vaultId);
      applied = page.appliedThroughSequence;
      continuation = page.continuationCursor;
    } while (continuation != null);

    _connectedSessionVaults.add(vaultId);
    _revokedVaults.remove(vaultId);
    final state = await _cache.state(vaultId);
    if (state != null) _scheduleLeaseExpiry(vaultId, state.accessContext);
    _publishIndexUpdate(vaultId);

    return MemberSyncResult(
      sequence: applied,
      entryCount: _indexes[vaultId]!.length,
      usedSnapshot: false,
    );
  }

  @override
  Future<LocalMemberEntryMaterial?> readCurrent({
    required String vaultId,
    required String entryId,
    required MemberSyncSessionAuthority authority,
  }) async {
    _knownVaults.add(vaultId);
    final generation = _lockGeneration;
    if (_profileQuarantined || _revokedVaults.contains(vaultId)) return null;
    final MemberSyncCacheState? state;
    try {
      state = await _cache.state(vaultId);
    } on MemberSyncProfileQuarantinedException {
      _profileQuarantined = true;
      return null;
    }
    if (state == null) return null;
    try {
      _validateCachedAuthority(
        vaultId: vaultId,
        state: state,
        authority: authority,
        allowConnectedDisabledPolicy: true,
      );
      final item = await _cache.readHead(vaultId, entryId);
      if (item == null) return null;
      _validateHeadCoordinates(
        item,
        authority.organizationId,
        vaultId,
        item.entryKey!,
        item.memberIndex!,
        state.accessContext.memberKeyGeneration,
        state.accessContext.vaultKeyVersion,
      );
      _validateSecretCoordinates(
        item,
        authority.organizationId,
        vaultId,
        item.memberSecret!,
        state.accessContext.memberKeyGeneration,
      );
      _requireReadable(vaultId, generation);
      return LocalMemberEntryMaterial(
        item: item,
        accessContext: state.accessContext,
        memberVaultKey: Map<String, dynamic>.unmodifiable(state.memberVaultKey),
        readGeneration: generation,
      );
    } on LocalMemberEntryReadInvalidatedException {
      rethrow;
    } on Object {
      await purgeVault(vaultId);
      rethrow;
    }
  }

  @override
  Future<void> revalidateCurrent({
    required String vaultId,
    required String entryId,
    required LocalMemberEntryMaterial material,
    required MemberSyncSessionAuthority authority,
  }) async {
    try {
      _requireReadable(vaultId, material.readGeneration);
      final state = await _cache.state(vaultId);
      _requireReadable(vaultId, material.readGeneration);
      if (state == null ||
          _canonicalJson(state.accessContext.toJson()) !=
              _canonicalJson(material.accessContext.toJson()) ||
          _canonicalJson(state.memberVaultKey) !=
              _canonicalJson(material.memberVaultKey)) {
        throw const LocalMemberEntryReadInvalidatedException();
      }
      _validateCachedAuthority(
        vaultId: vaultId,
        state: state,
        authority: authority,
        allowConnectedDisabledPolicy: true,
      );
      final current = await _cache.readHead(vaultId, entryId);
      _requireReadable(vaultId, material.readGeneration);
      if (current == null ||
          current.currentRevision != material.item.currentRevision ||
          current.memberIndexRevision != material.item.memberIndexRevision ||
          current.currentKeyVersion != material.item.currentKeyVersion ||
          _canonicalJson(current.entryKey) !=
              _canonicalJson(material.item.entryKey) ||
          _canonicalJson(current.memberSecret) !=
              _canonicalJson(material.item.memberSecret)) {
        throw const LocalMemberEntryReadInvalidatedException();
      }
    } on LocalMemberEntryReadInvalidatedException {
      rethrow;
    } on Object {
      try {
        await purgeVault(vaultId);
      } on Object {
        // The in-memory revocation fence is installed before durable cleanup.
      }
      throw const LocalMemberEntryReadInvalidatedException();
    }
  }

  /// Purges one active and staged generation after access loss/removal.
  @override
  Future<void> purgeVault(String vaultId) =>
      _purgeVault(vaultId, invalidateInFlight: true);

  Future<void> _purgeVault(
    String vaultId, {
    required bool invalidateInFlight,
  }) async {
    _revokedVaults.add(vaultId);
    if (invalidateInFlight) {
      _lockGeneration++;
      _running.clear();
    }
    _leaseTimers.remove(vaultId)?.cancel();
    _indexes.remove(vaultId);
    _connectedSessionVaults.remove(vaultId);
    _publishIndexUpdate(vaultId);
    await _serializeVault(vaultId, () => _cache.clearVault(vaultId));
    _publishDurableUpdate(vaultId);
  }

  /// Deletes the complete local profile on logout.
  Future<void> purgeAll() async {
    _sessionEpoch++;
    final operationGeneration = ++_lockGeneration;
    _profileQuarantined = true;
    _running.clear();
    _revokedVaults.addAll(_knownVaults);
    for (final timer in _leaseTimers.values) {
      timer.cancel();
    }
    _leaseTimers.clear();
    _indexes.clear();
    _connectedSessionVaults.clear();
    final quarantineGeneration = await _cache.quarantineProfile();
    await Future.wait(_vaultCommitTails.values.toList(growable: false));
    final cleared = await _cache.clearQuarantinedProfile(quarantineGeneration);
    if (!cleared || operationGeneration != _lockGeneration) return;
    _revokedVaults.clear();
    _knownVaults.clear();
    _profileQuarantined = false;
    _publishDurableUpdate('*');
  }

  @override
  Future<void> clearCurrentEntryCache() => purgeAll();

  Future<T> _commitCache<T>(
    String vaultId,
    int generation,
    Future<T> Function() operation,
  ) => _serializeVault(vaultId, () {
    _requireCurrent(generation);
    return operation();
  });

  Future<T> _serializeVault<T>(String vaultId, Future<T> Function() operation) {
    final previous = _vaultCommitTails[vaultId] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> tail;
    tail = previous
        .then<void>((_) {}, onError: (_, _) {})
        .then<void>((_) async {
          try {
            completer.complete(await operation());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .whenComplete(() {
          if (identical(_vaultCommitTails[vaultId], tail)) {
            _vaultCommitTails.remove(vaultId);
          }
        });
    _vaultCommitTails[vaultId] = tail;
    return completer.future;
  }

  void _validateDeltaPage(MemberDeltaPage page, String applied) {
    _validatePageCount(page.items);
    final appliedValue = BigInt.parse(page.appliedThroughSequence);
    final previousValue = BigInt.parse(applied);
    final upperBound = BigInt.parse(page.deltaUpperBound);
    if (appliedValue < previousValue || appliedValue > upperBound) {
      throw const FormatException('Non-monotonic Member delta');
    }
    if ((page.continuationCursor == null && appliedValue != upperBound) ||
        (page.continuationCursor != null && appliedValue >= upperBound)) {
      throw const FormatException('Invalid Member delta boundary');
    }
  }

  DateTime _maximumObservedWallTime(MemberSyncCacheState? state) {
    final now = _now().toUtc();
    final previous = state?.maximumObservedWallTime;
    return previous != null && previous.isAfter(now) ? previous : now;
  }

  void _validateRemoteAuthority({
    required String vaultId,
    required MemberOfflineAccessContext context,
    required Map<String, dynamic> memberVaultKey,
    required MemberSyncSessionAuthority authority,
    required int minimumMemberKeyGeneration,
    required Map<String, dynamic> authoritativeMemberVaultKey,
  }) {
    _validateContextCoordinates(
      vaultId: vaultId,
      context: context,
      authority: authority,
    );
    if (context.memberKeyGeneration > minimumMemberKeyGeneration) {
      throw MemberVaultKeyContextStaleException(
        requiredGeneration: context.memberKeyGeneration,
      );
    }
    if (context.memberKeyGeneration < minimumMemberKeyGeneration ||
        _canonicalJson(memberVaultKey) !=
            _canonicalJson(authoritativeMemberVaultKey)) {
      throw const FormatException('Member Vault key authority mismatch');
    }
    _validateMemberVaultKeyCoordinates(context, memberVaultKey);
    final now = _now().toUtc();
    if (context.issuedAt.isAfter(now.add(const Duration(minutes: 5))) ||
        (context.offlinePolicy != 'disabled' &&
            !now.isBefore(context.notAfter))) {
      throw const FormatException('Invalid Member access lease');
    }
  }

  void _validateCachedAuthority({
    required String vaultId,
    required MemberSyncCacheState state,
    required MemberSyncSessionAuthority authority,
    required bool allowConnectedDisabledPolicy,
  }) {
    final context = state.accessContext;
    _validateContextCoordinates(
      vaultId: vaultId,
      context: context,
      authority: authority,
    );
    _validateMemberVaultKeyCoordinates(context, state.memberVaultKey);
    final now = _now().toUtc();
    if (now
            .add(const Duration(minutes: 5))
            .isBefore(state.maximumObservedWallTime) ||
        now.add(const Duration(minutes: 5)).isBefore(context.issuedAt) ||
        (context.offlinePolicy != 'disabled' &&
            !now.isBefore(context.notAfter)) ||
        (context.offlinePolicy == 'disabled' &&
            (!allowConnectedDisabledPolicy ||
                !_connectedSessionVaults.contains(vaultId)))) {
      throw const FormatException('Member offline authority expired');
    }
  }

  void _validateContextCoordinates({
    required String vaultId,
    required MemberOfflineAccessContext context,
    required MemberSyncSessionAuthority authority,
  }) {
    if (context.principalId != authority.principalId ||
        context.memberId != authority.principalId ||
        context.organizationId != authority.organizationId ||
        context.organizationMembershipGeneration !=
            authority.organizationMembershipGeneration ||
        context.offlinePolicy != authority.offlinePolicy ||
        context.offlinePolicyVersion != authority.offlinePolicyVersion ||
        context.vaultId != vaultId ||
        context.notAfter != context.issuedAt.add(context.leaseDuration)) {
      throw const FormatException('Member access context binding mismatch');
    }
  }

  void _validateMemberVaultKeyCoordinates(
    MemberOfflineAccessContext context,
    Map<String, dynamic> memberVaultKey,
  ) {
    final wrapped = memberVaultKey['wrappedVaultKey'];
    final descriptor = wrapped is Map ? wrapped['descriptor'] : null;
    final scope = descriptor is Map ? descriptor['scope'] : null;
    if (descriptor is! Map ||
        scope is! Map ||
        scope['organizationId'] != context.organizationId ||
        scope['vaultId'] != context.vaultId ||
        scope['memberId'] != context.memberId ||
        descriptor['memberKeyGeneration'] != context.memberKeyGeneration ||
        descriptor['wrappedKeyVersion'] != context.vaultKeyVersion ||
        descriptor['recipientKeyVersion'] !=
            context.memberRecipientKeyVersion ||
        descriptor['recipientFingerprint'] !=
            context.memberRecipientKeyFingerprint) {
      throw const FormatException('Member Vault key binding mismatch');
    }
  }

  void _validateAccessContextContinuation(
    MemberOfflineAccessContext? previous,
    MemberOfflineAccessContext current,
  ) {
    if (previous == null) return;
    Map<String, Object?> binding(MemberOfflineAccessContext value) => {
      'contextVersion': value.contextVersion,
      'principalId': value.principalId,
      'organizationId': value.organizationId,
      'organizationMembershipGeneration':
          value.organizationMembershipGeneration,
      'vaultId': value.vaultId,
      'memberId': value.memberId,
      'memberKeyGeneration': value.memberKeyGeneration,
      'vaultKeyVersion': value.vaultKeyVersion,
      'memberRecipientKeyVersion': value.memberRecipientKeyVersion,
      'memberRecipientKeyFingerprint': value.memberRecipientKeyFingerprint,
      'offlinePolicy': value.offlinePolicy,
      'offlinePolicyVersion': value.offlinePolicyVersion,
    };
    if (_canonicalJson(binding(previous)) != _canonicalJson(binding(current)) ||
        current.notAfter.isBefore(previous.notAfter)) {
      throw const FormatException('Member access context changed mid-stream');
    }
  }

  void _scheduleLeaseExpiry(
    String vaultId,
    MemberOfflineAccessContext context,
  ) {
    _leaseTimers.remove(vaultId)?.cancel();
    if (context.offlinePolicy == 'disabled') return;
    final delay = context.notAfter.difference(_now().toUtc());
    if (delay <= Duration.zero) {
      unawaited(_purgeExpiredVault(vaultId));
      return;
    }
    _leaseTimers[vaultId] = Timer(
      delay,
      () => unawaited(_purgeExpiredVault(vaultId)),
    );
  }

  Future<void> _purgeExpiredVault(String vaultId) async {
    try {
      await purgeVault(vaultId);
    } on Object {
      // purgeVault clears decrypted state before attempting durable deletion.
    }
  }

  String _canonicalJson(Object? value) => jsonEncode(_sortedJson(value));

  Object? _sortedJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _sortedJson(value[key]),
      };
    }
    if (value is List) return value.map(_sortedJson).toList(growable: false);
    return value;
  }

  void _validatePageCount(List<MemberSyncItemModel> items) {
    if (items.length > VaultPerformanceBudget.maximumMemberSyncPageItems) {
      throw const FormatException('Member sync page exceeds item limit');
    }
  }

  void _requireKeyContextCovers(
    Iterable<MemberSyncItemModel> items,
    int currentGeneration,
  ) {
    var requiredGeneration = currentGeneration;
    for (final item in items) {
      final descriptor = item.entryKey?['descriptor'];
      if (descriptor is! Map) continue;
      final generation = descriptor['memberKeyGeneration'];
      if (generation is int && generation > requiredGeneration) {
        requiredGeneration = generation;
      }
    }
    if (requiredGeneration > currentGeneration) {
      throw MemberVaultKeyContextStaleException(
        requiredGeneration: requiredGeneration,
      );
    }
  }

  void _requireCurrent(int generation) {
    if (generation != _lockGeneration) {
      throw const _MemberSyncInvalidated();
    }
  }

  void _requireSessionEpoch(int epoch) {
    if (epoch != _sessionEpoch) {
      throw const _MemberSyncInvalidated();
    }
  }

  void _requireReadable(String vaultId, int generation) {
    if (generation != _lockGeneration || _revokedVaults.contains(vaultId)) {
      throw const LocalMemberEntryReadInvalidatedException();
    }
  }

  void _publishIndexUpdate(String vaultId) {
    if (!_indexUpdates.isClosed) _indexUpdates.add(vaultId);
  }

  void _publishDurableUpdate(String vaultId) {
    if (!_durableUpdates.isClosed) _durableUpdates.add(vaultId);
  }

  Future<List<MemberIndexEntry>> _decryptPage(
    List<MemberSyncItemModel> items,
    String organizationId,
    String vaultId,
    Uint8List vaultKey,
    int minimumGeneration,
    int expectedVaultKeyVersion,
  ) async {
    final output = <MemberIndexEntry>[];
    for (var offset = 0; offset < items.length; offset += decryptConcurrency) {
      final end = (offset + decryptConcurrency).clamp(0, items.length);
      output.addAll(
        await Future.wait(
          items
              .sublist(offset, end)
              .map(
                (item) => _decrypt(
                  item,
                  organizationId,
                  vaultId,
                  vaultKey,
                  minimumGeneration,
                  expectedVaultKeyVersion,
                ),
              ),
        ),
      );
    }
    return output;
  }

  Future<MemberIndexEntry> _decrypt(
    MemberSyncItemModel item,
    String organizationId,
    String vaultId,
    Uint8List vaultKey,
    int minimumGeneration,
    int expectedVaultKeyVersion,
  ) async {
    final entryKey = item.entryKey!;
    final memberIndex = item.memberIndex!;
    Uint8List? entryDek;
    try {
      _validateHeadCoordinates(
        item,
        organizationId,
        vaultId,
        entryKey,
        memberIndex,
        minimumGeneration,
        expectedVaultKeyVersion,
      );
      _validateSecretCoordinates(
        item,
        organizationId,
        vaultId,
        item.memberSecret!,
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
    String organizationId,
    String vaultId,
    Map<String, dynamic> entryKey,
    Map<String, dynamic> memberIndex,
    int minimumGeneration,
    int expectedVaultKeyVersion,
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
    final keyBinding = key['binding'];
    final generation = key['memberKeyGeneration'];

    // EntryKey has its own wrapper revision and normally remains unchanged
    // when an Entry edit reuses the existing DEK. `currentRevision` is the
    // MemberSecret head revision, not an independent authority for that
    // wrapper revision, so those two revisions are deliberately not compared.
    // The wrapper remains authenticated by its descriptor, while scope, key
    // version, member generation and wrapping Vault-key version are bound
    // below to independent current authority.
    if (keyScope is! Map ||
        indexScope is! Map ||
        keyBinding is! Map ||
        keyScope['organizationId'] != organizationId ||
        indexScope['organizationId'] != organizationId ||
        keyScope['vaultId'] != vaultId ||
        indexScope['vaultId'] != vaultId ||
        keyScope['entryId'] != item.entryId ||
        indexScope['entryId'] != item.entryId ||
        index['resourceRevision'] != item.memberIndexRevision ||
        item.memberIndexRevision != item.currentRevision ||
        key['keyVersion'] != item.currentKeyVersion ||
        index['keyVersion'] != item.currentKeyVersion ||
        keyBinding['wrappingVaultKeyVersion'] != expectedVaultKeyVersion ||
        generation != index['memberKeyGeneration'] ||
        generation is! int ||
        generation != minimumGeneration) {
      throw const FormatException('Member sync head binding mismatch');
    }
  }

  void _validateSecretCoordinates(
    MemberSyncItemModel item,
    String organizationId,
    String vaultId,
    Map<String, dynamic> memberSecret,
    int minimumGeneration,
  ) {
    final descriptorValue = memberSecret['descriptor'];
    if (descriptorValue is! Map) {
      throw const FormatException('Missing MemberSecret descriptor');
    }
    final descriptor = Map<String, dynamic>.from(descriptorValue);
    final scope = descriptor['scope'];
    final generation = descriptor['memberKeyGeneration'];
    if (scope is! Map ||
        scope['organizationId'] != organizationId ||
        scope['vaultId'] != vaultId ||
        scope['entryId'] != item.entryId ||
        descriptor['resourceRevision'] != item.currentRevision ||
        descriptor['keyVersion'] != item.currentKeyVersion ||
        generation is! int ||
        generation != minimumGeneration) {
      throw const FormatException('MemberSecret head binding mismatch');
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
      currentKeyVersion: item.currentKeyVersion!,
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
      currentKeyVersion: item.currentKeyVersion!,
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

  MemberEntryState _state(Object? value) => switch (value) {
    'active' || 'Active' || 0 || 1 => MemberEntryState.active,
    'archived' || 'Archived' || 2 => MemberEntryState.archived,
    'deleted' || 'Deleted' || 3 => MemberEntryState.deleted,
    _ => throw const FormatException('Malformed Member Entry state'),
  };

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

final class _MemberSnapshotRestartRequired implements Exception {
  const _MemberSnapshotRestartRequired({required this.afterSnapshot});

  final bool afterSnapshot;
}

final class _MemberSyncInvalidated implements Exception {
  const _MemberSyncInvalidated();
}
