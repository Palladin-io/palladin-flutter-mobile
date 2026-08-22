import 'dart:async';

/// Native cache action required after persisted vault content changes.
enum AutoFillMutationAction {
  /// Revoke the old cache immediately without rebuilding it yet.
  invalidate,

  /// Revoke and rebuild the cache from current server ciphertext.
  rebuild,
}

typedef AutoFillMutationHandler =
    Future<void> Function(AutoFillMutationAction action);

/// Process-local coordinator for persisted vault-content mutations.
///
/// It carries no entry data and no key material. The app-level handler clears
/// the native cache before a leased remote mutation can start and reads the
/// currently unlocked auth state only when an authoritative rebuild is due.
class AutoFillMutationNotifier {
  final StreamController<AutoFillMutationAction> _controller =
      StreamController<AutoFillMutationAction>.broadcast(sync: true);
  final Set<int> _activeMutations = {};
  AutoFillMutationHandler? _handler;
  var _nextMutationId = 0;
  var _batchAmbiguous = false;
  var _batchHasDefinitiveResult = false;

  Stream<AutoFillMutationAction> get changes => _controller.stream;

  /// Attaches the application's single cache side-effect handler.
  ///
  /// Tests and diagnostics may still observe [changes], but canonical
  /// mutations await this handler so their remote transition cannot start
  /// until native cache invalidation has completed successfully.
  void attachHandler(AutoFillMutationHandler handler) {
    if (_handler != null) {
      throw StateError('An AutoFill mutation handler is already attached');
    }
    _handler = handler;
  }

  void detachHandler() => _handler = null;

  /// Revokes the old cache before a multi-step mutation can continue.
  Future<void> notifyInvalidated() {
    if (_activeMutations.isEmpty) {
      _batchAmbiguous = false;
      _batchHasDefinitiveResult = false;
    }
    return _dispatch(AutoFillMutationAction.invalidate);
  }

  /// Rebuilds the cache after the persisted mutation is complete.
  Future<void> notifyChanged() {
    if (_activeMutations.isEmpty && !_batchAmbiguous) {
      return _dispatch(AutoFillMutationAction.rebuild);
    }
    return Future<void>.value();
  }

  /// Starts one potentially overlapping remote mutation.
  ///
  /// Every mutation invalidates immediately. The cache is rebuilt only after
  /// the entire active batch ends definitively. If any result is ambiguous,
  /// the batch leaves AutoFill empty; the next newly-started mutation creates
  /// a fresh batch that may rebuild from authoritative server state.
  Future<AutoFillMutationLease> beginMutation() async {
    if (_activeMutations.isEmpty) {
      _batchAmbiguous = false;
      _batchHasDefinitiveResult = false;
    }
    final id = ++_nextMutationId;
    _activeMutations.add(id);
    try {
      await _dispatch(AutoFillMutationAction.invalidate);
      return AutoFillMutationLease._(this, id);
    } catch (_) {
      _activeMutations.remove(id);
      if (_activeMutations.isEmpty &&
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
    if (_activeMutations.isEmpty && !_batchAmbiguous) await notifyChanged();
  }

  Future<void> _dispatch(AutoFillMutationAction action) async {
    _controller.add(action);
    final handler = _handler;
    if (handler != null) await handler(action);
  }
}

/// Opaque completion token for one cache-sensitive remote mutation.
final class AutoFillMutationLease {
  AutoFillMutationLease._(this._owner, this._id);

  final AutoFillMutationNotifier _owner;
  final int _id;
  var _finished = false;

  /// Marks a definitive HTTP result (success or concrete rejection).
  Future<void> complete() => _finish(ambiguous: false);

  /// Keeps the cache empty because the server outcome cannot be proven.
  Future<void> leaveAmbiguous() => _finish(ambiguous: true);

  Future<void> _finish({required bool ambiguous}) async {
    if (_finished) return;
    _finished = true;
    await _owner._finishMutation(_id, ambiguous: ambiguous);
  }
}
