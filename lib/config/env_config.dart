/// Application flavor representing the target environment.
enum AppFlavor { staging, production }

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
  });

  final AppFlavor flavor;
  final String appName;
  final String apiBaseUrl;
  final String posthogKey;
  final String posthogHost;

  /// Staging environment targeting `api.stage.clawvault.io`.
  factory EnvConfig.staging() {
    return const EnvConfig._(
      flavor: AppFlavor.staging,
      appName: 'Claw Vault (Stage)',
      apiBaseUrl: 'https://api.stage.clawvault.io',
      posthogKey: '', // TODO: Add PostHog staging project key
      posthogHost: 'https://app.posthog.com',
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
    );
  }

  bool get isStaging => flavor == AppFlavor.staging;
  bool get isProduction => flavor == AppFlavor.production;
}
