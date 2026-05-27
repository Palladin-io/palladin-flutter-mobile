import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/icon_picker_grid.dart'
    show IconPickerGrid, IconPresetTile;
import '../../../../l10n/generated/app_localizations.dart';
import 'vault_visuals.dart';

/// Horizontally-scrollable icon picker for vault entries.
///
/// Shows an upload circle (always visible) followed by 10 entry-specific
/// preset icons (each with its own palette color). The selected icon is
/// highlighted using [accentColor] (driven by the color picker), while
/// unselected icons show their own per-icon palette color — matching the
/// web panel's `EntryIconPicker` behavior.
///
/// When [isLoadingCustom] is true a small [CircularProgressIndicator]
/// is shown inside the upload circle instead of hiding it or replacing it
/// with a separate progress bar — the user's icon preview remains
/// visible with the spinner overlaid.
class EntryIconPicker extends StatelessWidget {
  const EntryIconPicker({
    super.key,
    required this.selected,
    required this.accentColor,
    required this.onSelected,
    this.onPickCustom,
    this.isLoadingCustom = false,
    this.moreTile,
  });

  final String selected;

  /// Accent used for the selected icon's ring and fill — typically
  /// `VaultVisuals.colorFor(_color)` from the color picker.
  final Color accentColor;

  final ValueChanged<String> onSelected;

  /// Callback to open the photo picker. Null while the picker is open or
  /// while an S3 upload is in progress — disables the tap but keeps the
  /// circle visible.
  final VoidCallback? onPickCustom;

  /// When true the upload circle renders a small spinner instead of the
  /// upload glyph / image preview, indicating background work.
  final bool isLoadingCustom;

  /// Optional trailing tile that opens the full icon + color browser.
  /// Mirrors the agents approve sheet's "more" affordance.
  final Widget? moreTile;

  bool get _isCustomUrl => EntryVisuals.isCustomUrl(selected);

  @override
  Widget build(BuildContext context) {
    final choices = EntryVisuals.iconChoices;
    return IconPickerGrid(
      itemCount: choices.length,
      itemBuilder: (i) => IconPresetTile(
        icon: choices[i].icon,
        paletteColor: choices[i].paletteColor,
        isSelected: !_isCustomUrl && choices[i].name == selected,
        selectedColor: accentColor,
        onTap: () => onSelected(choices[i].name),
      ),
      leadingTile: _EntryUploadCircle(
        accentColor: accentColor,
        imageUrl: _isCustomUrl ? selected : null,
        onTap: onPickCustom,
        isLoading: isLoadingCustom,
      ),
      moreTile: moreTile,
    );
  }
}

class _EntryUploadCircle extends StatelessWidget {
  const _EntryUploadCircle({
    required this.accentColor,
    required this.onTap,
    this.imageUrl,
    this.isLoading = false,
  });

  final Color accentColor;

  /// Null while picker/upload is in progress — tap is suppressed.
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
    return Icon(
      Icons.file_upload_outlined,
      size: 16,
      color: fallbackColor,
    );
  }

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
    final brightness = Theme.of(context).brightness;
    final fallbackColor = AppColors.onSurfaceSubtle(brightness);
    final borderColor =
        (_hasImage || isLoading) ? accentColor : fallbackColor.withValues(alpha: 0.35);
    final borderWidth = (_hasImage || isLoading) ? 2.0 : 1.5;

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
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: _buildContent(fallbackColor),
        ),
      ),
    );
  }
}
