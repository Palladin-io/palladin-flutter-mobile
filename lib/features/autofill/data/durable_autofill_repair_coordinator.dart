import 'dart:async';
import 'dart:typed_data';

import '../../vault/data/services/member_sync_service.dart';
import '../domain/autofill_cache_invalidator.dart';

/// One short-lived view of the currently unlocked BLoC session.
///
/// The coordinator never stores this object or copies its key across drains.
final class AutoFillRepairSession {
  const AutoFillRepairSession({
    required this.principalId,
    required this.identity,
    required this.privateKey,
  });

  final String principalId;
  final Object identity;
  final Uint8List privateKey;
}

typedef CurrentAutoFillRepairSession = AutoFillRepairSession? Function();

/// Opaque ownership token for one active native-cache deny.
final class AutoFillRepairDeny {
  AutoFillRepairDeny._();
}

/// Coalesces committed Member sync updates into local source authorization.
///
/// This coordinator deliberately has no Member sync/preparation dependency:
/// a durable update may only wait for its already-running publication tail and
/// authorize installed indexes. It therefore cannot create HTTP or
/// per-Entry requests while checking provider access.
final class DurableAutoFillRepairCoordinator {
  DurableAutoFillRepairCoordinator({
    required DurableMemberIndexUpdates memberIndexes,
    required AutoFillPreparedCacheSynchronizer autoFill,
    required CurrentAutoFillRepairSession currentSession,
    this.retryDelay = const Duration(milliseconds: 250),
    this.onFailure,
  }) : _memberIndexes = memberIndexes,
       _autoFill = autoFill,
       _currentSession = currentSession;

  final DurableMemberIndexUpdates _memberIndexes;
  final AutoFillPreparedCacheSynchronizer _autoFill;
  final CurrentAutoFillRepairSession _currentSession;
  final Duration retryDelay;
  final void Function(Object error)? onFailure;

  final Set<String> _knownVaultIds = {};
  final Map<String, int> _pending = {};
  StreamSubscription<String>? _subscription;
  Future<void>? _running;
  Timer? _retry;
  Timer? _foregroundRetry;
  Object? _readySessionIdentity;
  int? _readyEpoch;
  int _epoch = 0;
  int _sequence = 0;
  int _publicationAdmission = 0;
  int? _retriedSequence;
  final Set<AutoFillRepairDeny> _repairDenies = {};
  bool _disposed = false;
  _AutoFillPublication? _publication;

  /// Starts consuming the authoritative post-commit stream once.
  void start() {
    if (_subscription != null || _disposed) return;
    _subscription = _memberIndexes.durableUpdates.listen(_onDurableUpdate);
  }

  /// Replaces the complete Vault set returned by an all-Vault preparation.
  void replaceKnownVaults(Iterable<String> vaultIds) {
    _installKnownVaults(vaultIds);
    if (_pending.isNotEmpty) unawaited(drainPending());
  }

  void _installKnownVaults(Iterable<String> vaultIds) {
    final session = _currentSession();
    if (session == null || session.privateKey.isEmpty) return;
    _knownVaultIds
      ..clear()
      ..addAll(vaultIds);
    _readySessionIdentity = session.identity;
    _readyEpoch = _epoch;
  }

  /// Holds committed-index repairs after a native deny until the mutation or
  /// invalidation batch has installed its authoritative replacement.
  AutoFillRepairDeny suspendRepairs() {
    ++_publicationAdmission;
    _foregroundRetry?.cancel();
    _foregroundRetry = null;
    final deny = AutoFillRepairDeny._();
    _repairDenies.add(deny);
    _retry?.cancel();
    _retry = null;
    return deny;
  }

  /// Releases one owned deny without weakening any overlapping owner.
  void resumeRepairs(AutoFillRepairDeny deny) {
    if (!_repairDenies.remove(deny) || _repairDenies.isNotEmpty) return;
    if (_pending.isNotEmpty) unawaited(drainPending());
  }

  /// Publishes a foreground/reconnect rebuild only while no mutation or
  /// invalidation batch owns the durable native deny.
  ///
  /// The guard and synchronizer invocation are synchronous until the returned
  /// future is obtained, so a deny cannot interleave between them.
  Future<bool> synchronizePreparedIfAllowed({
    required Uint8List privateKey,
    required Iterable<String> vaultIds,
    Set<AutoFillRepairDeny> releasingDenies = const {},
  }) async {
    if (_disposed || !_repairDenies.containsAll(releasingDenies)) return false;
    final blockingDenies = _repairDenies.difference(releasingDenies);
    if (blockingDenies.isNotEmpty) {
      // Release this completed owner's denies synchronously. The next owner
      // reaching the gate can then publish, avoiding a two-owner deadlock.
      for (final deny in releasingDenies) {
        resumeRepairs(deny);
      }
      return false;
    }
    final session = _currentSession();
    if (session == null || !identical(session.privateKey, privateKey)) {
      for (final deny in releasingDenies) {
        resumeRepairs(deny);
      }
      return false;
    }
    _retriedSequence = null;
    _retry?.cancel();
    _retry = null;
    final epoch = _epoch;
    final completeVaultIds = Set<String>.unmodifiable(vaultIds);
    _installKnownVaults(completeVaultIds);
    final covered = Map<String, int>.from(_pending);
    try {
      await _publishPrepared(session, completeVaultIds);
    } catch (_) {
      // A foreground-only repair has no durable commit to drive _drain.
      // Caller-owned denies retain their separate authoritative retry path.
      if (!_disposed &&
          _epoch == epoch &&
          releasingDenies.isEmpty &&
          _repairDenies.isEmpty) {
        _scheduleForegroundRetry(session.principalId, session.identity, epoch);
      }
      rethrow;
    }
    _foregroundRetry?.cancel();
    _foregroundRetry = null;
    for (final update in covered.entries) {
      if (_pending[update.key] == update.value) {
        _pending.remove(update.key);
      }
    }
    for (final deny in releasingDenies) {
      resumeRepairs(deny);
    }
    return true;
  }

  void _scheduleForegroundRetry(
    String principalId,
    Object identity,
    int epoch,
  ) {
    _foregroundRetry ??= Timer(retryDelay, () {
      _foregroundRetry = null;
      final current = _currentSession();
      if (_disposed ||
          _epoch != epoch ||
          _readyEpoch != epoch ||
          _repairDenies.isNotEmpty ||
          _pending.isNotEmpty ||
          current == null ||
          current.privateKey.isEmpty ||
          current.principalId != principalId ||
          !identical(current.identity, identity) ||
          !identical(_readySessionIdentity, identity)) {
        return;
      }
      // Resolve the current session only when retrying; the timer retains no key.
      // One automatic attempt, then wait for an actual lifecycle/commit event.
      unawaited(
        _publishPrepared(
          current,
          Set<String>.unmodifiable(_knownVaultIds),
        ).catchError((Object error) {
          onFailure?.call(error);
        }),
      );
    });
  }

  /// Drops all profile-scoped state on lock, logout, or session replacement.
  void clearSession() {
    _foregroundRetry?.cancel();
    _foregroundRetry = null;
    _epoch += 1;
    _retriedSequence = null;
    ++_publicationAdmission;
    _knownVaultIds.clear();
    _pending.clear();
    _readySessionIdentity = null;
    _readyEpoch = null;
    _repairDenies.clear();
    _retry?.cancel();
    _retry = null;
  }

  /// Exposed as a deterministic test seam; production drains automatically.
  Future<void> drainPending() {
    final session = _currentSession();
    if (_repairDenies.isNotEmpty ||
        session == null ||
        _readyEpoch != _epoch ||
        !identical(_readySessionIdentity, session.identity)) {
      return Future<void>.value();
    }
    final active = _running;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _drain().whenComplete(() {
      if (identical(_running, operation)) _running = null;
      if (_pending.isNotEmpty &&
          _retry == null &&
          _retriedSequence != _sequence &&
          _repairDenies.isEmpty &&
          !_disposed &&
          _readyEpoch == _epoch &&
          identical(_readySessionIdentity, _currentSession()?.identity)) {
        unawaited(drainPending());
      }
    });
    _running = operation;
    return operation;
  }

  Future<void> dispose() async {
    _disposed = true;
    _foregroundRetry?.cancel();
    _foregroundRetry = null;
    _retry?.cancel();
    _retry = null;
    await _subscription?.cancel();
    _subscription = null;
  }

  void _onDurableUpdate(String vaultId) {
    if (_disposed) return;
    if (vaultId == '*') {
      clearSession();
      return;
    }
    _knownVaultIds.add(vaultId);
    _pending[vaultId] = ++_sequence;
    if (_readyEpoch == _epoch &&
        _repairDenies.isEmpty &&
        identical(_readySessionIdentity, _currentSession()?.identity)) {
      unawaited(drainPending());
    }
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty && !_disposed && _repairDenies.isEmpty) {
      final initialEpoch = _epoch;
      final initialSession = _currentSession();
      if (initialSession == null || initialSession.privateKey.isEmpty) {
        if (_epoch == initialEpoch) _pending.clear();
        return;
      }
      if (_readyEpoch != initialEpoch ||
          !identical(_readySessionIdentity, initialSession.identity)) {
        return;
      }
      var attemptedSequence = _sequence;
      try {
        var covered = Map<String, int>.from(_pending);
        while (true) {
          // A publication covers the complete known Vault set, including a
          // Vault whose running sync has not emitted its first commit yet.
          final waitingVaults = Set<String>.from(_knownVaultIds);
          await Future.wait(waitingVaults.map(_memberIndexes.waitForCurrent));
          if (_epoch != initialEpoch || _repairDenies.isNotEmpty) return;
          final latest = Map<String, int>.from(_pending);
          if (_sameUpdates(covered, latest) &&
              waitingVaults.length == _knownVaultIds.length &&
              waitingVaults.containsAll(_knownVaultIds)) {
            break;
          }
          covered = latest;
        }
        // Foreground repair may have consumed this commit while we awaited
        // its publication tail. It must not trigger a second native rebuild.
        if (covered.isEmpty) return;
        final currentSession = _currentSession();
        if (currentSession == null ||
            _repairDenies.isNotEmpty ||
            _epoch != initialEpoch ||
            _readyEpoch != initialEpoch ||
            currentSession.principalId != initialSession.principalId ||
            !identical(currentSession.identity, initialSession.identity) ||
            currentSession.privateKey.isEmpty) {
          if (_epoch == initialEpoch) _pending.clear();
          return;
        }
        attemptedSequence = _sequence;
        await _publishPrepared(
          currentSession,
          Set<String>.from(_knownVaultIds),
        );
        if (_epoch == initialEpoch) {
          for (final update in covered.entries) {
            if (_pending[update.key] == update.value) {
              _pending.remove(update.key);
            }
          }
        }
      } catch (error) {
        if (_epoch != initialEpoch) return;
        onFailure?.call(error);
        // Keep the committed work pending, but do not rebuild forever for a
        // permanent native failure. New commits/lifecycle attempts can retry.
        if (_retriedSequence == attemptedSequence) return;
        _retriedSequence = attemptedSequence;
        final principalId = initialSession.principalId;
        final identity = initialSession.identity;
        _retry ??= Timer(retryDelay, () {
          _retry = null;
          final current = _currentSession();
          if (!_disposed &&
              _epoch == initialEpoch &&
              current?.principalId == principalId &&
              identical(current?.identity, identity)) {
            unawaited(drainPending());
          }
        });
        return;
      }
    }
  }

  Future<void> _publishPrepared(
    AutoFillRepairSession session,
    Set<String> vaultIds,
  ) {
    final previous = _publication;
    if (previous != null &&
        previous.admission == _publicationAdmission &&
        previous.sequence == _sequence &&
        identical(previous.sessionIdentity, session.identity) &&
        previous.vaultIds.length == vaultIds.length &&
        previous.vaultIds.containsAll(vaultIds)) {
      return previous.completion;
    }
    if (previous != null) {
      return _publishAfter(
        previous,
        session,
        vaultIds,
        _epoch,
        _publicationAdmission,
      );
    }
    // Share only concurrent consumers of this commit. Native quarantine can
    // invalidate a completed cache without a Dart event, so later foreground
    // recovery must rebuild even when the local ciphertext has not changed.
    // The record contains no key; its Future is detached on every completion.
    final publication = _AutoFillPublication(
      sequence: _sequence,
      admission: _publicationAdmission,
      sessionIdentity: session.identity,
      vaultIds: Set<String>.unmodifiable(vaultIds),
    );
    _publication = publication;
    publication.completion =
        Future<void>.sync(
          () => _autoFill.synchronizePrepared(
            privateKey: session.privateKey,
            vaultIds: vaultIds,
          ),
        ).whenComplete(() {
          if (identical(_publication, publication)) _publication = null;
        });
    return publication.completion;
  }

  Future<void> _publishAfter(
    _AutoFillPublication previous,
    AutoFillRepairSession admitted,
    Set<String> vaultIds,
    int epoch,
    int admission,
  ) async {
    try {
      await previous.completion;
    } catch (_) {
      // The original caller owns its failure; a later admitted request still
      // needs its own publication from current authoritative state.
    }
    final current = _currentSession();
    if (_disposed ||
        _epoch != epoch ||
        _publicationAdmission != admission ||
        current == null ||
        current.principalId != admitted.principalId ||
        !identical(current.identity, admitted.identity) ||
        !identical(current.privateKey, admitted.privateKey) ||
        current.privateKey.isEmpty ||
        _readyEpoch != epoch ||
        !identical(_readySessionIdentity, current.identity) ||
        vaultIds.length != _knownVaultIds.length ||
        !vaultIds.containsAll(_knownVaultIds)) {
      throw StateError('Queued AutoFill publication invalidated');
    }
    await _publishPrepared(current, Set<String>.from(_knownVaultIds));
  }

  bool _sameUpdates(Map<String, int> left, Map<String, int> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }
}

final class _AutoFillPublication {
  _AutoFillPublication({
    required this.sequence,
    required this.admission,
    required this.sessionIdentity,
    required this.vaultIds,
  });

  final int sequence;
  final int admission;
  final Object sessionIdentity;
  final Set<String> vaultIds;
  late final Future<void> completion;
}
