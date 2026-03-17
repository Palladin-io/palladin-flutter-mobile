import 'package:flutter/material.dart';

import 'app.dart';
import 'config/env_config.dart';
import 'core/analytics/analytics_headers_service.dart';
import 'core/analytics/analytics_service.dart';
import 'core/di/injection.dart';

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
  configureDependencies(config);

  runApp(ClawVaultApp(config: config));
}
