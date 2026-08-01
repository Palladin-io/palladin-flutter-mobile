import 'dart:async';

import '../domain/services/website_icon_service.dart';
import '../domain/services/public_hostname.dart';

/// Debounced, stale-safe URL resolver for entry forms.
class WebsiteIconAutoResolver {
  WebsiteIconAutoResolver({
    WebsiteIconService? service,
    required this.onReference,
    required this.onResolved,
    this.onAutomaticCleared,
    this.debounce = const Duration(milliseconds: 500),
  }) : _service = service;

  final WebsiteIconService? _service;
  final void Function(String reference) onReference;
  final void Function(String reference) onResolved;
  final void Function()? onAutomaticCleared;
  final Duration debounce;
  Timer? _timer;
  int _generation = 0;
  bool _manualSelection = false;
  String? _resolvedHostname;

  void markManualSelection() {
    _manualSelection = true;
    _resolvedHostname = null;
    _generation++;
    _timer?.cancel();
  }

  void resolve(String input) {
    if (_manualSelection) return;
    final hostname = PublicHostname.normalize(input);
    final generation = ++_generation;
    _timer?.cancel();
    _clearAutomaticIconForChangedHostname(hostname);
    if (hostname == null || _service == null) return;
    _timer = Timer(debounce, () => _ensure(hostname, generation));
  }

  /// Cancels the debounce and completes the reservation needed by a save.
  /// A manual icon selection always wins and stale requests remain ignored.
  Future<String?> ensureNow(String input) async {
    if (_manualSelection) return null;
    final hostname = PublicHostname.normalize(input);
    _timer?.cancel();
    final generation = ++_generation;
    _clearAutomaticIconForChangedHostname(hostname);
    if (hostname == null || _service == null) return null;
    return _ensure(hostname, generation);
  }

  Future<String?> _ensure(String hostname, int generation) async {
    final asset = await _service!.ensureOne(hostname);
    if (_manualSelection || generation != _generation || asset == null) {
      return null;
    }
    _resolvedHostname = hostname;
    onReference(asset.reference);
    onResolved(asset.reference);
    return asset.reference;
  }

  void _clearAutomaticIconForChangedHostname(String? hostname) {
    final previous = _resolvedHostname;
    if (previous == null || previous == hostname) return;
    _resolvedHostname = null;
    onAutomaticCleared?.call();
  }

  void dispose() {
    _generation++;
    _timer?.cancel();
  }
}
