import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/config/env_config.dart';
import 'package:mobile_claw_vault/core/analytics/analytics_service.dart';

void main() {
  group('AnalyticsService', () {
    test('is not initialized by default', () {
      expect(AnalyticsService.instance.isInitialized, isFalse);
    });

    test('capture does not throw when not initialized', () async {
      await AnalyticsService.instance.capture('vault', 'page-viewed');
    });

    test('getSessionId returns null when not initialized', () async {
      final sessionId = await AnalyticsService.instance.getSessionId();
      expect(sessionId, isNull);
    });

    test('identify does not throw when not initialized', () async {
      await AnalyticsService.instance.identify('user-123');
    });

    test('reset does not throw when not initialized', () async {
      await AnalyticsService.instance.reset();
    });

    test('init skips setup when posthogKey is empty', () async {
      final config = EnvConfig.staging();
      await AnalyticsService.instance.init(config);
      expect(AnalyticsService.instance.isInitialized, isFalse);
    });
  });
}
