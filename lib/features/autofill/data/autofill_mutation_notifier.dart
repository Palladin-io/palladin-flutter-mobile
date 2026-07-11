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

  Stream<AutoFillMutationAction> get changes => _controller.stream;

  /// Revokes the old cache before a multi-step mutation can continue.
  void notifyInvalidated() =>
      _controller.add(AutoFillMutationAction.invalidate);

  /// Rebuilds the cache after the persisted mutation is complete.
  void notifyChanged() => _controller.add(AutoFillMutationAction.rebuild);
}
