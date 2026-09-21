import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../auth/presentation/bloc/auth_bloc.dart';
import '../data/services/entry_sharing/entry_share_ingress.dart';
import 'cubit/entry_share_reception_cubit.dart';
import 'entry_share_auth_binding.dart';

enum EntryShareAccountAction { login, register, continueAccount }

final class EntryShareAccountContinuation extends ChangeNotifier
    with WidgetsBindingObserver {
  EntryShareAccountContinuation({
    required AuthBloc auth,
    required EntryShareIngress ingress,
    required Future<EntryShareRecipientOwner?> Function(String?) ownerReader,
  }) : _auth = auth,
       _ingress = ingress,
       _ownerReader = ownerReader {
    _subscription = auth.stream.listen(_authChanged);
    ingress.addListener(_linkChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  final AuthBloc _auth;
  final EntryShareIngress _ingress;
  final Future<EntryShareRecipientOwner?> Function(String?) _ownerReader;
  late final StreamSubscription<AuthState> _subscription;
  EntryShareReceptionTransfer? _transfer;
  EntryShareRecipientOwner? _verifiedOwner;
  AuthAuthenticated? _observed;
  AuthAuthenticated? _authorityState;
  String? _principal, _organization;
  Timer? _expiry, _repair;
  int _epoch = 0, _version = 0, _authorityRevision = 0;
  bool _starting = false, _ready = false, _claiming = false, _disposed = false;
  bool _departed = false;
  String _route = '/share', _entryRoute = '/login';

  static const _accountRoutes = {
    '/login',
    '/register',
    '/verify-email',
    '/onboarding',
    '/unlock',
  };

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get active => !_disposed && _transfer?.isAvailable == true;
  bool get ready => active && _ready && _foreground;
  bool ownsVersion(int version) => active && version == _version;

  Future<bool> begin(
    EntryShareReceptionCubit cubit,
    EntryShareAccountAction action,
  ) async {
    if (_disposed || _starting || active || !_foreground) return false;
    final binding = entryShareAuthBinding(_auth.state);
    if (binding == null) return false;
    _starting = true;
    final epoch = ++_epoch;
    final version = _ingress.version;
    final transfer = await cubit.detachForAccount();
    if (epoch == _epoch) _starting = false;
    if (_disposed ||
        epoch != _epoch ||
        version != _ingress.version ||
        binding != entryShareAuthBinding(_auth.state) ||
        !_foreground) {
      transfer?.dispose();
      return false;
    }
    _starting = false;
    if (transfer == null) return false;
    _transfer = transfer;
    _version = version;
    _principal = transfer.initialOwner.principalId;
    _organization = transfer.initialOwner.organizationId;
    _verifiedOwner = _principal == null ? null : transfer.initialOwner;
    final authState = _auth.state;
    _observed = authState is AuthAuthenticated ? authState : null;
    _authorityState = _verifiedOwner == null ? null : _observed;
    _route = '/share';
    _departed = false;
    _entryRoute = action == EntryShareAccountAction.register
        ? '/register'
        : '/login';
    _expiry = Timer(transfer.remaining, clear);
    _repair = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_foreground && !_claiming) _authChanged(_auth.state);
    });
    _authChanged(_auth.state);
    _notify();
    return active;
  }

  String get accountRoute {
    final state = _auth.state;
    if (state is! AuthAuthenticated) return _entryRoute;
    if (!state.isOnboarded) return '/onboarding';
    if (!state.emailVerified) return '/verify-email';
    return '/unlock';
  }

  String? guardRoute(Uri uri) {
    if (!active) return null;
    final path = uri.path;
    final clean =
        !uri.hasFragment &&
        (!uri.hasQuery ||
            path == '/verify-email' &&
                uri.queryParametersAll.keys.every((key) => key == 'token'));
    if (!clean || (path != '/share' && !_accountRoutes.contains(path))) {
      clear(notify: false);
      return null;
    }
    _route = path;
    if (path != '/share') _departed = true;
    if (path == '/share' && _departed && !ready) return accountRoute;
    return null;
  }

  void _authChanged(AuthState state) {
    if (!active) return;
    if (_claiming) {
      if (entryShareAuthBinding(state) != entryShareAuthBinding(_observed!)) {
        clear();
      }
      return;
    }
    _ready = false;
    final revision = ++_authorityRevision;
    if (state is! AuthAuthenticated) {
      if (_principal != null || state is AuthInitial) clear();
      return;
    }
    final previous = _observed;
    if (_principal != null && state.userId != _principal ||
        previous != null &&
            (!previous.isVaultLocked && state.isVaultLocked ||
                previous.privateKey != null &&
                    !identical(previous.privateKey, state.privateKey) ||
                previous.isOnboarded && !state.isOnboarded ||
                previous.emailVerified && !state.emailVerified ||
                previous.isOnboarded &&
                    previous.permissions != state.permissions)) {
      clear();
      return;
    }
    _principal ??= state.userId;
    _observed = state;
    unawaited(_readAuthority(state, _epoch, revision));
  }

  Future<void> _readAuthority(
    AuthAuthenticated state,
    int epoch,
    int revision,
  ) async {
    try {
      final owner = await _ownerReader(state.userId);
      if (!active ||
          epoch != _epoch ||
          revision != _authorityRevision ||
          !identical(state, _auth.state)) {
        return;
      }
      if (owner == null ||
          owner.principalId != _principal ||
          owner.organizationId == null ||
          owner.authorizationGeneration == null ||
          _organization != null && owner.organizationId != _organization) {
        clear();
        return;
      }
      final old = _verifiedOwner;
      // Generation changes are compared with the state that verified that owner.
      final previous = _authorityState;
      if (old != null &&
          (old.authorizationGeneration != owner.authorizationGeneration &&
                  previous?.isOnboarded == true ||
              old.keyGeneration != owner.keyGeneration &&
                  previous?.isVaultLocked == false)) {
        clear();
        return;
      }
      _organization ??= owner.organizationId;
      _verifiedOwner = owner;
      _authorityState = state;
      _ready =
          state.isOnboarded &&
          state.emailVerified &&
          !state.isVaultLocked &&
          state.privateKey != null;
      _notify();
    } catch (_) {
      if (epoch == _epoch && revision == _authorityRevision) clear();
    }
  }

  Future<EntryShareReceptionCubit?> take({
    required int version,
    required EntryShareRecipientOwner owner,
    required Future<EntryShareRecipientOwner?> Function() ownerReader,
  }) async {
    if (!ready || _claiming || version != _version || owner != _verifiedOwner) {
      return null;
    }
    _claiming = true;
    final epoch = _epoch;
    final result = await _transfer!.resume(
      owner: owner,
      ownerReader: ownerReader,
    );
    if (_disposed || epoch != _epoch || !_foreground) {
      if (result != null) await result.close();
      return null;
    }
    clear(notify: false);
    return result;
  }

  void _linkChanged() {
    if ((_starting || active) && _ingress.version != _version) clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!active && !_starting) return;
    if (state == AppLifecycleState.detached ||
        state != AppLifecycleState.resumed &&
            !_accountRoutes.contains(_route)) {
      clear();
    } else if (state == AppLifecycleState.resumed) {
      _authChanged(_auth.state);
    }
  }

  void clear({bool notify = true}) {
    _epoch++;
    _authorityRevision++;
    _starting = false;
    _ready = false;
    _claiming = false;
    _transfer?.dispose();
    _transfer = null;
    _verifiedOwner = null;
    _observed = null;
    _authorityState = null;
    _principal = null;
    _organization = null;
    _expiry?.cancel();
    _repair?.cancel();
    _expiry = null;
    _repair = null;
    if (notify) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ingress.removeListener(_linkChanged);
    unawaited(_subscription.cancel());
    clear(notify: false);
    super.dispose();
  }
}
