import 'package:flutter/material.dart';

import 'app.dart';
import 'config/env_config.dart';

/// Entry point for the **staging** flavor.
///
/// Run with:
/// ```
/// flutter run --flavor staging -t lib/main_staging.dart
/// ```
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO: Initialize Firebase with staging google-services.json / GoogleService-Info.plist

  final config = EnvConfig.staging();
  runApp(ClawVaultApp(config: config));
}
