import 'dart:async';

import '../../auth/presentation/bloc/auth_state.dart';
import 'autofill_source_access_service.dart';

/// Subscribes before request consumers so final auth loss fences source access
/// synchronously. Loading and ordinary Vault locks are not account replacement.
final class AutoFillAuthLifecycle {
  AutoFillAuthLifecycle({
    required AuthState initialState,
    required Stream<AuthState> states,
    required AutoFillSourceAccessService source,
    void Function()? onTransition,
    void Function(Object)? onFailure,
  }) : _source = source,
       _onTransition = onTransition,
       _onFailure = onFailure {
    _subscription = states.listen(_accept);
    _accept(initialState);
  }

  final AutoFillSourceAccessService _source;
  final void Function()? _onTransition;
  final void Function(Object)? _onFailure;
  late final StreamSubscription<AuthState> _subscription;
  String? _principal;
  bool _terminal = false;

  void _accept(AuthState state) {
    if (state is AuthAuthenticated) {
      final replaced = _principal != null && _principal != state.userId;
      _principal = state.userId;
      _terminal = false;
      if (replaced) _transition();
    } else if (state is AuthUnauthenticated || state is AuthError) {
      _principal = null;
      if (_terminal) return;
      _terminal = true;
      _transition();
    }
  }

  void _transition() {
    // Admission is synchronous even though native denial is asynchronous.
    final pending = _source.transitionSession();
    unawaited(pending.catchError((Object error) => _onFailure?.call(error)));
    _onTransition?.call();
  }

  void runForegroundRepair(void Function() repair) {
    // The OS biometric prompt resumes the app before enrollment has committed.
    // Only redundant lifecycle repair is skipped; explicit revocation is not.
    if (!_source.isBiometricMutationActive) repair();
  }

  Future<void> dispose() => _subscription.cancel();
}
