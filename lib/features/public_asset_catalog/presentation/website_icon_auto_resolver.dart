import 'dart:async';

import '../domain/services/website_icon_service.dart';

/// Debounced, stale-safe URL resolver for entry forms.
class WebsiteIconAutoResolver {
  WebsiteIconAutoResolver({
    WebsiteIconService? service,
    required this.onResolved,
    this.debounce = const Duration(milliseconds: 500),
  }) : _service = service;

  final WebsiteIconService? _service;
  final void Function(String reference) onResolved;
  final Duration debounce;
  Timer? _timer;
  int _generation = 0;
  bool _manualSelection = false;

  void markManualSelection() {
    _manualSelection = true;
    _generation++;
    _timer?.cancel();
  }

  void resolve(String input) {
    if (_manualSelection || _service == null) return;
    final generation = ++_generation;
    _timer?.cancel();
    _timer = Timer(debounce, () async {
      final asset = await _service.resolveOne(input);
      if (!_manualSelection && generation == _generation && asset != null) {
        onResolved(asset.reference);
      }
    });
  }

  void dispose() {
    _generation++;
    _timer?.cancel();
  }
}
