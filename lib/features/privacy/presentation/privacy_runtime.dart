import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import 'consent_cubit.dart';
import 'privacy_consent_sheet.dart';

/// One runtime at the app root, shared by onboarding and settings surfaces.
class PrivacyRuntime extends StatefulWidget {
  const PrivacyRuntime({
    super.key,
    required this.router,
    required this.child,
    this.analytics,
  });
  final GoRouter router;
  final Widget child;
  final AnalyticsService? analytics;
  @override
  State<PrivacyRuntime> createState() => _PrivacyRuntimeState();
}

class _PrivacyRuntimeState extends State<PrivacyRuntime>
    with WidgetsBindingObserver {
  late final ConsentCubit _consents = context.read<ConsentCubit>();
  final _prompted = <String>{};
  bool _offerScheduled = false;
  bool _foreground = true;
  void _offerChoices({bool present = false}) {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated ||
        widget.router.routerDelegate.currentConfiguration.isEmpty) {
      return;
    }
    if (auth.needsPrivacyChoices ||
        widget.router.routerDelegate.state.uri.path == '/settings/privacy') {
      _prompted.add(auth.userId);
      return;
    }
    if (!auth.isOnboarded ||
        !_foreground ||
        widget.router.routerDelegate.state.uri.path == '/verify-email' ||
        !auth.emailVerified ||
        auth.isVaultLocked ||
        _prompted.contains(auth.userId) ||
        _consents.state.loading ||
        _consents.state.error != null ||
        _consents.state.userId != auth.userId) {
      return;
    }
    if (_consents.state.consents.any((c) => c.status == 'unknown')) {
      // Reads can recover while a form is mounted. Push a native sheet above
      // that flow instead of setting the startup flag that redirects to /privacy-choices.
      // Recheck account, route and consent after the navigator has finished building.
      if (!present) {
        if (_offerScheduled) return;
        _offerScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _offerScheduled = false;
          if (mounted) _offerChoices(present: true);
        });
        WidgetsBinding.instance.ensureVisualUpdate();
        return;
      }
      final navigatorContext =
          widget.router.routerDelegate.navigatorKey.currentContext;
      if (navigatorContext == null) return;
      _prompted.add(auth.userId);
      unawaited(
        showPrivacyConsentSheet(navigatorContext, source: 'mobile_onboarding'),
      );
    }
  }

  void _bind(AuthState state) {
    _offerChoices();
    unawaited(
      _consents.bind(
        state is AuthAuthenticated ? state.userId : null,
        Localizations.localeOf(context).languageCode,
      ),
    );
  }

  void _pageview() {
    _offerChoices();
    final delegate = widget.router.routerDelegate;
    if (delegate.currentConfiguration.isEmpty) return;
    // The configuration belongs to the underlying route after context.push().
    // The top state retains the visible match's template, never its resolved
    // path parameters, query or fragment. Missing templates fail closed.
    final template = delegate.state.fullPath;
    if (template == null || template.isEmpty) return;
    unawaited(
      (widget.analytics ?? AnalyticsService.instance).pageview(template),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.router.routerDelegate.addListener(_pageview);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind(context.read<AuthBloc>().state);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _consents.setForeground(_foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.router.routerDelegate.removeListener(_pageview);
    unawaited(_consents.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: [
      BlocListener<AuthBloc, AuthState>(listener: (_, state) => _bind(state)),
      BlocListener<ConsentCubit, ConsentState>(
        listener: (_, _) {
          _pageview();
        },
      ),
    ],
    child: widget.child,
  );
}
