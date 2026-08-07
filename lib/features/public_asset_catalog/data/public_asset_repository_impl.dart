import '../domain/entities/public_asset.dart';
import '../domain/repositories/public_asset_repository.dart';
import '../domain/services/public_hostname.dart';
import 'public_asset_remote_datasource.dart';

/// Validating repository implementation. Malformed catalog rows fail closed.
class PublicAssetRepositoryImpl implements PublicAssetRepository {
  PublicAssetRepositoryImpl(this._remote);
  final PublicAssetRemoteDatasource _remote;
  final Map<String, PublicAsset> _assets = {};

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    return _parseAll(await _remote.search(normalized));
  }

  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) async {
    final normalized = PublicHostname.unique(hostnames, limit: 10000);
    if (normalized.isEmpty) {
      return const WebsiteIconEnsureResult(assets: {}, statuses: {});
    }
    final assets = <String, PublicAsset>{};
    final statuses = <String, WebsiteIconEnsureStatus>{};
    for (var offset = 0; offset < normalized.length; offset += 500) {
      final end = (offset + 500).clamp(0, normalized.length);
      final page = normalized.sublist(offset, end);
      final expectedHostnames = page.toSet();
      final returnedHostnames = <String>{};
      final rows = await _remote.ensure(page);
      for (final row in rows) {
        final hostname = PublicHostname.normalize(row['hostname'] as String?);
        final status = switch (row['status']) {
          'pending' => WebsiteIconEnsureStatus.pending,
          'ready' => WebsiteIconEnsureStatus.ready,
          'failed' => WebsiteIconEnsureStatus.failed,
          _ => throw const FormatException(
            'Malformed website icon ensure status',
          ),
        };
        final assetValue = row['asset'];
        final asset = _parse(
          assetValue is Map ? Map<String, dynamic>.from(assetValue) : row,
        );
        if (hostname == null ||
            !expectedHostnames.contains(hostname) ||
            !returnedHostnames.add(hostname) ||
            (status == WebsiteIconEnsureStatus.ready) != (asset != null)) {
          throw const FormatException('Malformed website icon ensure item');
        }
        statuses[hostname] = status;
        if (asset != null) assets[hostname] = asset;
      }
      if (returnedHostnames.length != expectedHostnames.length) {
        throw const FormatException(
          'Website icon ensure response omitted a requested hostname',
        );
      }
    }
    return WebsiteIconEnsureResult(assets: assets, statuses: statuses);
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
