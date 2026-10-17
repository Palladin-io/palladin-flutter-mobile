import '../../../domain/entities/entry_share.dart';

/// The same deadline follows a capability from ingress through reception.
final class EntryShareLifetime {
  EntryShareLifetime({
    DateTime? receivedAt,
    Duration age = Duration.zero,
    DateTime Function()? now,
    Duration Function()? elapsed,
  }) : _now = now ?? DateTime.now,
       _elapsed = elapsed ?? (Stopwatch()..start()).elapsedGetter {
    if (age.isNegative) {
      throw const EntryShareException(EntryShareErrorKind.invalidLink);
    }
    final current = _now();
    _wallDeadline = (receivedAt ?? current).add(maximum);
    if (_wallDeadline.isAfter(current.add(maximum))) {
      _wallDeadline = current.add(maximum);
    }
    _monotonicDeadline = _elapsed() + maximum - age;
    _remainingCeiling = maximum - age;
  }

  static const maximum = Duration(minutes: 15);
  final DateTime Function() _now;
  final Duration Function() _elapsed;
  late DateTime _wallDeadline;
  late Duration _monotonicDeadline, _remainingCeiling;

  Duration get remaining {
    final wall = _wallDeadline.difference(_now());
    final monotonic = _monotonicDeadline - _elapsed();
    final shortest = wall < monotonic ? wall : monotonic;
    if (shortest < _remainingCeiling) _remainingCeiling = shortest;
    return _remainingCeiling > Duration.zero
        ? _remainingCeiling
        : Duration.zero;
  }

  bool get isLive => remaining > Duration.zero;

  void shortenTo(DateTime expiresAt) {
    final current = _now();
    if (expiresAt.isBefore(_wallDeadline)) _wallDeadline = expiresAt;
    final deadline = _elapsed() + expiresAt.difference(current);
    if (deadline < _monotonicDeadline) _monotonicDeadline = deadline;
    remaining;
  }
}

extension on Stopwatch {
  Duration elapsedGetter() => elapsed;
}
