import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../config/env_config.dart';
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
  late Future<Uri?> _deliveryUrl;
  @override
  void initState() {
    super.initState();
    _deliveryUrl = _load();
  }

  @override
  void didUpdateWidget(PublicAssetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) _deliveryUrl = _load();
  }

  Future<Uri?> _load() async {
    final reference = PublicAssetReference.parse(widget.reference);
    if (reference is! CatalogAssetReference) return null;
    if (reference.deliveryUrl case final direct?) {
      return _trusted(direct) ? direct : null;
    }
    final asset = await getIt<PublicAssetRepository>().getById(
      reference.assetId,
    );
    return asset != null && _trusted(asset.deliveryUrl)
        ? asset.deliveryUrl
        : null;
  }

  bool _trusted(Uri candidate) {
    final base = Uri.parse(getIt<EnvConfig>().publicAssetBaseUrl);
    final prefix = '${base.path.replaceFirst(RegExp(r'/$'), '')}/';
    return candidate.scheme == base.scheme &&
        candidate.host == base.host &&
        candidate.port == base.port &&
        candidate.userInfo.isEmpty &&
        !candidate.hasQuery &&
        !candidate.hasFragment &&
        candidate.path.startsWith(prefix);
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
