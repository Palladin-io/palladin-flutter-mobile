import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'vault_visuals.dart';

/// The 40×40 entry icon shown inline beside the Label field (mockup
/// parity). Tapping it opens the icon + color browser. Renders a custom
/// uploaded image (file:// while pending, https:// once uploaded) or a
/// tinted preset glyph.
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

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 40,
        height: 40,
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
    if (icon.startsWith('file://')) {
      return Image.file(
        File(icon.substring(7)),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _glyph(),
      );
    }
    if (icon.startsWith('http://') || icon.startsWith('https://')) {
      return Image.network(
        icon,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _glyph(),
      );
    }
    return _glyph();
  }

  Widget _glyph() =>
      Icon(EntryVisuals.iconFor(icon), size: 18, color: accentColor);
}
