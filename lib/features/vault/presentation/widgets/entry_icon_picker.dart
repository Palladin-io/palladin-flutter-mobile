import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'vault_visuals.dart';

/// Horizontally-scrollable icon picker for vault entries.
///
/// Shows 10 entry-specific preset icons (each with its own palette color)
/// plus an optional upload circle. The selected icon is highlighted using
/// [accentColor] (driven by the color picker), while unselected icons
/// show their own per-icon palette color — matching the web panel's
/// `EntryIconPicker` behavior.
class EntryIconPicker extends StatelessWidget {
  const EntryIconPicker({
    super.key,
    required this.selected,
    required this.accentColor,
    required this.onSelected,
    this.onPickCustom,
  });

  final String selected;

  /// Accent used for the selected icon's ring and fill — typically
  /// `VaultVisuals.colorFor(_color)` from the color picker.
  final Color accentColor;

  final ValueChanged<String> onSelected;

  /// When non-null an upload-circle is prepended. Caller handles pick
  /// logic and updates [selected] with the resulting URL.
  final VoidCallback? onPickCustom;

  bool get _isCustomUrl => EntryVisuals.isCustomUrl(selected);

  @override
  Widget build(BuildContext context) {
    final choices = EntryVisuals.iconChoices;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (onPickCustom != null) ...[
            _EntryUploadCircle(
              accentColor: accentColor,
              imageUrl: _isCustomUrl ? selected : null,
              onTap: onPickCustom!,
            ),
            const SizedBox(width: 8),
          ],
          for (int i = 0; i < choices.length; i++) ...[
            _EntryIconCircle(
              icon: choices[i].icon,
              paletteColor: choices[i].paletteColor,
              isSelected: !_isCustomUrl && choices[i].name == selected,
              accentColor: accentColor,
              onTap: () => onSelected(choices[i].name),
            ),
            if (i < choices.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _EntryIconCircle extends StatelessWidget {
  const _EntryIconCircle({
    required this.icon,
    required this.paletteColor,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final Color paletteColor;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bgOpacity = isSelected
        ? (brightness == Brightness.dark ? 0.15 : 0.12)
        : (brightness == Brightness.dark ? 0.10 : 0.08);
    final bgColor = isSelected
        ? accentColor.withValues(alpha: bgOpacity)
        : paletteColor.withValues(alpha: bgOpacity);
    final iconColor = isSelected ? accentColor : paletteColor;

    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: isSelected
                ? Border.all(color: accentColor, width: 2)
                : null,
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}

class _EntryUploadCircle extends StatelessWidget {
  const _EntryUploadCircle({
    required this.accentColor,
    required this.onTap,
    this.imageUrl,
  });

  final Color accentColor;
  final VoidCallback onTap;
  final String? imageUrl;

  bool get _hasImage => imageUrl != null;

  Widget _buildPreview() {
    if (imageUrl == null) return const SizedBox.shrink();
    if (imageUrl!.startsWith('file://')) {
      return Image.file(
        File(imageUrl!.substring(7)),
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (ctx, e, s) =>
            Icon(Icons.file_upload_outlined, size: 16, color: accentColor),
      );
    }
    return Image.network(
      imageUrl!,
      width: 36,
      height: 36,
      fit: BoxFit.cover,
      errorBuilder: (ctx, e, _) =>
          Icon(Icons.file_upload_outlined, size: 16, color: accentColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final borderColor = _hasImage
        ? accentColor
        : AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.35);
    return Semantics(
      button: true,
      label: l10n.vaultIconUpload,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: borderColor,
              width: _hasImage ? 2 : 1.5,
              style: _hasImage ? BorderStyle.solid : BorderStyle.solid,
            ),
          ),
          child: _hasImage
              ? ClipOval(child: _buildPreview())
              : Icon(
                  Icons.file_upload_outlined,
                  size: 16,
                  color: AppColors.onSurfaceSubtle(brightness),
                ),
        ),
      ),
    );
  }
}
