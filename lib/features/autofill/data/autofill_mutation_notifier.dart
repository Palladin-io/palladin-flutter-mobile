import 'dart:async';

/// Native cache action required after persisted vault content changes.
enum AutoFillMutationAction {
  /// Revoke the old cache immediately without rebuilding it yet.
  invalidate,

  /// Revoke and rebuild the cache from current server ciphertext.
  rebuild,
}

/// Process-local signal that persisted vault content changed.
///
/// It carries no entry data and no key material. The app-level listener reads
/// the currently unlocked auth state at handling time and starts a full cache
/// replacement only when a private key is already available there.
class AutoFillMutationNotifier {
  final StreamController<AutoFillMutationAction> _controller =
      StreamController<AutoFillMutationAction>.broadcast(sync: true);
  final Set<int> _activeMutations = {};
  var _nextMutationId = 0;
  var _batchAmbiguous = false;

  Stream<AutoFillMutationAction> get changes => _controller.stream;

  /// Revokes the old cache before a multi-step mutation can continue.
  void notifyInvalidated() {
    if (_activeMutations.isEmpty) _batchAmbiguous = false;
    _controller.add(AutoFillMutationAction.invalidate);
  }

  /// Rebuilds the cache after the persisted mutation is complete.
  void notifyChanged() {
    if (_activeMutations.isEmpty && !_batchAmbiguous) {
      _controller.add(AutoFillMutationAction.rebuild);
    }
  }

  /// Starts one potentially overlapping remote mutation.
  ///
  /// Every mutation invalidates immediately. The cache is rebuilt only after
  /// the entire active batch ends definitively. If any result is ambiguous,
  /// the batch leaves AutoFill empty; the next newly-started mutation creates
  /// a fresh batch that may rebuild from authoritative server state.
  AutoFillMutationLease beginMutation() {
    if (_activeMutations.isEmpty) _batchAmbiguous = false;
    final id = ++_nextMutationId;
    _activeMutations.add(id);
    _controller.add(AutoFillMutationAction.invalidate);
    return AutoFillMutationLease._(this, id);
  }

  void _finishMutation(int id, {required bool ambiguous}) {
    if (!_activeMutations.remove(id)) return;
    _batchAmbiguous = _batchAmbiguous || ambiguous;
    if (_activeMutations.isEmpty && !_batchAmbiguous) notifyChanged();
  }
}

/// Opaque completion token for one cache-sensitive remote mutation.
final class AutoFillMutationLease {
  AutoFillMutationLease._(this._owner, this._id);

  final AutoFillMutationNotifier _owner;
  final int _id;
  var _finished = false;

  /// Marks a definitive HTTP result (success or concrete rejection).
  void complete() => _finish(ambiguous: false);

  /// Keeps the cache empty because the server outcome cannot be proven.
  void leaveAmbiguous() => _finish(ambiguous: true);

  void _finish({required bool ambiguous}) {
    if (_finished) return;
    _finished = true;
    _owner._finishMutation(_id, ambiguous: ambiguous);
  }
}
