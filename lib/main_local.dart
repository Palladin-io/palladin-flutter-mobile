import 'package:flutter/material.dart';

import 'app.dart';
import 'config/env_config.dart';
import 'core/analytics/analytics_headers_service.dart';
import 'core/analytics/analytics_service.dart';
import 'core/di/injection.dart';

/// Entry point for the **local** flavor (localhost backend).
///
/// Run with:
/// ```
/// flutter run --flavor local -t lib/main_local.dart
/// ```
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = EnvConfig.local();

  await AnalyticsService.instance.init(config);
  await AnalyticsHeadersService.instance.init();
  configureDependencies(config);

  runApp(ClawVaultApp(config: config));
}
