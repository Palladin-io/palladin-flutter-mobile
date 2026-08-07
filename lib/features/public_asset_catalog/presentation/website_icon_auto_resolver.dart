import 'dart:async';

import '../domain/entities/public_asset.dart';
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
    this.previewTimeout = const Duration(seconds: 5),
  }) : _service = service;

  final WebsiteIconService? _service;
  final void Function(String reference) onReference;
  final void Function(String reference) onResolved;
  final void Function()? onAutomaticCleared;
  final Duration debounce;
  final Duration previewTimeout;
  Timer? _timer;
  WebsiteIconPreparationCancellation? _activePreparation;
  int _generation = 0;
  bool _manualSelection = false;
  String? _resolvedHostname;

  void markManualSelection() {
    _manualSelection = true;
    _resolvedHostname = null;
    _generation++;
    _timer?.cancel();
    _cancelActivePreparation();
  }

  void resolve(String input) {
    if (_manualSelection) return;
    final hostname = PublicHostname.normalize(input);
    final generation = ++_generation;
    _timer?.cancel();
    _cancelActivePreparation();
    _clearAutomaticIconForChangedHostname(hostname);
    if (hostname == null || _service == null) return;
    _timer = Timer(debounce, () => _ensure(hostname, generation));
  }

  /// Cancels the debounce and waits briefly for a ready asset needed by save.
  /// A manual icon selection always wins and stale requests remain ignored.
  Future<String?> ensureNow(String input) async {
    if (_manualSelection) return null;
    final hostname = PublicHostname.normalize(input);
    _timer?.cancel();
    _cancelActivePreparation();
    final generation = ++_generation;
    _clearAutomaticIconForChangedHostname(hostname);
    if (hostname == null || _service == null) return null;
    return _ensure(hostname, generation, waitForReady: true);
  }

  Future<String?> _ensure(
    String hostname,
    int generation, {
    bool waitForReady = false,
  }) async {
    if (generation != _generation) return null;
    final cancellation = WebsiteIconPreparationCancellation();
    _activePreparation = cancellation;
    // A newly reserved catalog asset starts as Pending. The live form preview
    // gets a short bounded window to observe Ready instead of stopping after
    // the first response and leaving the default type glyph indefinitely.
    final PublicAsset? asset;
    try {
      asset = await _service!.ensureOneWithin(
        hostname,
        timeout: waitForReady
            ? const Duration(milliseconds: 1500)
            : previewTimeout,
        cancellation: cancellation,
      );
    } finally {
      if (identical(_activePreparation, cancellation)) {
        _activePreparation = null;
      }
    }
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

  void _cancelActivePreparation() {
    _activePreparation?.cancel();
    _activePreparation = null;
  }

  void dispose() {
    _generation++;
    _timer?.cancel();
    _cancelActivePreparation();
  }
}
