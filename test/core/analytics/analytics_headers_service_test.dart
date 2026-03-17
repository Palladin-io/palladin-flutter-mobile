import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/core/analytics/analytics_headers_service.dart';

void main() {
  group('AnalyticsHeadersService', () {
    test('getHeaders includes x-user-agent without init', () async {
      final headers = await AnalyticsHeadersService.instance.getHeaders();

      expect(headers, contains('x-user-agent'));
      expect(
        headers['x-user-agent'],
        contains('ClawVault/mobile'),
      );
      expect(
        headers['x-user-agent'],
        contains(Platform.operatingSystem),
      );
    });

    test('getHeaders omits x-app-version when PackageInfo not loaded',
        () async {
      final headers = await AnalyticsHeadersService.instance.getHeaders();

      // PackageInfo.fromPlatform() has not been called in this test,
      // so version headers should be absent.
      expect(headers, isNot(contains('x-app-version')));
      expect(headers, isNot(contains('x-app-build-number')));
    });

    test('getHeaders omits x-session-id when analytics not initialized',
        () async {
      final headers = await AnalyticsHeadersService.instance.getHeaders();
      expect(headers, isNot(contains('x-session-id')));
    });
  });
}
