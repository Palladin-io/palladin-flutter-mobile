import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/features/approval/domain/repositories/approval_repository.dart';

/// The approve body must carry **exactly one** of `expiresAt` / `queryLimit`
/// (the backend enforces XOR). `GrantLimit.toWire()` is the single place
/// that mapping lives, so we pin the invariant here.
void main() {
  group('GrantLimit.toWire — XOR invariant', () {
    test('GrantExpiry → only expiresAt (UTC ISO-8601), queryLimit null', () {
      final at = DateTime.utc(2026, 6, 3, 12, 30);
      final wire = GrantExpiry(at).toWire();

      expect(wire.queryLimit, isNull);
      expect(wire.expiresAt, isNotNull);
      // Round-trips back to the same instant.
      expect(DateTime.parse(wire.expiresAt!).toUtc(), at);
    });

    test('GrantExpiry serializes a local DateTime as UTC', () {
      // A non-UTC input must still be emitted in UTC so the server reads
      // the correct absolute instant.
      final local = DateTime(2026, 1, 1, 0, 0);
      final wire = GrantExpiry(local).toWire();
      expect(wire.expiresAt, endsWith('Z'));
      expect(DateTime.parse(wire.expiresAt!).toUtc(), local.toUtc());
    });

    test('GrantUseLimit → only queryLimit, expiresAt null', () {
      final wire = const GrantUseLimit(25).toWire();
      expect(wire.expiresAt, isNull);
      expect(wire.queryLimit, 25);
    });

    test('GrantLifetime → neither field (datasource omits → lifetime)', () {
      final wire = const GrantLifetime().toWire();
      expect(wire.expiresAt, isNull);
      expect(wire.queryLimit, isNull);
    });

    test('at most one field is non-null across all variants', () {
      for (final limit in <GrantLimit>[
        GrantExpiry(DateTime.utc(2026, 6, 3)),
        const GrantUseLimit(1),
        const GrantLifetime(),
      ]) {
        final wire = limit.toWire();
        final nonNull = [wire.expiresAt, wire.queryLimit]
            .where((v) => v != null)
            .length;
        expect(nonNull, lessThanOrEqualTo(1), reason: 'over-specified for $limit');
      }
    });
  });
}
