import '../domain/entities/public_asset.dart';
import '../domain/repositories/public_asset_repository.dart';
import '../domain/services/public_hostname.dart';
import 'public_asset_remote_datasource.dart';

/// Validating repository implementation. Malformed catalog rows fail closed.
class PublicAssetRepositoryImpl implements PublicAssetRepository {
  PublicAssetRepositoryImpl(this._remote);
  final PublicAssetRemoteDatasource _remote;
  final Map<String, PublicAsset> _assets = {};
  final Set<String> _acquisitionRequested = {};

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    return _parseAll(await _remote.search(normalized));
  }

  @override
  Future<Map<String, PublicAsset>> resolveWebsiteIcons(
    Iterable<String> hostnames,
  ) async {
    final normalized = PublicHostname.unique(hostnames, limit: 10000);
    if (normalized.isEmpty) return const {};
    final result = <String, PublicAsset>{};
    for (var offset = 0; offset < normalized.length; offset += 500) {
      final end = (offset + 500).clamp(0, normalized.length);
      final page = normalized.sublist(offset, end);
      final acquireMissing = page.any(
        (hostname) => !_acquisitionRequested.contains(hostname),
      );
      final rows = await _remote.resolve(page, acquireMissing: acquireMissing);
      _acquisitionRequested.addAll(page);
      for (final row in rows) {
        final hostname = PublicHostname.normalize(row['hostname'] as String?);
        final assetValue = row['asset'];
        final asset = _parse(
          assetValue is Map ? Map<String, dynamic>.from(assetValue) : row,
        );
        if (hostname != null && asset != null) result[hostname] = asset;
      }
    }
    return result;
  }

  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async {
    if (assetId.isEmpty) return null;
    final cached = _assets[assetId];
    if (cached != null && (revision == null || cached.revision == revision)) {
      return cached;
    }
    final row = await _remote.getById(assetId, revision: revision);
    return row == null ? null : _parse(row);
  }

  List<PublicAsset> _parseAll(List<Map<String, dynamic>> rows) =>
      rows.map(_parse).whereType<PublicAsset>().toList(growable: false);

  PublicAsset? _parse(Map<String, dynamic> row) {
    final id = row['id'] as String? ?? row['assetId'] as String?;
    final type = row['type'] as String?;
    final name = row['name'] as String? ?? row['displayName'] as String?;
    final revision = row['revision'];
    final urlValue = row['deliveryUrl'] as String? ?? row['url'] as String?;
    final url = Uri.tryParse(urlValue ?? '');
    if (id == null ||
        id.isEmpty ||
        (type != 'websiteIcon' && type != 'agentIcon') ||
        name == null ||
        name.isEmpty ||
        revision is! num ||
        url == null ||
        (url.scheme != 'https' && url.scheme != 'http')) {
      return null;
    }
    final canonicalType = type!;
    final asset = PublicAsset(
      id: id,
      type: canonicalType,
      name: name,
      revision: revision.toInt(),
      deliveryUrl: url,
    );
    _assets[id] = asset;
    return asset;
  }
}
