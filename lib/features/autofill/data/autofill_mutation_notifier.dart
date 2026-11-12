import 'dart:async';

import '../domain/autofill_entry_coordinate.dart';

/// Source-access action required after persisted Vault content changes.
enum AutoFillMutationAction {
  /// Deny source access before the remote mutation.
  invalidate,

  /// Reconcile current server ciphertext before authorizing source access.
  rebuild,
}

typedef AutoFillMutationHandler =
    Future<void> Function(AutoFillMutationAction action);

/// Process-local coordinator for persisted vault-content mutations.
///
/// It carries no entry data and no key material. The app-level handler clears
/// native source access before a leased remote mutation can start and reads the
/// currently unlocked auth state only when an authoritative rebuild is due.
class AutoFillMutationNotifier {
  final StreamController<AutoFillMutationAction> _controller =
      StreamController<AutoFillMutationAction>.broadcast(sync: true);
  final Set<int> _activeMutations = {};
  AutoFillMutationHandler? _handler;
  Set<AutoFillEntryCoordinate>? _batchScope;
  Set<AutoFillEntryCoordinate>? get currentMutationScope =>
      _batchScope == null ? null : Set.unmodifiable(_batchScope!);
  var _nextMutationId = 0;
  var _batchAmbiguous = false;
  var _batchHasDefinitiveResult = false;

  Stream<AutoFillMutationAction> get changes => _controller.stream;

  /// Attaches the application's single source-access handler.
  ///
  /// Tests and diagnostics may still observe [changes], but canonical
  /// mutations await this handler so their remote transition cannot start
  /// until native source denial has completed successfully.
  void attachHandler(AutoFillMutationHandler handler) {
    if (_handler != null) {
      throw StateError('An AutoFill mutation handler is already attached');
    }
    _handler = handler;
  }

  void detachHandler() => _handler = null;

  /// True account/session replacement only. Keep IDs monotonic so an old
  /// remote completion cannot finish a new account's active mutation.
  void resetSession() {
    _activeMutations.clear();
    _batchScope = null;
    _batchAmbiguous = false;
    _batchHasDefinitiveResult = false;
  }

  /// Denies source access before a multi-step mutation can continue.
  Future<void> notifyInvalidated() {
    _batchScope = null;
    if (_activeMutations.isEmpty) {
      _batchAmbiguous = false;
      _batchHasDefinitiveResult = false;
    }
    return _dispatch(AutoFillMutationAction.invalidate);
  }

  /// Requests reconciliation after the persisted mutation is complete.
  Future<void> notifyChanged() {
    if (_activeMutations.isNotEmpty) return Future<void>.value();
    _batchScope = null;
    // A standalone definitive mutation starts a fresh batch. A previous
    // ambiguous batch must not suppress a later authoritative rebuild.
    _batchAmbiguous = false;
    _batchHasDefinitiveResult = false;
    return _dispatch(AutoFillMutationAction.rebuild);
  }

  /// Starts one potentially overlapping remote mutation.
  ///
  /// Every mutation invalidates immediately. Access is restored only after
  /// the entire active batch ends definitively. If any result is ambiguous,
  /// the batch leaves AutoFill denied; the next newly-started mutation creates
  /// a fresh batch that may reconcile authoritative server state.
  Future<AutoFillMutationLease> beginMutation({
    Set<AutoFillEntryCoordinate>? scope,
  }) async {
    if (_activeMutations.isEmpty) {
      _batchScope = scope == null ? null : Set.of(scope);
      _batchAmbiguous = false;
      _batchHasDefinitiveResult = false;
    }
    if (scope == null) {
      _batchScope = null;
    } else {
      _batchScope?.addAll(scope);
    }
    final id = ++_nextMutationId;
    _activeMutations.add(id);
    try {
      await _dispatch(AutoFillMutationAction.invalidate);
      if (!_activeMutations.contains(id)) {
        throw StateError('Mutation session changed');
      }
      return AutoFillMutationLease._(this, id);
    } catch (_) {
      final removed = _activeMutations.remove(id);
      if (removed &&
          _activeMutations.isEmpty &&
          !_batchAmbiguous &&
          _batchHasDefinitiveResult) {
        await notifyChanged();
      }
      rethrow;
    }
  }

  Future<void> _finishMutation(int id, {required bool ambiguous}) async {
    if (!_activeMutations.remove(id)) return;
    _batchAmbiguous = _batchAmbiguous || ambiguous;
    _batchHasDefinitiveResult = _batchHasDefinitiveResult || !ambiguous;
    if (_activeMutations.isEmpty && !_batchAmbiguous) {
      await _dispatch(AutoFillMutationAction.rebuild);
    }
  }

  Future<void> _dispatch(AutoFillMutationAction action) async {
    _controller.add(action);
    final handler = _handler;
    if (handler != null) await handler(action);
  }
}

/// Opaque completion token for one source-sensitive remote mutation.
final class AutoFillMutationLease {
  AutoFillMutationLease._(this._owner, this._id);

  final AutoFillMutationNotifier _owner;
  final int _id;
  var _finished = false;

  /// Marks a definitive HTTP result (success or concrete rejection).
  Future<void> complete() => _finish(ambiguous: false);

  /// Keeps source access denied because the server outcome cannot be proven.
  Future<void> leaveAmbiguous() => _finish(ambiguous: true);

  Future<void> _finish({required bool ambiguous}) async {
    if (_finished) return;
    _finished = true;
    await _owner._finishMutation(_id, ambiguous: ambiguous);
  }
}
