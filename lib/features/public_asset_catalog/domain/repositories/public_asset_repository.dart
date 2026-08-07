import '../entities/public_asset.dart';

enum WebsiteIconEnsureStatus { pending, ready, failed }

class WebsiteIconEnsureResult {
  const WebsiteIconEnsureResult({required this.assets, required this.statuses});

  final Map<String, PublicAsset> assets;
  final Map<String, WebsiteIconEnsureStatus> statuses;
}

/// Public Asset Catalog read operations used by mobile.
abstract interface class PublicAssetRepository {
  Future<List<PublicAsset>> searchWebsiteIcons(String query);

  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  );

  Future<PublicAsset?> getById(String assetId, {int? revision});
}
