import '../entities/public_asset.dart';
import '../repositories/public_asset_repository.dart';
import 'public_hostname.dart';

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
      return (await _repository.ensureWebsiteIcons([hostname]))[hostname];
    } catch (_) {
      return null;
    }
  }

  /// Waits only as part of an explicit save action. A URL is returned only
  /// after the catalog reports the immutable asset as ready.
  Future<PublicAsset?> ensureOneWithin(
    String? urlOrHostname, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final hostname = PublicHostname.normalize(urlOrHostname);
    if (hostname == null) return null;
    return (await ensureBatchWithin([hostname], timeout: timeout))[hostname];
  }

  /// Performs one best-effort catalog request and returns ready assets only.
  Future<Map<String, PublicAsset>> ensureBatch(
    Iterable<String?> domains,
  ) async {
    final unique = PublicHostname.unique(domains, limit: 10000);
    if (unique.isEmpty) return const {};
    try {
      return await _repository.ensureWebsiteIcons(unique);
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
  }) async {
    final unique = PublicHostname.unique(domains, limit: 10000);
    final ready = <String, PublicAsset>{};
    void report() => onProgress?.call(ready.length, unique.length);
    report();
    if (unique.isEmpty || timeout.inMicroseconds <= 0) return ready;

    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      final unresolved = unique
          .where((hostname) => !ready.containsKey(hostname))
          .toList(growable: false);
      if (unresolved.isEmpty) break;
      final remaining = timeout - stopwatch.elapsed;
      if (remaining.inMicroseconds <= 0) break;
      try {
        ready.addAll(
          await _repository.ensureWebsiteIcons(unresolved).timeout(remaining),
        );
      } catch (_) {
        // Optional enrichment never blocks the credential save/import.
      }
      report();
      if (ready.length == unique.length) break;
      final wait = timeout - stopwatch.elapsed;
      if (wait.inMicroseconds <= 0) break;
      await Future<void>.delayed(wait < pollInterval ? wait : pollInterval);
    }
    report();
    return ready;
  }

  Future<List<PublicAsset>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    return _repository.searchWebsiteIcons(query);
  }
}
