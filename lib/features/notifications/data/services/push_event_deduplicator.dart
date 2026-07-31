import '../../domain/entities/push_message.dart';

/// Bounded, session-only duplicate filter shared by foreground and tap paths.
final class PushEventDeduplicator {
  PushEventDeduplicator({this.capacity = 256}) {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
  }

  final int capacity;
  final Set<String> _seen = <String>{};
  final List<String> _order = <String>[];

  /// Returns `true` once for one structural backend event in this session.
  bool accept(PushMessage message) {
    final key = message.deduplicationKey;
    if (!_seen.add(key)) return false;
    _order.add(key);
    if (_order.length > capacity) {
      _seen.remove(_order.removeAt(0));
    }
    return true;
  }

  void clear() {
    _seen.clear();
    _order.clear();
  }
}
