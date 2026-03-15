import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'config/env_config.dart';
import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';

/// Root application widget for Claw Vault.
///
/// Sets up the [AuthBloc] at the top of the widget tree, configures
/// [GoRouter] with auth-aware redirects, and applies the dark theme
/// matching the mobile prototype.
class ClawVaultApp extends StatelessWidget {
  const ClawVaultApp({super.key, required this.config});

  final EnvConfig config;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<AuthBloc>()..add(const AuthCheckRequested()),
      child: Builder(
        builder: (context) {
          final authBloc = context.read<AuthBloc>();
          final router = createRouter(authBloc);

          return MaterialApp.router(
            title: config.appName,
            debugShowCheckedModeBanner: false,
            theme: _buildDarkTheme(),
            routerConfig: router,
          );
        },
      ),
    );
  }

  /// Dark theme matching the Claw Vault design prototype.
  ///
  /// Background: deep navy `#000B2E`
  /// Surface: `#1a2a4a`
  /// Primary/accent: teal `#48ECDF`
  /// Error/brand: red `#FF4D5F`
  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF000B2E),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF48ECDF),
        error: Color(0xFFFF4D5F),
        surface: Color(0xFF1a2a4a),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1a2a4a),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
