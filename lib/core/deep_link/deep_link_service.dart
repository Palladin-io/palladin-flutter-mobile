import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';

/// Resolves custom-scheme deep links (`palladin://…`) into in-app routes.
///
/// Currently handles the email-verification link
/// `palladin://verify-email?token=<token>`, mapping it to the
/// `/verify-email?token=<token>` route. Only explicitly recognized hosts
/// are mapped — an unknown link resolves to `null` so a malicious or
/// malformed URL can never drive arbitrary navigation.
///
/// The token is opaque and single-use server-side; it is never logged.
class DeepLinkService {
  DeepLinkService({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;

  static const _scheme = 'palladin';

  /// Resolves the link that cold-started the app (if any) into a route.
  Future<String?> initialRoute() async {
    try {
      final uri = await _appLinks.getInitialLink();
      return uri == null ? null : _routeFor(uri);
    } catch (e) {
      AppLogger.w('DeepLink', 'Initial link resolution failed: ${e.runtimeType}');
      return null;
    }
  }

  /// Subscribes to deep links delivered while the app is running (resume /
  /// warm start). [onRoute] receives the resolved in-app route for each
  /// recognized link.
  void listen(void Function(String route) onRoute) {
    _subscription?.cancel();
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) {
        final route = _routeFor(uri);
        if (route != null) onRoute(route);
      },
      onError: (Object e) =>
          AppLogger.w('DeepLink', 'Link stream error: ${e.runtimeType}'),
    );
  }

  /// Maps a recognized [uri] to an in-app route, or `null` if unhandled.
  @visibleForTesting
  String? routeForUri(Uri uri) => _routeFor(uri);

  String? _routeFor(Uri uri) {
    if (uri.scheme != _scheme) return null;
    // Both `palladin://verify-email?token=…` (host) and
    // `palladin:///verify-email?token=…` (path) shapes are tolerated.
    final target = uri.host.isNotEmpty ? uri.host : uri.pathSegments.firstOrNull;
    switch (target) {
      case 'verify-email':
        final token = uri.queryParameters['token'];
        if (token == null || token.isEmpty) return '/verify-email';
        return Uri(
          path: '/verify-email',
          queryParameters: {'token': token},
        ).toString();
      default:
        AppLogger.w('DeepLink', 'Unhandled deep link');
        return null;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
