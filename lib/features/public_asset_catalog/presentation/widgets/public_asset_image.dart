import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../domain/entities/public_asset.dart';
import '../../domain/public_asset_reference.dart';
import '../../domain/repositories/public_asset_repository.dart';

/// Resolves a catalog reference and renders only the server-provided URL.
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
  late Future<PublicAsset?> _asset;
  @override
  void initState() {
    super.initState();
    _asset = _load();
  }

  @override
  void didUpdateWidget(PublicAssetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) _asset = _load();
  }

  Future<PublicAsset?> _load() {
    final reference = PublicAssetReference.parse(widget.reference);
    if (reference is! CatalogAssetReference) return Future.value();
    return getIt<PublicAssetRepository>().getById(reference.assetId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PublicAsset?>(
    future: _asset,
    builder: (context, snapshot) {
      final asset = snapshot.data;
      if (asset == null) return widget.fallback;
      return Image.network(
        asset.deliveryUrl.toString(),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => widget.fallback,
      );
    },
  );
}
