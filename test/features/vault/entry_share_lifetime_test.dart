import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_lifetime.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share.dart';

void main() {
  final initial = DateTime.utc(2026, 9, 21);
  late DateTime now;
  late Duration elapsed;
  EntryShareLifetime lifetime({
    DateTime? receivedAt,
    Duration age = Duration.zero,
  }) => EntryShareLifetime(
    receivedAt: receivedAt,
    age: age,
    now: () => now,
    elapsed: () => elapsed,
  );
  setUp(() {
    now = initial;
    elapsed = Duration.zero;
  });

  test('native residence and Dart residence share the same finite ceiling', () {
    final deadline = lifetime(
      receivedAt: initial.subtract(const Duration(minutes: 4)),
      age: const Duration(minutes: 4),
    );
    expect(deadline.remaining, const Duration(minutes: 11));
    now = now.add(const Duration(minutes: 3));
    elapsed += const Duration(minutes: 3);
    expect(deadline.remaining, const Duration(minutes: 8));
  });
  test(
    'native monotonic age prevents clock rollback from extending lifetime',
    () {
      final deadline = lifetime(
        receivedAt: initial.add(const Duration(hours: 1)),
        age: const Duration(minutes: 14),
      );
      expect(deadline.remaining, const Duration(minutes: 1));
      now = initial.subtract(const Duration(hours: 2));
      elapsed += const Duration(minutes: 1);
      expect(deadline.isLive, false);
    },
  );
  test('wall expiry rejects a capability even before monotonic expiry', () {
    final deadline = lifetime(
      receivedAt: initial.subtract(const Duration(minutes: 16)),
    );
    expect(deadline.isLive, false);
  });
  test('a future native timestamp cannot grant more than fifteen minutes', () {
    final deadline = lifetime(receivedAt: initial.add(const Duration(days: 2)));
    expect(deadline.remaining, EntryShareLifetime.maximum);
  });
  test(
    'shortening is irreversible across later expiries and clock rollback',
    () {
      final deadline = lifetime();
      deadline.shortenTo(initial.add(const Duration(minutes: 2)));
      expect(deadline.remaining, const Duration(minutes: 2));
      deadline.shortenTo(initial.add(const Duration(hours: 1)));
      now = initial.subtract(const Duration(days: 1));
      expect(deadline.remaining, const Duration(minutes: 2));
      elapsed += const Duration(minutes: 2);
      expect(deadline.isLive, false);
    },
  );
  test('expired lifetime never revives when either clock rolls back', () {
    final deadline = lifetime();
    elapsed = const Duration(minutes: 15);
    expect(deadline.isLive, false);
    elapsed = Duration.zero;
    now = initial.subtract(const Duration(days: 1));
    expect(deadline.isLive, false);
  });
  test('native age at or over the ceiling is expired immediately', () {
    expect(lifetime(age: const Duration(minutes: 15)).isLive, false);
    expect(lifetime(age: const Duration(days: 1)).isLive, false);
  });
  test('negative native age is rejected without diagnostics', () {
    expect(
      () => lifetime(age: const Duration(milliseconds: -1)),
      throwsA(isA<EntryShareException>()),
    );
  });
}
