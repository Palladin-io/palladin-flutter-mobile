import 'package:flutter/material.dart';

import 'app.dart';
import 'config/env_config.dart';
import 'core/analytics/analytics_headers_service.dart';
import 'core/analytics/analytics_service.dart';
import 'core/di/injection.dart';

/// Default entry point. Falls back to **staging** configuration.
///
/// Prefer using the flavor-specific entry points for running on device:
/// ```
/// flutter run --flavor staging -t lib/main_staging.dart
/// flutter run --flavor production -t lib/main_production.dart
/// ```
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = EnvConfig.staging();

  await AnalyticsService.instance.init(config);
  await AnalyticsHeadersService.instance.init();
  configureDependencies(config);

  runApp(ClawVaultApp(config: config));
}
