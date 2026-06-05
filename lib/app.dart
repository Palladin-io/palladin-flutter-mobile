import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'l10n/generated/app_localizations.dart';

import 'config/env_config.dart';
import 'core/di/injection.dart';
import 'core/l10n/locale_cubit.dart';
import 'core/router/app_router.dart';
import 'core/storage/user_preferences.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/theme_cubit.dart';
import 'features/agents/presentation/bloc/agents_cubit.dart';
import 'features/approval/presentation/cubit/pending_grants_cubit.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/notifications/data/services/notification_signalr_service.dart';
import 'features/notifications/data/services/push_notification_service.dart';
import 'features/notifications/domain/entities/push_message.dart';
import 'features/notifications/presentation/cubit/push_navigation_cubit.dart';

class ClawVaultApp extends StatefulWidget {
  const ClawVaultApp({
    super.key,
    required this.config,
    required this.userPreferences,
    required this.initialThemeMode,
    required this.initialLocale,
  });

  final EnvConfig config;
  final UserPreferences userPreferences;
  final ThemeMode initialThemeMode;
  final Locale initialLocale;

  @override
  State<ClawVaultApp> createState() => _ClawVaultAppState();
}

class _ClawVaultAppState extends State<ClawVaultApp>
    with WidgetsBindingObserver {
  // Stable across rebuilds so the push deep-link can navigate via
  // GoRouter regardless of which subtree currently has focus.
  final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  late final AuthBloc _authBloc =
      getIt<AuthBloc>()..add(const AuthCheckRequested());
  late final GoRouter _router =
      createRouter(_authBloc, navigatorKey: _navigatorKey);

  final PushNavigationCubit _pushNavigationCubit =
      getIt<PushNavigationCubit>();
  final PushNotificationService _pushService =
      getIt<PushNotificationService>();

  // In-app real-time channel (foreground). Works on the simulator too, unlike
  // FCM. Connected while authenticated; FCM/APNs covers the background.
  final NotificationSignalRService _signalR =
      getIt<NotificationSignalRService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Forward tapped notifications (background / terminated / cold start)
    // into the navigation cubit, which the BlocListener below consumes.
    _pushService.onMessageTapped = _pushNavigationCubit.onNotificationTapped;
    // Foreground push → live-refresh the relevant list. Tap-routing stays on
    // onMessageTapped above.
    _pushService.onMessageReceived = _onForegroundPush;
    // In-app real-time over SignalR → same refresh handler.
    _signalR.onNotification = _onSignalRNotification;
    // Handle a cold start triggered by a notification tap. Guard on `mounted`
    // — if the app is torn down before the future resolves, the cubit may
    // already be closed (Bad state: Cubit is already closed).
    _pushService.initialMessage().then((message) {
      if (!mounted || message == null) return;
      _pushNavigationCubit.onNotificationTapped(message);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _signalR.disconnect();
    _authBloc.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On returning to the foreground, re-open the real-time channel (idempotent)
    // and quietly refresh live lists so anything that changed while backgrounded
    // (and any events missed while the socket was suspended) shows up.
    if (state == AppLifecycleState.resumed) {
      if (_authBloc.state is AuthAuthenticated) _signalR.connect();
      _refreshLiveData();
    }
  }

  /// Quiet refresh of the in-app lists that mirror server state, gated on an
  /// authenticated session so we never hit the API while logged out.
  void _refreshLiveData() {
    if (_authBloc.state is! AuthAuthenticated) return;
    getIt<AgentsCubit>().refresh();
    getIt<PendingGrantsCubit>().refresh();
  }

  /// A foreground push arrived — refresh the list it affects (agents for
  /// agent_pending; grant lifecycle events also touch the agents/approvals
  /// surfaces). Best-effort and auth-gated.
  void _onForegroundPush(PushMessage message) {
    if (_authBloc.state is! AuthAuthenticated) return;
    switch (message.type) {
      case PushNotificationType.agentPending:
        getIt<AgentsCubit>().refresh();
      case PushNotificationType.grantPending:
      case PushNotificationType.grantApproved:
        // A grant lifecycle change touches both the agents surface and the
        // pending-approvals queue (and its nav badge).
        getIt<AgentsCubit>().refresh();
        getIt<PendingGrantsCubit>().refresh();
      case PushNotificationType.unknown:
        break;
    }
  }

  /// A SignalR (in-app real-time) notification arrived. Unlike FCM, SignalR
  /// carries no OS-level notification, so we surface a visible heads-up banner
  /// ourselves (the web shows a toast for the same events) in addition to
  /// refreshing the affected list.
  void _onSignalRNotification(PushMessage message) {
    _onForegroundPush(message);
    if (_authBloc.state is! AuthAuthenticated) return;
    // Pass the full routing data so a tap on the banner deep-links to the
    // specific agent / grant (not just the list).
    _pushService.showLocalNotification(
      title: message.title,
      body: message.body,
      data: message.toRoutingData(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _authBloc),
        BlocProvider.value(value: _pushNavigationCubit),
        BlocProvider(
          create: (_) => ThemeCubit(
            widget.userPreferences,
            initial: widget.initialThemeMode,
          ),
        ),
        BlocProvider(
          create: (_) => LocaleCubit(
            widget.userPreferences,
            initial: widget.initialLocale,
          ),
        ),
      ],
      child: MultiBlocListener(
        listeners: [
          // Auth-driven push token lifecycle: register on login, remove
          // on logout. Runs only on state class transitions so a key
          // unlock (which re-emits AuthAuthenticated) doesn't re-register.
          BlocListener<AuthBloc, AuthState>(
            listenWhen: (prev, curr) => prev.runtimeType != curr.runtimeType,
            listener: _onAuthStateChanged,
          ),
          // Deep-link: navigate when a tapped notification resolves to a
          // route, then clear the cubit so the next tap re-fires.
          BlocListener<PushNavigationCubit, String?>(
            listener: (context, route) {
              if (route == null) return;
              _router.go(route);
              _pushNavigationCubit.consumed();
            },
          ),
        ],
        child: Builder(
          builder: (context) {
            final themeMode = context.watch<ThemeCubit>().state;
            final locale = context.watch<LocaleCubit>().state;

            return MaterialApp.router(
              title: widget.config.appName,
              debugShowCheckedModeBanner: false,
              theme: _buildLightTheme(),
              darkTheme: _buildDarkTheme(),
              themeMode: themeMode,
              locale: locale,
              routerConfig: _router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            );
          },
        ),
      ),
    );
  }

  void _onAuthStateChanged(BuildContext context, AuthState state) {
    if (state is AuthAuthenticated) {
      // Fire-and-forget: registration is non-blocking and failure is
      // non-fatal (handled/logged inside the service).
      _pushService.registerForCurrentUser();
      // Open the in-app real-time channel for instant updates.
      _signalR.connect();
    } else if (state is AuthUnauthenticated) {
      _pushService.unregister();
      _signalR.disconnect();
    }
  }

  /// Light theme — warm cream background, navy text.
  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      scaffoldBackgroundColor: AppColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: AppColors.brandRed,
        error: AppColors.brandRed,
        surface: AppColors.lightSurface,
        onSurface: AppColors.darkBackground,
        onPrimary: AppColors.onBrandRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightSurface,
        foregroundColor: AppColors.darkBackground,
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Dark theme — deep navy background, cream text.
  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      scaffoldBackgroundColor: AppColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.tealAccent,
        error: AppColors.brandRed,
        surface: AppColors.darkSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: AppColors.onBrandRed,
        elevation: 0,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brandRed,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
