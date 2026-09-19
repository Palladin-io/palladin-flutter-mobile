import 'dart:async';

import '../entities/public_asset.dart';
import '../repositories/public_asset_repository.dart';
import 'public_hostname.dart';

class WebsiteIconPreparationCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

class _WebsiteIconPreparationCancelled implements Exception {
  const _WebsiteIconPreparationCancelled();
}

/// Coordinates privacy-bounded website icon lookup without affecting the
/// calling create/import operation when the optional catalog is unavailable.
class WebsiteIconService {
  const WebsiteIconService(
    this._repository, {
    this.pollInterval = const Duration(seconds: 1),
  });
  final PublicAssetRepository _repository;
  final Duration pollInterval;

  Future<PublicAsset?> ensureOne(String? urlOrHostname) async {
    final hostname = PublicHostname.normalize(urlOrHostname);
    if (hostname == null) return null;
    try {
      return (await _repository.ensureWebsiteIcons([
        hostname,
      ])).assets[hostname];
    } catch (_) {
      return null;
    }
  }

  /// Waits only as part of an explicit save action. A URL is returned only
  /// after the catalog reports the immutable asset as ready.
  Future<PublicAsset?> ensureOneWithin(
    String? urlOrHostname, {
    Duration timeout = const Duration(milliseconds: 1500),
    WebsiteIconPreparationCancellation? cancellation,
  }) async {
    final hostname = PublicHostname.normalize(urlOrHostname);
    if (hostname == null) return null;
    return (await ensureBatchWithin(
      [hostname],
      timeout: timeout,
      cancellation: cancellation,
    ))[hostname];
  }

  /// Performs one best-effort catalog request and returns ready assets only.
  Future<Map<String, PublicAsset>> ensureBatch(
    Iterable<String?> domains,
  ) async {
    final unique = PublicHostname.unique(domains, limit: 10000);
    if (unique.isEmpty) return const {};
    try {
      return (await _repository.ensureWebsiteIcons(unique)).assets;
    } catch (_) {
      return const {};
    }
  }

  /// Polls only during an explicit save/import window. Pending or failed
  /// assets are omitted, so callers never encrypt a URL for a missing object.
  Future<Map<String, PublicAsset>> ensureBatchWithin(
    Iterable<String?> domains, {
    required Duration timeout,
    void Function(int ready, int total)? onProgress,
    WebsiteIconPreparationCancellation? cancellation,
  }) => _ensureBatchUntilTerminal(
    domains,
    timeout: timeout,
    onProgress: onProgress,
    cancellation: cancellation,
  );

  /// Polls without an elapsed-time deadline until every hostname reaches a
  /// ready/failed terminal state. Session-authority cancellation still applies.
  Future<Map<String, PublicAsset>> ensureBatchUntilResolved(
    Iterable<String?> domains, {
    void Function(int ready, int total)? onProgress,
    WebsiteIconPreparationCancellation? cancellation,
  }) => _ensureBatchUntilTerminal(
    domains,
    onProgress: onProgress,
    cancellation: cancellation,
  );

  Future<Map<String, PublicAsset>> _ensureBatchUntilTerminal(
    Iterable<String?> domains, {
    Duration? timeout,
    void Function(int ready, int total)? onProgress,
    WebsiteIconPreparationCancellation? cancellation,
  }) async {
    final unique = PublicHostname.unique(domains, limit: 10000);
    final ready = <String, PublicAsset>{};
    final failed = <String>{};
    void report() =>
        onProgress?.call(ready.length + failed.length, unique.length);
    report();
    if (unique.isEmpty ||
        (timeout != null && timeout.inMicroseconds <= 0) ||
        cancellation?.isCancelled == true) {
      return ready;
    }

    final stopwatch = Stopwatch()..start();
    while (timeout == null || stopwatch.elapsed < timeout) {
      if (cancellation?.isCancelled == true) break;
      final unresolved = unique
          .where(
            (hostname) =>
                !ready.containsKey(hostname) && !failed.contains(hostname),
          )
          .toList(growable: false);
      if (unresolved.isEmpty) break;
      final remaining = timeout == null ? null : timeout - stopwatch.elapsed;
      if (remaining != null && remaining.inMicroseconds <= 0) break;
      try {
        final request = remaining == null
            ? _repository.ensureWebsiteIcons(unresolved)
            : _repository.ensureWebsiteIcons(unresolved).timeout(remaining);
        final result = cancellation == null
            ? await request
            : await Future.any<WebsiteIconEnsureResult>([
                request,
                cancellation.whenCancelled.then<WebsiteIconEnsureResult>(
                  (_) => throw const _WebsiteIconPreparationCancelled(),
                ),
              ]);
        ready.addEntries(
          result.assets.entries.where((entry) => unique.contains(entry.key)),
        );
        // Only an explicit Pending outcome warrants another request. An
        // unknown/omitted result or an unusable Ready icon is unavailable for
        // this optional preparation, without discarding other ready icons.
        failed.addAll(
          unresolved.where(
            (hostname) =>
                !ready.containsKey(hostname) &&
                result.statuses[hostname] != WebsiteIconEnsureStatus.pending,
          ),
        );
      } on _WebsiteIconPreparationCancelled {
        break;
      } catch (_) {
        // An explicit transport or parsing failure means the optional catalog
        // is unavailable. Fail fast instead of stalling save/import until the
        // full polling deadline; only a successful Pending response retries.
        break;
      }
      report();
      if (ready.length + failed.length == unique.length) break;
      final wait = timeout == null ? pollInterval : timeout - stopwatch.elapsed;
      if (timeout != null && wait.inMicroseconds <= 0) break;
      final delay = Future<void>.delayed(
        wait < pollInterval ? wait : pollInterval,
      );
      if (cancellation == null) {
        await delay;
      } else {
        await Future.any<void>([delay, cancellation.whenCancelled]);
      }
    }
    report();
    return ready;
  }

  Future<List<PublicAsset>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    return _repository.searchWebsiteIcons(query);
  }
}
