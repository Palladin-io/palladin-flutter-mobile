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
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/notifications/data/services/push_notification_service.dart';
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

class _ClawVaultAppState extends State<ClawVaultApp> {
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

  @override
  void initState() {
    super.initState();
    // Forward tapped notifications (background / terminated / cold start)
    // into the navigation cubit, which the BlocListener below consumes.
    _pushService.onMessageTapped = _pushNavigationCubit.onNotificationTapped;
    // Handle a cold start triggered by a notification tap.
    _pushService.initialMessage().then((message) {
      if (message != null) {
        _pushNavigationCubit.onNotificationTapped(message);
      }
    });
  }

  @override
  void dispose() {
    _authBloc.close();
    super.dispose();
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
    } else if (state is AuthUnauthenticated) {
      _pushService.unregister();
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
