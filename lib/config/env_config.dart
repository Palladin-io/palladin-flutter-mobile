import 'dart:io';

/// Application flavor representing the target environment.
enum AppFlavor { local, staging, production }

/// Holds all environment-specific configuration values.
///
/// Each flavor (staging, production) has its own factory constructor
/// that reads explicitly supplied deployment values.
class EnvConfig {
  static const _productionCertificatePins = <String>[];

  const EnvConfig._({
    required this.flavor,
    required this.appName,
    required this.apiBaseUrl,
    required this.posthogKey,
    required this.posthogHost,
    required this.googleServerClientId,
    this.certificatePins = const [],
  });

  final AppFlavor flavor;
  final String appName;
  final String apiBaseUrl;
  final String posthogKey;
  final String posthogHost;

  bool get clientAnalyticsReleased =>
      const bool.fromEnvironment('CLIENT_ANALYTICS_RELEASED');

  /// Google OAuth web client ID used as `serverClientId` in GoogleSignIn.
  /// Ensures the ID token audience matches what the backend validates against.
  final String googleServerClientId;

  /// Base64 SHA-256 SPKI pins; empty = pinning disabled. Always ship a backup
  /// pin before switching the server cert.
  final List<String> certificatePins;

  /// Local development environment targeting `localhost:5000`.
  ///
  /// Uses `10.0.2.2` on Android emulator (special alias for host loopback)
  /// and `localhost` on iOS simulator and physical devices via USB proxy.
  factory EnvConfig.local() {
    final host = Platform.isAndroid ? '10.0.2.2' : 'localhost';
    return EnvConfig._(
      flavor: AppFlavor.local,
      appName: 'Palladin (Local)',
      apiBaseUrl: 'http://$host:5000',
      posthogKey: const String.fromEnvironment('POSTHOG_PROJECT_KEY'),
      posthogHost: 'https://eu.i.posthog.com',
      googleServerClientId: const String.fromEnvironment(
        'GOOGLE_SERVER_CLIENT_ID',
      ),
    );
  }

  /// Staging distribution with an explicitly configured HTTPS API.
  factory EnvConfig.staging({
    String apiBaseUrl = const String.fromEnvironment('PALLADIN_API_BASE_URL'),
  }) {
    return EnvConfig._(
      flavor: AppFlavor.staging,
      appName: 'Palladin (Stage)',
      apiBaseUrl: _requireApiBaseUrl(apiBaseUrl),
      posthogKey: const String.fromEnvironment('POSTHOG_PROJECT_KEY'),
      posthogHost: 'https://eu.i.posthog.com',
      googleServerClientId: const String.fromEnvironment(
        'GOOGLE_SERVER_CLIENT_ID',
      ),
    );
  }

  /// Production distribution configuration.
  ///
  /// Store testing keeps the production app identity and Firebase/signing
  /// configuration while temporarily targeting the staging API.
  factory EnvConfig.production({
    bool useStagingBackend = false,
    String apiBaseUrl = const String.fromEnvironment('PALLADIN_API_BASE_URL'),
  }) {
    return EnvConfig._(
      flavor: AppFlavor.production,
      appName: 'Palladin',
      apiBaseUrl: _requireApiBaseUrl(apiBaseUrl),
      posthogKey: const String.fromEnvironment('POSTHOG_PROJECT_KEY'),
      posthogHost: 'https://eu.i.posthog.com',
      googleServerClientId: const String.fromEnvironment(
        'GOOGLE_SERVER_CLIENT_ID',
      ),
      // Staging and production must never share certificate pin sets.
      certificatePins: useStagingBackend
          ? const []
          : _productionCertificatePins,
    );
  }

  static String _requireApiBaseUrl(String value) {
    final uri = Uri.tryParse(value);
    if (value != value.trim() ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError(
        'PALLADIN_API_BASE_URL must be an absolute HTTPS URL '
        'without credentials, query or fragment.',
      );
    }
    return value;
  }

  bool get isLocal => flavor == AppFlavor.local;
  bool get isStaging => flavor == AppFlavor.staging;
  bool get isProduction => flavor == AppFlavor.production;
}
