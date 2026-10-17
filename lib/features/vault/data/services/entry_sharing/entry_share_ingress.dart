import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'entry_share_lifetime.dart';
import 'entry_share_link_service.dart';
import 'entry_share_secrets.dart';

typedef EntryShareInbound = ({
  String shareId,
  EntryShareSecrets secrets,
  EntryShareLifetime lifetime,
});

/// Native messages are an independent input boundary, never router state.
final class EntryShareIngress extends ChangeNotifier {
  EntryShareIngress({
    required EntryShareLinkService links,
    MethodChannel channel = const MethodChannel(
      'io.palladin.mobile/entry-sharing',
    ),
    DateTime Function()? now,
    Duration Function()? elapsed,
  }) : _links = links,
       _channel = channel,
       _now = now ?? DateTime.now,
       _elapsed = elapsed ?? (Stopwatch()..start()).elapsedGetter;

  final EntryShareLinkService _links;
  final MethodChannel _channel;
  final DateTime Function() _now;
  final Duration Function() _elapsed;
  EntryShareInbound? _pending;
  Timer? _expiry;
  Future<void>? _pulling;
  bool _started = false, _disposed = false, _pullAgain = false;
  int _announced = 0, _consumed = 0, _version = 0, _discardEpoch = 0;

  int get version => _version;
  bool get hasPending => _pending?.lifetime.isLive == true;

  Future<void> start() {
    if (_disposed || _started) return Future.value();
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (_disposed || call.method != 'pending') return;
      final value = call.arguments;
      if (value is! int || value < 1) {
        clear();
        return;
      }
      if (value <= _announced) return;
      _announced = value;
      _invalidate();
      unawaited(_requestPull());
    });
    return _requestPull();
  }

  Future<void> _requestPull() {
    _pullAgain = true;
    return _pulling ??= _drain().whenComplete(() => _pulling = null);
  }

  Future<void> _drain() async {
    while (!_disposed && _pullAgain) {
      _pullAgain = false;
      final epoch = _discardEpoch;
      final started = _elapsed();
      try {
        final value = await _channel.invokeMethod<Object?>('takePending');
        if (_disposed) return;
        if (epoch != _discardEpoch) continue;
        if (value == null) continue;
        if (value is! Map || value['generation'] is! int) {
          _invalidate();
          continue;
        }
        final generation = value['generation'] as int;
        if (generation < _announced || generation <= _consumed) continue;
        _announced = generation;
        _consumed = generation;
        _invalidate();
        if (_disposed || epoch != _discardEpoch) continue;
        final url = value['url'];
        final receivedAt = value['receivedAtUnixMs'];
        final age = value['ageMilliseconds'];
        if (url is! String ||
            receivedAt is! int ||
            age is! int ||
            age < 0 ||
            age >= EntryShareLifetime.maximum.inMilliseconds) {
          continue;
        }
        final transferTime = _elapsed() - started;
        if (transferTime.isNegative) continue;
        final lifetime = EntryShareLifetime(
          receivedAt: DateTime.fromMillisecondsSinceEpoch(
            receivedAt,
            isUtc: true,
          ),
          age: Duration(milliseconds: age) + transferTime,
          now: _now,
          elapsed: _elapsed,
        );
        if (!lifetime.isLive) continue;
        final parsed = _links.parse(url);
        _pending = (
          shareId: parsed.shareId,
          secrets: parsed.secrets,
          lifetime: lifetime,
        );
        _expiry = Timer(lifetime.remaining, _invalidate);
        notifyListeners();
      } catch (_) {
        if (!_disposed) _invalidate();
      }
    }
  }

  EntryShareInbound? take(int expectedVersion) {
    if (_disposed || expectedVersion != _version) return null;
    final pending = _pending;
    if (pending == null) return null;
    if (!pending.lifetime.isLive) {
      _invalidate();
      return null;
    }
    _expiry?.cancel();
    _expiry = null;
    _pending = null;
    return pending;
  }

  void clear() {
    if (!_disposed) {
      _discardEpoch++;
      _invalidate();
    }
  }

  void _invalidate() {
    _expiry?.cancel();
    _expiry = null;
    _pending?.secrets.dispose();
    _pending = null;
    _version++;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    _expiry?.cancel();
    _pending?.secrets.dispose();
    _pending = null;
    super.dispose();
  }
}

extension on Stopwatch {
  Duration elapsedGetter() => elapsed;
}
