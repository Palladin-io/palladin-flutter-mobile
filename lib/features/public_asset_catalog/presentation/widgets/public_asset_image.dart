import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../config/env_config.dart';
import '../../domain/public_asset_reference.dart';
import '../../domain/repositories/public_asset_repository.dart';

final _assetIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Loads a published revision from the configured API, never the embedded URL.
class PublicAssetImage extends StatefulWidget {
  const PublicAssetImage({
    super.key,
    required this.reference,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });
  final String reference;
  final Widget fallback;
  final double? width;
  final double? height;
  final BoxFit fit;
  @override
  State<PublicAssetImage> createState() => _PublicAssetImageState();
}

class _PublicAssetImageState extends State<PublicAssetImage> {
  late Future<Uri?> _deliveryUrl;

  @override
  void initState() {
    super.initState();
    _deliveryUrl = _load();
  }

  @override
  void didUpdateWidget(PublicAssetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) {
      _deliveryUrl = _load();
    }
  }

  Future<Uri?> _load() async {
    final reference = PublicAssetReference.parse(widget.reference);
    if (reference is! CatalogAssetReference ||
        !_assetIdPattern.hasMatch(reference.assetId)) {
      return null;
    }
    var revision = reference.revision;
    if (revision == null) {
      final asset = await getIt<PublicAssetRepository>().getById(
        reference.assetId,
      );
      revision = asset?.revision;
    }
    if (revision == null) return null;
    return publicAssetContentUrl(
      getIt<EnvConfig>().apiBaseUrl,
      reference.assetId,
      revision,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uri?>(
    future: _deliveryUrl,
    builder: (context, snapshot) {
      final deliveryUrl = snapshot.data;
      if (deliveryUrl == null) return widget.fallback;
      return Image.network(
        deliveryUrl.toString(),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => widget.fallback,
      );
    },
  );
}

Uri? publicAssetContentUrl(String apiBaseUrl, String assetId, int revision) {
  // References are decrypted input; do not allow them to alter the API route.
  if (!_assetIdPattern.hasMatch(assetId) || revision < 1) {
    return null;
  }
  final base = Uri.parse(apiBaseUrl);
  return base.replace(
    pathSegments: [
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
      'api',
      'public-assets',
      assetId,
      'revisions',
      '$revision',
      'content',
    ],
  );
}
