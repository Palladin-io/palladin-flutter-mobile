import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../public_asset_catalog/presentation/widgets/public_asset_image.dart';
import 'vault_visuals.dart';

/// The entry icon shown inline beside the Label field (mockup parity),
/// sized to the input height ([AppSpacing.controlHeight]) so it lines up
/// with the label field next to it. Tapping it opens the icon + color
/// browser. Renders a custom uploaded image (file:// while pending,
/// https:// once uploaded) or a tinted preset glyph.
class EntryIconTile extends StatelessWidget {
  const EntryIconTile({
    super.key,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  /// Icon name (preset) or a `file://` / `https://` URL (custom).
  final String icon;
  final Color accentColor;
  final VoidCallback onTap;

  static const double _size = AppSpacing.controlHeight;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: EntryVisuals.isCustomUrl(icon)
              ? null
              : accentColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.inputBorder(brightness)),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: _content(brightness),
      ),
    );
  }

  Widget _content(Brightness brightness) {
    if (icon.startsWith('public-asset:')) {
      return PublicAssetImage(
        reference: icon,
        width: _size,
        height: _size,
        fallback: _glyph(),
      );
    }
    if (icon.startsWith('file://')) {
      return Image.file(
        File(icon.substring(7)),
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _glyph(),
      );
    }
    return _glyph();
  }

  Widget _glyph() =>
      Icon(EntryVisuals.iconFor(icon), size: 18, color: accentColor);
}
