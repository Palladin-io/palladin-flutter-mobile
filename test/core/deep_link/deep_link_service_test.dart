import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/deep_link/deep_link_service.dart';

void main() {
  final service = DeepLinkService();

  test('maps the verify-email deep link to the route with its token', () {
    final route = service.routeForUri(
      Uri.parse('palladin://verify-email?token=abc123'),
    );
    expect(route, '/verify-email?token=abc123');
  });

  test('maps a verify-email link without a token to the bare route', () {
    final route = service.routeForUri(Uri.parse('palladin://verify-email'));
    expect(route, '/verify-email');
  });

  test('ignores a foreign scheme', () {
    final route = service.routeForUri(
      Uri.parse('https://palladin.io/verify-email?token=abc'),
    );
    expect(route, isNull);
  });

  test('ignores an unknown host', () {
    final route =
        service.routeForUri(Uri.parse('palladin://something-else?token=abc'));
    expect(route, isNull);
  });
}
