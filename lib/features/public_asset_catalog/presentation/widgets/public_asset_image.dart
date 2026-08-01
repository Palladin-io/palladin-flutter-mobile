import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../config/env_config.dart';
import '../../domain/public_asset_reference.dart';
import '../../domain/repositories/public_asset_repository.dart';

/// Resolves a catalog reference and renders only the server-provided URL.
///
/// A reserved website-icon URL can briefly precede the immutable object. The
/// widget therefore retries only the allowlisted bucket/CDN image GET four
/// times with bounded backoff and a cache-busting query. It never polls an API
/// readiness or resolve endpoint.
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
  static const _retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  late Future<Uri?> _deliveryUrl;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _retryScheduled = false;
  bool _retryExhausted = false;

  @override
  void initState() {
    super.initState();
    _deliveryUrl = _load();
  }

  @override
  void didUpdateWidget(PublicAssetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) {
      _retryTimer?.cancel();
      _retryAttempt = 0;
      _retryScheduled = false;
      _retryExhausted = false;
      _deliveryUrl = _load();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
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

  Uri _retryUrl(Uri deliveryUrl) => _retryAttempt == 0
      ? deliveryUrl
      : deliveryUrl.replace(
          queryParameters: {
            ...deliveryUrl.queryParameters,
            'palladin_icon_retry': '$_retryAttempt',
          },
        );

  void _retryAfterImageError() {
    if (_retryScheduled || _retryExhausted) return;
    if (_retryAttempt >= _retryDelays.length) {
      _retryExhausted = true;
      return;
    }
    _retryScheduled = true;
    _retryTimer = Timer(_retryDelays[_retryAttempt], () {
      if (!mounted) return;
      setState(() {
        _retryAttempt += 1;
        _retryScheduled = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uri?>(
    future: _deliveryUrl,
    builder: (context, snapshot) {
      final deliveryUrl = snapshot.data;
      if (deliveryUrl == null) return widget.fallback;
      return Image.network(
        _retryUrl(deliveryUrl).toString(),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) {
          _retryAfterImageError();
          return widget.fallback;
        },
      );
    },
  );
}
