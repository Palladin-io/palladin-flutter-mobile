import '../entities/public_asset.dart';

/// Public Asset Catalog read operations used by mobile.
abstract interface class PublicAssetRepository {
  Future<List<PublicAsset>> searchWebsiteIcons(String query);

  Future<Map<String, PublicAsset>> resolveWebsiteIcons(
    Iterable<String> hostnames,
  );

  Future<PublicAsset?> getById(String assetId, {int? revision});
}
