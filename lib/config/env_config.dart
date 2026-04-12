import 'dart:io';

/// Application flavor representing the target environment.
enum AppFlavor { local, staging, production }

/// Holds all environment-specific configuration values.
///
/// Each flavor (staging, production) has its own factory constructor
/// that provides the correct URLs, keys, and identifiers.
class EnvConfig {
  const EnvConfig._({
    required this.flavor,
    required this.appName,
    required this.apiBaseUrl,
    required this.posthogKey,
    required this.posthogHost,
    required this.googleServerClientId,
  });

  final AppFlavor flavor;
  final String appName;
  final String apiBaseUrl;
  final String posthogKey;
  final String posthogHost;
  /// Google OAuth web client ID used as `serverClientId` in GoogleSignIn.
  /// Ensures the ID token audience matches what the backend validates against.
  final String googleServerClientId;

  /// Local development environment targeting `localhost:5000`.
  ///
  /// Uses `10.0.2.2` on Android emulator (special alias for host loopback)
  /// and `localhost` on iOS simulator and physical devices via USB proxy.
  factory EnvConfig.local() {
    final host = Platform.isAndroid ? '10.0.2.2' : 'localhost';
    return EnvConfig._(
      flavor: AppFlavor.local,
      appName: 'Claw Vault (Local)',
      apiBaseUrl: 'http://$host:5000',
      posthogKey: '',
      posthogHost: 'https://app.posthog.com',
      // Staging Firebase project used for local development
      googleServerClientId: '810617442937-uqjo7cinqaemjjd3r3qtr7lhag44ebc5.apps.googleusercontent.com',
    );
  }

  /// Staging environment targeting `api.stage.clawvault.io`.
  factory EnvConfig.staging() {
    return const EnvConfig._(
      flavor: AppFlavor.staging,
      appName: 'Claw Vault (Stage)',
      apiBaseUrl: 'https://api.stage.clawvault.io',
      posthogKey: '', // TODO: Add PostHog staging project key
      posthogHost: 'https://app.posthog.com',
      googleServerClientId: '810617442937-uqjo7cinqaemjjd3r3qtr7lhag44ebc5.apps.googleusercontent.com',
    );
  }

  /// Production environment targeting `api.clawvault.io`.
  factory EnvConfig.production() {
    return const EnvConfig._(
      flavor: AppFlavor.production,
      appName: 'Claw Vault',
      apiBaseUrl: 'https://api.clawvault.io',
      posthogKey: '', // TODO: Add PostHog production project key
      posthogHost: 'https://app.posthog.com',
      googleServerClientId: '', // TODO: set production web client ID
    );
  }

  bool get isLocal => flavor == AppFlavor.local;
  bool get isStaging => flavor == AppFlavor.staging;
  bool get isProduction => flavor == AppFlavor.production;
}
