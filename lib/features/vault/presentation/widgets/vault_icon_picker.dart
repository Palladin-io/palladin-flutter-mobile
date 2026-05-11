import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'vault_visuals.dart';

/// Horizontal row of icon-circles used in vault create / edit forms.
///
/// When [onPickCustom] is provided an extra upload circle is prepended
/// before the presets. If [selected] is a URL the upload circle shows a
/// preview of the custom image (with a selected-state border) instead of
/// the upload glyph, so the user can see which icon is active.
class VaultIconPicker extends StatelessWidget {
  const VaultIconPicker({
    super.key,
    required this.selected,
    required this.accentColor,
    required this.onSelected,
    this.onPickCustom,
  });

  final String selected;
  final Color accentColor;
  final ValueChanged<String> onSelected;

  /// When non-null an upload-circle is shown as the first item.
  /// Caller implements the pick + upload logic and updates [selected]
  /// with the resulting URL on success.
  final VoidCallback? onPickCustom;

  bool get _isCustomUrl => VaultVisuals.isCustomUrl(selected);

  @override
  Widget build(BuildContext context) {
    final choices = VaultVisuals.iconChoices;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (onPickCustom != null)
          _UploadCircle(
            color: primaryColor,
            accentColor: accentColor,
            imageUrl: _isCustomUrl ? selected : null,
            onTap: onPickCustom!,
          ),
        for (int i = 0; i < choices.length; i++)
          _IconCircle(
            icon: choices[i].icon,
            paletteColor: choices[i].paletteColor,
            isSelected: !_isCustomUrl && choices[i].name == selected,
            accentColor: accentColor,
            onTap: () => onSelected(choices[i].name),
          ),
      ],
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({
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
    final iconColor =
        isSelected ? accentColor : AppColors.textTertiaryMobile;

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

/// Circle that triggers a custom icon upload.
///
/// When [imageUrl] is set (a custom icon is already selected) it renders
/// the image as a full-bleed circle with a selected-state border so the
/// user can see the current custom icon. Tapping it always opens the
/// picker so they can replace the image.
class _UploadCircle extends StatelessWidget {
  const _UploadCircle({
    required this.color,
    required this.accentColor,
    required this.onTap,
    this.imageUrl,
  });

  final Color color;
  final Color accentColor;
  final VoidCallback onTap;

  /// URL of the currently-selected custom icon, or null when no custom
  /// icon is active. When non-null the image is displayed instead of the
  /// upload glyph.
  final String? imageUrl;

  bool get _hasImage => imageUrl != null;

  Widget _buildPreview(Color fallbackColor) {
    if (imageUrl == null) return const SizedBox.shrink();
    if (imageUrl!.startsWith('file://')) {
      return Image.file(
        File(imageUrl!.substring(7)),
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (ctx, e, s) =>
            Icon(Icons.file_upload_outlined, size: 16, color: fallbackColor),
      );
    }
    return Image.network(
      imageUrl!,
      width: 36,
      height: 36,
      fit: BoxFit.cover,
      errorBuilder: (ctx, e, _) =>
          Icon(Icons.file_upload_outlined, size: 16, color: fallbackColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
              color: _hasImage ? accentColor : color.withValues(alpha: 0.35),
              width: _hasImage ? 2 : 1.5,
            ),
          ),
          child: _hasImage
              ? ClipOval(child: _buildPreview(color))
              : Icon(
                  Icons.file_upload_outlined,
                  size: 16,
                  color: color,
                ),
        ),
      ),
    );
  }
}
