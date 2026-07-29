/// The supported icon-reference namespaces.
sealed class PublicAssetReference {
  const PublicAssetReference();

  factory PublicAssetReference.parse(String? value) {
    final reference = value?.trim() ?? '';
    if (reference.startsWith('public-asset:') && reference.length > 13) {
      return CatalogAssetReference(reference.substring(13));
    }
    if (reference.startsWith('builtin:') && reference.length > 8) {
      return BuiltinAssetReference(reference.substring(8));
    }
    if (reference.startsWith('vault-asset:') && reference.length > 12) {
      return VaultAssetReference(reference.substring(12));
    }
    // Compatibility with the pre-catalog encrypted presentation namespace.
    if (reference.startsWith('asset:') && reference.length > 6) {
      return VaultAssetReference(reference.substring(6));
    }
    if (reference.startsWith('https://') || reference.startsWith('http://')) {
      return LegacyUrlAssetReference(reference);
    }
    return BuiltinAssetReference(reference.isEmpty ? 'vpn_key' : reference);
  }
}

final class CatalogAssetReference extends PublicAssetReference {
  const CatalogAssetReference(this.assetId);
  final String assetId;
}

final class BuiltinAssetReference extends PublicAssetReference {
  const BuiltinAssetReference(this.glyph);
  final String glyph;
}

final class VaultAssetReference extends PublicAssetReference {
  const VaultAssetReference(this.assetReference);
  final String assetReference;

  String get legacyReference => 'asset:$assetReference';
}

final class LegacyUrlAssetReference extends PublicAssetReference {
  const LegacyUrlAssetReference(this.url);
  final String url;
}
