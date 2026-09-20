import 'dart:io';

/// Application flavor representing the target environment.
enum AppFlavor { local, staging, production }

/// Holds all environment-specific configuration values.
///
/// Each flavor (staging, production) has its own factory constructor
/// that provides the correct URLs, keys, and identifiers.
class EnvConfig {
  static const _productionCertificatePins = <String>[];

  const EnvConfig._({
    required this.flavor,
    required this.appName,
    required this.apiBaseUrl,
    required this.publicAssetBaseUrl,
    required this.posthogKey,
    required this.posthogHost,
    required this.googleServerClientId,
    required this.sharingWebOrigin,
    this.certificatePins = const [],
  });

  final AppFlavor flavor;
  final String appName;
  final String apiBaseUrl;
  final String publicAssetBaseUrl;
  final String posthogKey;
  final String posthogHost;
  final String sharingWebOrigin;

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
  factory EnvConfig.local({
    String sharingWebOrigin = const String.fromEnvironment(
      'PALLADIN_SHARING_WEB_ORIGIN',
    ),
  }) {
    final host = Platform.isAndroid ? '10.0.2.2' : 'localhost';
    return EnvConfig._(
      flavor: AppFlavor.local,
      sharingWebOrigin: sharingWebOrigin,
      appName: 'Palladin (Local)',
      apiBaseUrl: 'http://$host:5000',
      publicAssetBaseUrl: 'http://$host:4566/palladin-local-public-assets',
      posthogKey: const String.fromEnvironment('POSTHOG_PROJECT_KEY'),
      posthogHost: 'https://eu.i.posthog.com',
      // Staging Firebase project used for local development
      googleServerClientId:
          '1006466869105-3j8tlokqhsej6cnu0tcvohb7bgd13s9v.apps.googleusercontent.com',
    );
  }

  /// Staging environment targeting `api.stage.palladin.io`.
  factory EnvConfig.staging({
    String sharingWebOrigin = const String.fromEnvironment(
      'PALLADIN_SHARING_WEB_ORIGIN',
    ),
  }) {
    return EnvConfig._(
      flavor: AppFlavor.staging,
      sharingWebOrigin: sharingWebOrigin,
      appName: 'Palladin (Stage)',
      apiBaseUrl: 'https://api.stage.palladin.io',
      publicAssetBaseUrl: 'https://assets.palladin.io',
      posthogKey: const String.fromEnvironment('POSTHOG_PROJECT_KEY'),
      posthogHost: 'https://eu.i.posthog.com',
      googleServerClientId:
          '1006466869105-3j8tlokqhsej6cnu0tcvohb7bgd13s9v.apps.googleusercontent.com',
    );
  }

  /// Production distribution configuration.
  ///
  /// Store testing keeps the production app identity and Firebase/signing
  /// configuration while temporarily targeting the staging API.
  factory EnvConfig.production({
    bool useStagingBackend = false,
    String sharingWebOrigin = const String.fromEnvironment(
      'PALLADIN_SHARING_WEB_ORIGIN',
    ),
  }) {
    return EnvConfig._(
      flavor: AppFlavor.production,
      sharingWebOrigin: sharingWebOrigin,
      appName: 'Palladin',
      apiBaseUrl: useStagingBackend
          ? 'https://api.stage.palladin.io'
          : 'https://api.palladin.io',
      publicAssetBaseUrl: 'https://assets.palladin.io',
      posthogKey: const String.fromEnvironment('POSTHOG_PROJECT_KEY'),
      posthogHost: 'https://eu.i.posthog.com',
      googleServerClientId:
          '1006466869105-3j8tlokqhsej6cnu0tcvohb7bgd13s9v.apps.googleusercontent.com',
      // Staging and production must never share certificate pin sets.
      certificatePins: useStagingBackend
          ? const []
          : _productionCertificatePins,
    );
  }

  bool get isLocal => flavor == AppFlavor.local;
  bool get isStaging => flavor == AppFlavor.staging;
  bool get isProduction => flavor == AppFlavor.production;
}
