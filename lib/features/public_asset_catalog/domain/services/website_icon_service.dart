import '../entities/public_asset.dart';
import '../repositories/public_asset_repository.dart';
import 'public_hostname.dart';

/// Coordinates privacy-bounded website icon lookup without affecting the
/// calling create/import operation when the optional catalog is unavailable.
class WebsiteIconService {
  const WebsiteIconService(this._repository);
  final PublicAssetRepository _repository;

  Future<PublicAsset?> resolveOne(String? urlOrHostname) async {
    final hostname = PublicHostname.normalize(urlOrHostname);
    if (hostname == null) return null;
    try {
      return (await _repository.resolveWebsiteIcons([hostname]))[hostname];
    } catch (_) {
      return null;
    }
  }

  /// Resolves at most one API batch. Callers may poll this method for assets
  /// that the backend catalog is still acquiring, but must keep that polling
  /// bounded and outside create/import transactions.
  Future<Map<String, PublicAsset>> resolveBatch(
    Iterable<String?> domains,
  ) async {
    final unique = PublicHostname.unique(domains, limit: 10000);
    if (unique.isEmpty) return const {};
    try {
      return await _repository.resolveWebsiteIcons(unique);
    } catch (_) {
      return const {};
    }
  }

  Future<List<PublicAsset>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    return _repository.searchWebsiteIcons(query);
  }
}
