import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'config/env_config.dart';
import 'core/analytics/analytics_headers_service.dart';
import 'core/analytics/analytics_service.dart';
import 'core/di/injection.dart';
import 'core/firebase/push_bootstrap.dart';
import 'core/storage/user_preferences.dart';

/// Entry point for the **production** flavor.
///
/// Run with:
/// ```
/// flutter run --flavor production -t lib/main_production.dart
/// ```
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = EnvConfig.production();

  await AnalyticsService.instance.init(config);
  await AnalyticsHeadersService.instance.init();
  await bootstrapPush();
  configureDependencies(config);

  final prefs = UserPreferences(const FlutterSecureStorage());
  final themeMode = await prefs.themeMode;
  final locale = await prefs.locale;

  runApp(ClawVaultApp(
    config: config,
    userPreferences: prefs,
    initialThemeMode: themeMode,
    initialLocale: locale,
  ));
}
