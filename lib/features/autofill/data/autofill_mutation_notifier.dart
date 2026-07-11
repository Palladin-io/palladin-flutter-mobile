import 'dart:async';

/// Process-local signal that persisted vault content changed.
///
/// It carries no entry data and no key material. The app-level listener reads
/// the currently unlocked auth state at handling time and starts a full cache
/// replacement only when a private key is already available there.
class AutoFillMutationNotifier {
  final StreamController<void> _controller = StreamController<void>.broadcast(
    sync: true,
  );

  Stream<void> get changes => _controller.stream;

  void notifyChanged() => _controller.add(null);
}
