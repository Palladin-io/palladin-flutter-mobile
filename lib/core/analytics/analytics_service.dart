import 'package:posthog_flutter/posthog_flutter.dart';

import '../../config/env_config.dart';

/// Wraps the PostHog SDK with Claw Vault conventions.
///
/// All captured events are automatically prefixed with `mb:` to follow
/// the project-wide analytics naming format `{component}:{module}:{event}`.
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService _instance = AnalyticsService._();
  static AnalyticsService get instance => _instance;

  late final Posthog _posthog;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init(EnvConfig config) async {
    if (_initialized) return;
    if (config.posthogKey.isEmpty) return;

    final posthogConfig = PostHogConfig(config.posthogKey);
    posthogConfig.host = config.posthogHost;

    await Posthog().setup(posthogConfig);
    _posthog = Posthog();
    _initialized = true;
  }

  /// Captures an analytics event with the `mb:{module}:{event}` prefix.
  Future<void> capture(
    String module,
    String event, {
    Map<String, Object>? properties,
  }) async {
    if (!_initialized) return;
    await _posthog.capture(
      eventName: 'mb:$module:$event',
      properties: properties,
    );
  }

  /// Returns the current PostHog session ID, or `null` if not initialized.
  Future<String?> getSessionId() async {
    if (!_initialized) return null;
    return _posthog.getSessionId();
  }

  /// Identifies a user for analytics tracking.
  Future<void> identify(
    String userId, {
    Map<String, Object>? properties,
  }) async {
    if (!_initialized) return;
    await _posthog.identify(
      userId: userId,
      userProperties: properties,
    );
  }

  /// Resets the current user identity and starts a new anonymous session.
  Future<void> reset() async {
    if (!_initialized) return;
    await _posthog.reset();
  }
}
