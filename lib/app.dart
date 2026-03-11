import 'package:flutter/material.dart';

import 'config/env_config.dart';

/// Root application widget for Claw Vault.
///
/// Receives the resolved [EnvConfig] so that the app can access
/// environment-specific values (API base URL, PostHog keys, etc.)
/// without any global mutable state.
class ClawVaultApp extends StatelessWidget {
  const ClawVaultApp({super.key, required this.config});

  final EnvConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: config.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: HomePage(config: config),
    );
  }
}

/// Temporary home page that displays the current environment.
///
/// This will be replaced once the real feature shell is built.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.config});

  final EnvConfig config;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(config.appName),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Environment: ${config.flavor.name}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'API: ${config.apiBaseUrl}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
