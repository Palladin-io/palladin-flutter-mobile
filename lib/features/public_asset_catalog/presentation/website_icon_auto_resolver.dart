import 'dart:async';

import '../domain/services/website_icon_service.dart';
import '../domain/services/public_hostname.dart';

/// Debounced, stale-safe URL resolver for entry forms.
class WebsiteIconAutoResolver {
  WebsiteIconAutoResolver({
    WebsiteIconService? service,
    required this.onReference,
    required this.onResolved,
    this.debounce = const Duration(milliseconds: 500),
  }) : _service = service;

  final WebsiteIconService? _service;
  final void Function(String reference) onReference;
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
    if (_manualSelection) return;
    final hostname = PublicHostname.normalize(input);
    if (hostname == null) return;

    if (_service == null) return;
    final generation = ++_generation;
    _timer?.cancel();
    _timer = Timer(debounce, () async {
      final asset = await _service.ensureOne(hostname);
      if (_manualSelection || generation != _generation) return;
      if (asset != null) {
        onReference(asset.reference);
        onResolved(asset.reference);
      }
    });
  }

  void dispose() {
    _generation++;
    _timer?.cancel();
  }
}
