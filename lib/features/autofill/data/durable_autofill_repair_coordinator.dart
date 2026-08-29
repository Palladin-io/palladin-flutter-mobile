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

/// Coalesces committed Member sync updates into local-only native rebuilds.
///
/// This coordinator deliberately has no Member sync/preparation dependency:
/// a durable update may only wait for its already-running publication tail and
/// rebuild from installed indexes. It therefore cannot create HTTP or
/// per-Entry requests while repairing the native derivative.
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
  Object? _readySessionIdentity;
  int? _readyEpoch;
  int _epoch = 0;
  int _sequence = 0;
  bool _repairsSuspended = false;
  bool _disposed = false;

  /// Starts consuming the authoritative post-commit stream once.
  void start() {
    if (_subscription != null || _disposed) return;
    _subscription = _memberIndexes.durableUpdates.listen(_onDurableUpdate);
  }

  /// Replaces the complete Vault set returned by an all-Vault preparation.
  void replaceKnownVaults(Iterable<String> vaultIds) {
    final session = _currentSession();
    if (session == null || session.privateKey.isEmpty) return;
    _knownVaultIds
      ..clear()
      ..addAll(vaultIds);
    _readySessionIdentity = session.identity;
    _readyEpoch = _epoch;
    if (_pending.isNotEmpty) unawaited(drainPending());
  }

  /// Holds committed-index repairs after a native deny until the mutation or
  /// invalidation batch has installed its authoritative replacement.
  void suspendRepairs() {
    _repairsSuspended = true;
    _retry?.cancel();
    _retry = null;
  }

  /// Releases a previously held deny and drains every coalesced commit.
  void resumeRepairs() {
    if (!_repairsSuspended) return;
    _repairsSuspended = false;
    if (_pending.isNotEmpty) unawaited(drainPending());
  }

  /// Drops all profile-scoped state on lock, logout, or session replacement.
  void clearSession() {
    _epoch += 1;
    _knownVaultIds.clear();
    _pending.clear();
    _readySessionIdentity = null;
    _readyEpoch = null;
    _repairsSuspended = false;
    _retry?.cancel();
    _retry = null;
  }

  /// Exposed as a deterministic test seam; production drains automatically.
  Future<void> drainPending() {
    final session = _currentSession();
    if (_repairsSuspended ||
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
          !_repairsSuspended &&
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
        !_repairsSuspended &&
        identical(_readySessionIdentity, _currentSession()?.identity)) {
      unawaited(drainPending());
    }
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty && !_disposed && !_repairsSuspended) {
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
      try {
        var covered = Map<String, int>.from(_pending);
        while (true) {
          await Future.wait(covered.keys.map(_memberIndexes.waitForCurrent));
          if (_epoch != initialEpoch || _repairsSuspended) return;
          final latest = Map<String, int>.from(_pending);
          if (_sameUpdates(covered, latest)) break;
          covered = latest;
        }
        final currentSession = _currentSession();
        if (currentSession == null ||
            _repairsSuspended ||
            _epoch != initialEpoch ||
            _readyEpoch != initialEpoch ||
            currentSession.principalId != initialSession.principalId ||
            !identical(currentSession.identity, initialSession.identity) ||
            currentSession.privateKey.isEmpty) {
          if (_epoch == initialEpoch) _pending.clear();
          return;
        }
        await _autoFill.synchronizePrepared(
          privateKey: currentSession.privateKey,
          vaultIds: Set<String>.from(_knownVaultIds),
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
        _retry ??= Timer(retryDelay, () {
          _retry = null;
          if (!_disposed) unawaited(drainPending());
        });
        return;
      }
    }
  }

  bool _sameUpdates(Map<String, int> left, Map<String, int> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }
}
