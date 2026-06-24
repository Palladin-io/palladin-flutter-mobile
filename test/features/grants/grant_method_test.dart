import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant_method.dart';

void main() {
  group('parseGrantMethods', () {
    test('parses a combined-flags string', () {
      expect(parseGrantMethods('get, exec'), [GrantMethod.get, GrantMethod.exec]);
    });

    test('is case- and whitespace-insensitive and canonically ordered', () {
      expect(parseGrantMethods('Inject,  GET'), [GrantMethod.get, GrantMethod.inject]);
    });

    test('skips unknown tokens', () {
      expect(parseGrantMethods('get, frobnicate'), [GrantMethod.get]);
    });

    test('de-duplicates', () {
      expect(parseGrantMethods('exec, exec'), [GrantMethod.exec]);
    });

    test('returns [] for null/empty', () {
      expect(parseGrantMethods(null), isEmpty);
      expect(parseGrantMethods(''), isEmpty);
      expect(parseGrantMethods('   '), isEmpty);
    });
  });

  group('serializeGrantMethods', () {
    test('serializes to PascalCase combined flags in canonical order', () {
      expect(serializeGrantMethods([GrantMethod.exec, GrantMethod.get]), 'Get, Exec');
      expect(serializeGrantMethods([GrantMethod.inject]), 'Inject');
      expect(
        serializeGrantMethods([GrantMethod.get, GrantMethod.exec, GrantMethod.inject]),
        'Get, Exec, Inject',
      );
    });

    test('round-trips with parseGrantMethods', () {
      const methods = [GrantMethod.exec, GrantMethod.inject];
      expect(
        parseGrantMethods(serializeGrantMethods(methods).toLowerCase()),
        methods,
      );
    });
  });
}
