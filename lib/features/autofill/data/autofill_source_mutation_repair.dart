import 'autofill_source_access_service.dart';

/// Keeps remote-mutation denial across ordinary Vault locks. Only a definitive
/// outcome followed by successful authoritative reconciliation releases it.
final class AutoFillSourceMutationRepair {
  AutoFillSourceMutationRepair(this._source);

  final AutoFillSourceAccessService _source;
  final Set<Future<AutoFillSourceMutation>> _pending = {};
  final Set<Future<AutoFillSourceMutation>> _committed = {};
  void Function()? _validateSession;

  void _synchronizeSession() {
    try {
      _validateSession?.call();
    } on StateError {
      clearSession();
    }
    _validateSession ??= _source.captureSessionGuard();
  }

  Future<void> invalidate() {
    return _admitInvalidation().then<void>((_) {});
  }

  Future<AutoFillSourceMutation> _admitInvalidation() {
    _synchronizeSession();
    final owner = _source.invalidate(revokeAuthorization: true);
    _pending.add(owner);
    return owner;
  }

  Future<void> invalidateCommitted() async {
    final validate = _source.captureSessionGuard();
    final owner = _admitInvalidation();
    await owner;
    validate();
    _committed.add(owner);
  }

  bool get needsReconciliation {
    _synchronizeSession();
    return _committed.isNotEmpty;
  }

  Future<void> markCommitted() {
    _synchronizeSession();
    if (_pending.isEmpty) return invalidateCommitted();
    _committed.addAll(_pending);
    return Future.value();
  }

  Future<T> prepare<T>(
    Future<T> Function() authoritativeRefresh, {
    void Function()? validateCurrent,
  }) async {
    _synchronizeSession();
    final validateSession = _source.captureSessionGuard();
    final covered = List<Future<AutoFillSourceMutation>>.of(_committed);
    final owners = await Future.wait(covered);
    validateSession();
    final result = await authoritativeRefresh();
    validateSession();
    validateCurrent?.call();
    final remaining = [
      for (var i = 0; i < covered.length; i++)
        if (_pending.contains(covered[i])) owners[i],
    ];
    for (final owner in remaining) {
      if (!_source.ownsMutation(owner)) {
        throw StateError('Source mutation no longer belongs to this session');
      }
    }
    for (final owner in remaining) {
      _source.complete(owner);
    }
    _pending.removeAll(covered);
    _committed.removeAll(covered);
    return result;
  }

  /// Account replacement only; an ordinary lock must preserve pending work.
  void clearSession() {
    _validateSession = null;
    _pending.clear();
    _committed.clear();
  }
}
