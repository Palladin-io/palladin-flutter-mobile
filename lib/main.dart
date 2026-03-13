import 'package:flutter/material.dart';

import 'app.dart';
import 'config/env_config.dart';
import 'core/di/injection.dart';

/// Default entry point. Falls back to **staging** configuration.
///
/// Prefer using the flavor-specific entry points for running on device:
/// ```
/// flutter run --flavor staging -t lib/main_staging.dart
/// flutter run --flavor production -t lib/main_production.dart
/// ```
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final config = EnvConfig.staging();
  configureDependencies(config);
  runApp(ClawVaultApp(config: config));
}
