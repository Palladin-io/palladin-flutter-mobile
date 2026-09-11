import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import 'consent_cubit.dart';

/// One runtime at the app root, shared by onboarding and settings surfaces.
class PrivacyRuntime extends StatefulWidget {
  const PrivacyRuntime({super.key, required this.router, required this.child});
  final GoRouter router;
  final Widget child;
  @override
  State<PrivacyRuntime> createState() => _PrivacyRuntimeState();
}

class _PrivacyRuntimeState extends State<PrivacyRuntime>
    with WidgetsBindingObserver {
  late final ConsentCubit _consents = context.read<ConsentCubit>();
  void _bind(AuthState state) {
    unawaited(
      _consents.bind(
        state is AuthAuthenticated ? state.userId : null,
        Localizations.localeOf(context).languageCode,
      ),
    );
  }

  void _pageview() {
    unawaited(
      AnalyticsService.instance.pageview(
        widget.router.routerDelegate.currentConfiguration.fullPath,
      ),
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
    _consents.setForeground(state == AppLifecycleState.resumed);
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
      BlocListener<ConsentCubit, ConsentState>(listener: (_, _) => _pageview()),
    ],
    child: widget.child,
  );
}
