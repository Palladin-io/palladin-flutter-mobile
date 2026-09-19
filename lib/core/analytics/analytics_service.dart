import 'dart:async';

import 'package:dio/dio.dart';

import '../../config/env_config.dart';
import '../utils/request_id.dart';

/// Narrow, consent-gated EU capture transport. No native analytics SDK,
/// automatic events, durable identifiers, profile updates or offline queue.
class AnalyticsService {
  AnalyticsService({
    Dio? transport,
    DateTime Function()? now,
    String Function()? uuid,
  }) : _transport =
           transport ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 5),
               sendTimeout: const Duration(seconds: 5),
               receiveTimeout: const Duration(seconds: 5),
               followRedirects: false,
             ),
           ),
       _now = now ?? DateTime.now,
       _uuid = uuid ?? newRequestId;

  static final AnalyticsService instance = AnalyticsService();
  final Dio _transport;
  final DateTime Function() _now;
  final String Function() _uuid;
  final Set<CancelToken> _pending = {};
  String _projectKey = '';
  bool _configured = false;
  String? _userId;
  String? _sessionId;
  String? _lastRoute;
  DateTime? _validUntil;
  bool Function()? _consentAllowed;
  Timer? _expiry;

  static const _events = {
    'unlock:biometric-used',
    'unlock:vault-unlocked',
    'unlock:unlock-failed',
    'onboarding:recovery-key-confirmed',
    'recovery:recovery-started',
    'recovery:recovery-failed',
    'vault:create-sheet-opened',
    'entry:detail-tab-switched',
    'push:notification-tapped',
    'search:search-result-selected',
    'dashboard:onboarding-notifications-enabled',
    'dashboard:onboarding-notifications-skipped',
    'dashboard:onboarding-skipped',
    'dashboard:onboarding-entry-clicked',
    'dashboard:onboarding-api-key-clicked',
    'dashboard:onboarding-agent-clicked',
    'auth:verification-email-resent',
  };

  /// Kept as the entry-point configuration hook; this performs no I/O.
  Future<void> init(EnvConfig config) async {
    configure(
      projectKey: config.posthogKey,
      host: config.posthogHost,
      released: config.clientAnalyticsReleased,
    );
  }

  void configure({
    required String projectKey,
    required String host,
    required bool released,
  }) {
    reset();
    _projectKey = projectKey;
    _configured =
        released && projectKey.isNotEmpty && host == 'https://eu.i.posthog.com';
  }

  bool get isInitialized => _allowed;
  bool get _allowed {
    if (!_configured ||
        _userId == null ||
        _validUntil == null ||
        !_now().isBefore(_validUntil!) ||
        !(_consentAllowed?.call() ?? false)) {
      reset();
      return false;
    }
    return true;
  }

  void authorize(
    String userId,
    DateTime validUntil,
    bool Function() consentAllowed,
  ) {
    if (_userId != userId) reset();
    _userId = userId;
    _validUntil = validUntil;
    _consentAllowed = consentAllowed;
    if (!_allowed) return;
    _expiry?.cancel();
    _expiry = Timer(validUntil.difference(_now()), reset);
  }

  Future<void> capture(
    String module,
    String event, {
    Map<String, Object>? properties,
  }) async {
    if (!_events.contains('$module:$event')) return;
    // Caller properties are deliberately omitted, including decrypted values.
    await _send('mb:$module:$event', const {});
  }

  Future<void> pageview(String routeTemplate) async {
    if (!_allowed || _lastRoute == routeTemplate) return;
    _lastRoute = routeTemplate;
    await _send('\$pageview', {'route': routeTemplate, 'component': 'mobile'});
  }

  Future<void> _send(String event, Map<String, Object> properties) async {
    if (!_allowed || _pending.length >= 5) return;
    _sessionId ??= _uuid();
    final userId = _userId;
    final sessionId = _sessionId;
    final cancellation = CancelToken();
    _pending.add(cancellation);
    try {
      await Future<void>.value();
      if (cancellation.isCancelled || !_allowed || userId != _userId) return;
      await _transport.post<void>(
        'https://eu.i.posthog.com/i/v0/e/',
        cancelToken: cancellation,
        options: Options(
          contentType: Headers.jsonContentType,
          followRedirects: false,
        ),
        data: {
          'api_key': _projectKey,
          'event': event,
          'distinct_id': userId,
          'timestamp': _now().toUtc().toIso8601String(),
          'properties': {
            ...properties,
            '\$session_id': sessionId,
            '\$process_person_profile': false,
            '\$geoip_disable': true,
          },
        },
      );
    } catch (_) {
      // Best effort: no retry, durable queue, error capture or payload logging.
    } finally {
      _pending.remove(cancellation);
    }
  }

  Future<String?> getSessionId() async => _allowed ? _sessionId : null;

  Future<void> reset() async {
    _expiry?.cancel();
    _userId = null;
    _sessionId = null;
    _lastRoute = null;
    _validUntil = null;
    _consentAllowed = null;
    for (final pending in _pending) {
      pending.cancel();
    }
    _pending.clear();
  }
}
