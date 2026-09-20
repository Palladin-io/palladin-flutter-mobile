import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../data/services/entry_sharing/entry_share_ingress.dart';

final class EntryShareNavigation with WidgetsBindingObserver {
  EntryShareNavigation(this._ingress, this._router);
  final EntryShareIngress _ingress;
  final GoRouter _router;
  bool _started = false, _disposed = false, _scheduled = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _ingress.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _changed();
  }

  void _changed() {
    if (_disposed || _scheduled || !_ingress.hasPending) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (_disposed ||
          !_ingress.hasPending ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
        return;
      }
      // The sole router input is this constant, never a URL, ID or capability.
      if (_router.routeInformationProvider.value.uri.path !=
          AppRoutes.entryShare) {
        _router.go(AppRoutes.entryShare);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _changed();
    if (state == AppLifecycleState.detached) _ingress.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ingress.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
  }
}
