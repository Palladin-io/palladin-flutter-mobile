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
    this.pollInterval = const Duration(seconds: 2),
    this.maxPollAttempts = 30,
  }) : _service = service;

  final WebsiteIconService? _service;
  final void Function(String reference) onReference;
  final void Function(String reference) onResolved;
  final Duration debounce;
  final Duration pollInterval;
  final int maxPollAttempts;
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

    // Persist a stable, environment-independent reference immediately. The
    // catalog lookup below is only needed to render the preview.
    onReference('website:$hostname');
    if (_service == null) return;
    final generation = ++_generation;
    _timer?.cancel();
    _timer = Timer(debounce, () async {
      for (var attempt = 0; attempt <= maxPollAttempts; attempt++) {
        final asset = await _service.resolveOne(hostname);
        if (_manualSelection || generation != _generation) return;
        if (asset != null) {
          onResolved(asset.reference);
          return;
        }
        if (attempt < maxPollAttempts) await Future<void>.delayed(pollInterval);
      }
    });
  }

  void dispose() {
    _generation++;
    _timer?.cancel();
  }
}
