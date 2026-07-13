import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'analytics_service.dart';

/// Builds HTTP headers that attach analytics and device context to every
/// outgoing API request.
///
/// Headers produced:
/// - `x-session-id` -- PostHog session ID (when available)
/// - `x-user-agent` -- `Palladin/mobile ({os} {osVersion})`
/// - `x-platform` -- `mobile` (analytics platform, read by the backend)
/// - `x-app-version` -- semantic version from pubspec
/// - `x-app-build-number` -- build number from pubspec
class AnalyticsHeadersService {
  AnalyticsHeadersService._();

  /// Analytics platform tag. The backend reads this from the `x-platform`
  /// transport header (web sends `web`) to attribute events; it replaces the
  /// former `platform` field in the auth request body.
  static const String _platform = 'mobile';

  static final AnalyticsHeadersService _instance =
      AnalyticsHeadersService._();
  static AnalyticsHeadersService get instance => _instance;

  PackageInfo? _packageInfo;

  Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  Future<Map<String, String>> getHeaders() async {
    final headers = <String, String>{};

    final sessionId = await AnalyticsService.instance.getSessionId();
    if (sessionId != null) {
      headers['x-session-id'] = sessionId;
    }

    headers['x-user-agent'] =
        'Palladin/mobile (${Platform.operatingSystem} ${Platform.operatingSystemVersion})';

    headers['x-platform'] = _platform;

    if (_packageInfo != null) {
      headers['x-app-version'] = _packageInfo!.version;
      headers['x-app-build-number'] = _packageInfo!.buildNumber;
    }

    return headers;
  }
}
