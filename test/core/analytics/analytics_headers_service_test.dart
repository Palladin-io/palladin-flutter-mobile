import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/analytics/analytics_headers_service.dart';

void main() {
  test('API receives no device or client analytics metadata', () async {
    expect(await AnalyticsHeadersService.instance.getHeaders(), {
      'x-platform': 'mobile',
    });
  });
}
