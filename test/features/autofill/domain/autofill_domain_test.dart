import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_domain.dart';

void main() {
  test('normalizes URL hosts and rejects ambiguous identifiers', () {
    expect(
      normalizeAutoFillDomain('https://WWW.Example.com/login'),
      'www.example.com',
    );
    expect(normalizeAutoFillDomain('sub.example.com.'), 'sub.example.com');
    expect(normalizeAutoFillDomain('localhost'), isNull);
    expect(normalizeAutoFillDomain('not a host'), isNull);
    expect(normalizeAutoFillDomain('https://user@example.com'), isNull);
    expect(normalizeAutoFillDomain('https://example.com:443'), isNull);
    expect(normalizeAutoFillDomain('https://exаmple.com'), isNull);
    expect(normalizeAutoFillDomain('*.example.com'), isNull);
  });
}
