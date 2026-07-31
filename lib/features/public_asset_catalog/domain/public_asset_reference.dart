/// The supported icon-reference namespaces.
sealed class PublicAssetReference {
  const PublicAssetReference();

  factory PublicAssetReference.parse(String? value) {
    final reference = value?.trim() ?? '';
    if (reference.startsWith('public-asset:') && reference.length > 13) {
      final payload = reference.substring(13).split('|');
      if (payload.length == 3) {
        final revision = int.tryParse(payload[1]);
        Uri? deliveryUrl;
        try {
          deliveryUrl = Uri.tryParse(Uri.decodeComponent(payload[2]));
        } on FormatException {
          deliveryUrl = null;
        }
        if (revision != null && revision > 0 && deliveryUrl != null) {
          return CatalogAssetReference(
            payload[0],
            revision: revision,
            deliveryUrl: deliveryUrl,
          );
        }
      }
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
  const CatalogAssetReference(this.assetId, {this.revision, this.deliveryUrl});
  final String assetId;
  final int? revision;
  final Uri? deliveryUrl;
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
