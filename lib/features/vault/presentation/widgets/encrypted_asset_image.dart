import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/services/encrypted_presentation_asset_service.dart';

/// Renders a locally decrypted presentation asset without a persistent cache.
class EncryptedAssetImage extends StatefulWidget {
  const EncryptedAssetImage({
    super.key,
    required this.reference,
    required this.target,
    required this.vaultId,
    required this.fallback,
    this.entryId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String reference;
  final PresentationAssetTarget target;
  final String vaultId;
  final String? entryId;
  final Widget fallback;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  State<EncryptedAssetImage> createState() => _EncryptedAssetImageState();
}

class _EncryptedAssetImageState extends State<EncryptedAssetImage> {
  final EncryptedPresentationAssetService _assets =
      getIt<EncryptedPresentationAssetService>();
  PresentationAssetValue? _value;
  Object? _requestToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant EncryptedAssetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference ||
        oldWidget.vaultId != widget.vaultId ||
        oldWidget.entryId != widget.entryId ||
        oldWidget.target != widget.target) {
      _clear();
      _load();
    }
  }

  Future<void> _load() async {
    final auth = context.read<AuthBloc>().state;
    final privateKey = auth is AuthAuthenticated && !auth.isVaultLocked
        ? auth.privateKey
        : null;
    if (privateKey == null || !widget.reference.startsWith('asset:')) return;
    final token = Object();
    _requestToken = token;
    final keyCopy = Uint8List.fromList(privateKey);
    try {
      final value = await _assets.load(
        reference: widget.reference,
        target: widget.target,
        vaultId: widget.vaultId,
        entryId: widget.entryId,
        memberPrivateKey: keyCopy,
      );
      if (!mounted || _requestToken != token) {
        _assets.release(value);
        return;
      }
      _clear();
      setState(() => _value = value);
    } catch (_) {
      // Corruption, scope and network failures deliberately share one fallback.
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
  }

  void _clear() {
    _requestToken = null;
    final value = _value;
    _value = null;
    if (value != null) _assets.release(value);
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<AuthBloc, AuthState>(
    listenWhen: (previous, current) =>
        current is! AuthAuthenticated || current.isVaultLocked,
    listener: (context, state) {
      _clear();
      if (mounted) setState(() {});
    },
    child: _value == null
        ? widget.fallback
        : Image.memory(
            _value!.bytes,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: false,
            errorBuilder: (context, error, stackTrace) => widget.fallback,
          ),
  );
}
