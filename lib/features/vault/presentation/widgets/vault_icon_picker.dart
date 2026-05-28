import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/widgets/icon_picker_grid.dart'
    show IconPickerGrid, IconPresetTile;
import '../../../../l10n/generated/app_localizations.dart';
import 'vault_visuals.dart';

/// Horizontal row of icon-circles used in vault create / edit forms.
class VaultIconPicker extends StatelessWidget {
  const VaultIconPicker({
    super.key,
    required this.selected,
    required this.accentColor,
    required this.onSelected,
    this.moreTile,
  });

  final String selected;
  final Color accentColor;
  final ValueChanged<String> onSelected;

  /// Optional trailing tile that opens the full icon + color browser.
  final Widget? moreTile;

  bool get _isCustomUrl => VaultVisuals.isCustomUrl(selected);

  @override
  Widget build(BuildContext context) {
    final choices = VaultVisuals.iconChoices;
    return IconPickerGrid(
      itemCount: choices.length,
      itemBuilder: (i) => IconPresetTile(
        icon: choices[i].icon,
        paletteColor: choices[i].paletteColor,
        isSelected: !_isCustomUrl && choices[i].name == selected,
        selectedColor: accentColor,
        onTap: () => onSelected(choices[i].name),
      ),
      moreTile: moreTile,
    );
  }
}

/// Upload circle shown below the icon picker when a custom icon is active.
/// Tapping it opens the photo picker; the current custom image is shown
/// as a preview with a selected-state border.
class VaultUploadTile extends StatelessWidget {
  const VaultUploadTile({
    super.key,
    required this.accentColor,
    required this.onTap,
    this.imageUrl,
    this.isLoading = false,
  });

  final Color accentColor;
  final VoidCallback? onTap;
  final String? imageUrl;
  final bool isLoading;

  bool get _hasImage => imageUrl != null;

  Widget _buildContent(Color fallbackColor) {
    if (isLoading) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(accentColor),
        ),
      );
    }
    if (_hasImage) return ClipOval(child: _buildPreview(fallbackColor));
    return Icon(Icons.file_upload_outlined, size: 16, color: fallbackColor);
  }

  Widget _buildPreview(Color fallbackColor) {
    if (imageUrl == null) return const SizedBox.shrink();
    if (imageUrl!.startsWith('file://')) {
      return Image.file(
        File(imageUrl!.substring(7)),
        width: 36, height: 36, fit: BoxFit.cover,
        errorBuilder: (_, e, s) =>
            Icon(Icons.file_upload_outlined, size: 16, color: fallbackColor),
      );
    }
    return Image.network(
      imageUrl!,
      width: 36, height: 36, fit: BoxFit.cover,
      errorBuilder: (_, e, s) =>
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
          width: 36, height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: (_hasImage || isLoading)
                  ? accentColor
                  : Colors.grey.withValues(alpha: 0.35),
              width: (_hasImage || isLoading) ? 2.0 : 1.5,
            ),
          ),
          child: _buildContent(Colors.grey),
        ),
      ),
    );
  }
}
