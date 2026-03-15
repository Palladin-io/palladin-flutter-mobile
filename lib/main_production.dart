import 'package:flutter/material.dart';

import 'app.dart';
import 'config/env_config.dart';
import 'core/di/injection.dart';

/// Entry point for the **production** flavor.
///
/// Run with:
/// ```
/// flutter run --flavor production -t lib/main_production.dart
/// ```
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO: Initialize Firebase with production google-services.json / GoogleService-Info.plist

  final config = EnvConfig.production();
  configureDependencies(config);
  runApp(ClawVaultApp(config: config));
}
