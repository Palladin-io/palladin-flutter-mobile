import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/storage/biometric_key_store.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../data/autofill_credential_source.dart';
import '../data/autofill_password_verifier.dart';
import '../data/autofill_request_controller.dart';
import '../data/autofill_request_session.dart';
import '../data/autofill_source_access_service.dart';
import 'autofill_request_page.dart';

/// Keeps OS request lifetime separate from the main app's navigation/session.
class AutoFillRequestHost extends StatefulWidget {
  const AutoFillRequestHost({
    super.key,
    required this.navigatorKey,
    required this.prepare,
    required this.child,
    this.requestPageBuilder,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Future<AutoFillRequestSession> Function() prepare;
  final Widget child;
  @visibleForTesting
  final WidgetBuilder? requestPageBuilder;
  @override
  State<AutoFillRequestHost> createState() => _AutoFillRequestHostState();
}

class _AutoFillRequestHostState extends State<AutoFillRequestHost>
    with WidgetsBindingObserver {
  late final _auth = getIt<AuthBloc>();
  late final _requests = getIt<AutoFillRequestController>();
  late final _source = getIt<AutoFillSourceAccessService>();
  StreamSubscription<AuthState>? _authSubscription;
  AuthState? _previous;
  bool _running = false, _again = false;
  String? _opened, _failedNotice;
  bool get _enabled =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _previous = _auth.state;
    _authSubscription = _auth.stream.listen((state) {
      final previous = _previous;
      _previous = state;
      if (previous is AuthAuthenticated &&
          (state is! AuthAuthenticated ||
              state.userId != previous.userId ||
              (!previous.isVaultLocked && state.isVaultLocked))) {
        unawaited(_requests.cancel());
      }
      _schedule();
    });
    _requests.addListener(_schedule);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_poll());
    });
  }

  Future<void> _poll() async {
    try {
      await _requests.poll();
      if (mounted) _schedule();
    } catch (_) {
      _noticeFailure();
    }
  }

  void _schedule() {
    if (!mounted) return;
    _again = true;
    if (!_running) unawaited(_drain());
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (mounted && _again) {
        _again = false;
        try {
          await _advance();
        } catch (_) {
          _noticeFailure();
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _advance() async {
    final request = _requests.request;
    final state = _auth.state;
    if (request == null || state is! AuthAuthenticated) return;
    await _requests.ensureBound();
    final ready = _auth.state;
    if (!mounted ||
        !identical(request, _requests.request) ||
        ready is! AuthAuthenticated ||
        ready.userId != state.userId ||
        _requests.boundPrincipalId != ready.userId ||
        ready.isVaultLocked ||
        ready.privateKey == null ||
        _opened == request.id) {
      return;
    }
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    _opened = request.id;
    unawaited(
      navigator
          .push<void>(
            MaterialPageRoute(
              builder:
                  widget.requestPageBuilder ??
                  (_) => AutoFillRequestPage(
                    controller: _requests,
                    credentials: getIt<AutoFillCredentialSource>(),
                    access: _source,
                    prepare: widget.prepare,
                    authorizePassword: getIt<AutoFillPasswordVerifier>().verify,
                    biometricAvailable: () async {
                      final keys = getIt<BiometricKeyStore>();
                      return await keys.canStore() && await keys.isEnrolled();
                    },
                  ),
            ),
          )
          .whenComplete(() async {
            if (_opened == request.id) _opened = null;
            if (identical(_requests.request, request)) await _requests.cancel();
          }),
    );
  }

  void _noticeFailure() {
    final request = _requests.request;
    final context = widget.navigatorKey.currentContext;
    if (!mounted ||
        request == null ||
        context == null ||
        _failedNotice == request.id) {
      return;
    }
    _failedNotice = request.id;
    final copy = AppLocalizations.of(context);
    if (copy != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(copy.autofillRequestFailed)));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) return;
    if (state == AppLifecycleState.resumed) unawaited(_poll());
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        !_requests.isAuthenticating) {
      unawaited(_requests.cancel());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_enabled) _requests.removeListener(_schedule);
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
