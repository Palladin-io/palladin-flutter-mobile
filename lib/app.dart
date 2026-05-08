import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

class ClawVaultApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => getIt<AuthBloc>()..add(const AuthCheckRequested()),
        ),
        BlocProvider(create: (_) => ThemeCubit(userPreferences, initial: initialThemeMode)),
        BlocProvider(create: (_) => LocaleCubit(userPreferences, initial: initialLocale)),
      ],
      child: Builder(
        builder: (context) {
          final themeMode = context.watch<ThemeCubit>().state;
          final locale = context.watch<LocaleCubit>().state;
          final router = createRouter(context.read<AuthBloc>());

          return MaterialApp.router(
            title: config.appName,
            debugShowCheckedModeBanner: false,
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            themeMode: themeMode,
            locale: locale,
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          );
        },
      ),
    );
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
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
