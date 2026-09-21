import 'dart:async';

import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../vault/data/services/member_sync_service.dart';
import '../../vault/presentation/cubit/vault_list_cubit.dart';
import 'cubit/notification_center_cubit.dart';

/// Repairs Inbox-only events that deliberately have no push/SignalR fan-out.
final class NotificationForegroundRepair {
  NotificationForegroundRepair({
    required this.auth,
    required this.vaults,
    required this.inbox,
    required this.readAuthority,
  });

  final AuthBloc auth;
  final VaultListCubit vaults;
  final NotificationCenterCubit inbox;
  final Future<MemberSyncSessionAuthority> Function() readAuthority;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<VaultListState>? _vaultSubscription;
  Timer? _timer;
  bool _started = false;
  bool _foreground = false;
  int _generation = 0;
  int? _runningGeneration;
  String? _account;

  void start({required bool foreground}) {
    if (_started) return;
    _started = true;
    _foreground = foreground;
    _authSubscription = auth.stream.listen((_) => _contextChanged());
    _vaultSubscription = vaults.stream.listen((_) => _contextChanged());
    _contextChanged();
  }

  void setForeground(bool foreground) {
    if (!_started || _foreground == foreground) return;
    _foreground = foreground;
    _contextChanged();
  }

  void _contextChanged() {
    if (!_started) return;
    _generation++;
    _timer?.cancel();
    _timer = null;
    final state = auth.state;
    final account = state is AuthAuthenticated ? state.userId : null;
    if (_account != null && account != _account) {
      inbox.reset();
    } else {
      inbox.lock();
    }
    _account = account;
    if (!_ready) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _repair());
    unawaited(_repair());
  }

  bool get _ready {
    final state = auth.state;
    return _started &&
        _foreground &&
        state is AuthAuthenticated &&
        !state.isVaultLocked &&
        state.privateKey != null &&
        state.emailVerified &&
        state.isOnboarded &&
        vaults.state is VaultListLoaded;
  }

  Future<void> _repair() async {
    final generation = _generation;
    if (!_ready || _runningGeneration == generation) return;
    _runningGeneration = generation;
    final authenticated = auth.state as AuthAuthenticated;
    final loaded = vaults.state as VaultListLoaded;
    try {
      final authority = await readAuthority();
      if (!_ready ||
          generation != _generation ||
          !identical(auth.state, authenticated) ||
          !identical(vaults.state, loaded) ||
          authority.principalId != authenticated.userId) {
        return;
      }
      inbox.configureUnlockedResolution(
        activeAccountId: authority.principalId,
        activeOrganizationId: authority.organizationId,
        activeVaults: loaded.vaults,
      );
      await inbox.refresh();
    } catch (_) {
      // Optional repair stays quiet and never records transport/session data.
    } finally {
      if (_runningGeneration == generation) _runningGeneration = null;
    }
  }

  Future<void> dispose() async {
    if (!_started) return;
    _started = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    inbox.lock();
    await _authSubscription?.cancel();
    await _vaultSubscription?.cancel();
  }
}
