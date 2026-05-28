import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../../features/agents/presentation/widgets/approve_agent_sheet.dart'
    show ApproveActionButton;
import '../../l10n/generated/app_localizations.dart';

/// Describes a single picker icon — name (stored value), glyph data, and
/// the per-icon palette tint used when the tile is not selected.
typedef IconColorBrowserChoice = ({
  String name,
  IconData icon,
  Color paletteColor,
});

/// Result emitted by [IconColorBrowserSheet] when the user confirms their
/// selection. `iconKey` is `null` when the user opened the browser
/// without picking a glyph — the browser disables Confirm in that case,
/// so callers can safely assume a non-null key when the future resolves.
typedef IconColorBrowserResult = ({String? iconKey, Color color});

/// Reusable icon + color browser bottom sheet — the same shape the
/// [ApproveActionButton] approve-agent sheet uses for its icon browser.
///
/// Renders an 6-column grid of every glyph in [icons], a divider, a
/// "Color" label, the six [colorOptions] swatches and a Cancel / Confirm
/// footer. Confirm is disabled until an icon is selected.
class IconColorBrowserSheet extends StatefulWidget {
  const IconColorBrowserSheet({
    super.key,
    required this.icons,
    required this.colorOptions,
    required this.initialIconKey,
    required this.initialColor,
    required this.title,
    required this.confirmLabel,
    this.leadingTile,
    this.onPickCustom,
  });

  /// Full set of glyphs to render in the browser grid.
  final List<IconColorBrowserChoice> icons;

  /// Six selectable accent colors shown below the icon grid.
  final List<Color> colorOptions;

  /// Currently-selected glyph (matches `IconColorBrowserChoice.name`)
  /// when the sheet opens, or `null` when no icon is yet active.
  final String? initialIconKey;

  /// Currently-selected accent color when the sheet opens.
  final Color initialColor;

  /// Header text — typically the localized icon-browser title.
  final String title;

  /// Label rendered on the green confirm CTA in the footer.
  final String confirmLabel;

  /// Optional first tile (e.g. upload circle). Ignored when [onPickCustom]
  /// is provided — the sheet manages the upload circle internally in that case.
  final Widget? leadingTile;

  /// When provided, an upload circle is shown as the first tile in the
  /// browser grid. Tapping it calls this callback; the returned string
  /// (a `file://` or `https://` URL) becomes the selected icon so callers
  /// can treat custom images the same as preset icon names. Returning
  /// `null` means the user cancelled the picker.
  final Future<String?> Function()? onPickCustom;

  /// Opens the sheet on the root navigator and returns the user's
  /// selection, or `null` on cancel / dismiss.
  static Future<IconColorBrowserResult?> show(
    BuildContext context, {
    required List<IconColorBrowserChoice> icons,
    required List<Color> colorOptions,
    required String? initialIconKey,
    required Color initialColor,
    required String title,
    required String confirmLabel,
    Widget? leadingTile,
    Future<String?> Function()? onPickCustom,
  }) {
    return showModalBottomSheet<IconColorBrowserResult>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IconColorBrowserSheet(
        icons: icons,
        colorOptions: colorOptions,
        initialIconKey: initialIconKey,
        initialColor: initialColor,
        title: title,
        confirmLabel: confirmLabel,
        leadingTile: leadingTile,
        onPickCustom: onPickCustom,
      ),
    );
  }

  @override
  State<IconColorBrowserSheet> createState() => _IconColorBrowserSheetState();
}

bool _isCustomUrl(String? s) =>
    s != null &&
    (s.startsWith('https://') || s.startsWith('http://') || s.startsWith('file://'));

class _IconColorBrowserSheetState extends State<IconColorBrowserSheet> {
  late String? _localIcon = widget.initialIconKey;
  late Color _localColor = widget.initialColor;
  bool _isLoadingCustom = false;

  void _confirm() {
    final icon = _localIcon;
    if (icon == null) return;
    Navigator.of(context).pop<IconColorBrowserResult>((
      iconKey: icon,
      color: _localColor,
    ));
  }

  Future<void> _pickCustom() async {
    if (_isLoadingCustom) return;
    setState(() => _isLoadingCustom = true);
    try {
      final url = await widget.onPickCustom!();
      if (url != null && mounted) setState(() => _localIcon = url);
    } finally {
      if (mounted) setState(() => _isLoadingCustom = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.modalBackground(brightness),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          color: AppColors.onSurface(brightness),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 20,
                          color: AppColors.onSurfaceSubtle(brightness),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _BrowserIconGrid(
                  icons: widget.icons,
                  selectedIcon: _localIcon,
                  selectedColor: _localColor,
                  leadingTile: widget.onPickCustom != null
                      ? _BrowserUploadCircle(
                          accentColor: _localColor,
                          isSelected: _isCustomUrl(_localIcon),
                          isLoading: _isLoadingCustom,
                          imageUrl: _isCustomUrl(_localIcon) ? _localIcon : null,
                          onTap: _isLoadingCustom ? null : _pickCustom,
                        )
                      : widget.leadingTile,
                  onSelected: (icon) => setState(() => _localIcon = icon),
                ),
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.cardBorder(brightness),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.agentIconColorLabel,
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                _ColorPickerRow(
                  colors: widget.colorOptions,
                  selected: _localColor,
                  onSelected: (color) => setState(() => _localColor = color),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.onSurface(brightness),
                            side: BorderSide(
                              color: AppColors.cardBorder(brightness),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            l10n.apiKeysCancel,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ApproveActionButton(
                        label: widget.confirmLabel,
                        icon: Icons.check,
                        onPressed: _localIcon == null ? null : _confirm,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 6-column grid of every icon in [icons]. Selected tile uses the
/// user-picked accent color; unselected tiles use the per-glyph palette
/// tint. Optionally renders [leadingTile] as the first slot.
class _BrowserIconGrid extends StatelessWidget {
  const _BrowserIconGrid({
    required this.icons,
    required this.selectedIcon,
    required this.selectedColor,
    required this.onSelected,
    this.leadingTile,
  });

  final List<IconColorBrowserChoice> icons;
  final String? selectedIcon;
  final Color selectedColor;
  final ValueChanged<String> onSelected;
  final Widget? leadingTile;

  @override
  Widget build(BuildContext context) {
    final leadingCount = leadingTile != null ? 1 : 0;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: icons.length + leadingCount,
      itemBuilder: (_, index) {
        if (leadingTile != null && index == 0) return leadingTile!;
        final choice = icons[index - leadingCount];
        final selected = choice.name == selectedIcon;
        return InkWell(
          onTap: () => onSelected(choice.name),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? selectedColor.withValues(alpha: 0.18)
                  : choice.paletteColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? selectedColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(
              choice.icon,
              size: 20,
              color: selected ? selectedColor : choice.paletteColor,
            ),
          ),
        );
      },
    );
  }
}

/// Row of color swatches — single-select. The active swatch gets a
/// cream / navy ring (brightness-aware) so it reads against any color.
class _ColorPickerRow extends StatelessWidget {
  const _ColorPickerRow({
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final ringColor = AppColors.onSurface(brightness);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final color in colors)
          GestureDetector(
            onTap: () => onSelected(color),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected.toARGB32() == color.toARGB32()
                      ? ringColor
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Upload circle rendered inside the browser grid as the first slot when
/// [IconColorBrowserSheet.onPickCustom] is provided. Circular shape
/// distinguishes it from the preset squared tiles.
class _BrowserUploadCircle extends StatelessWidget {
  const _BrowserUploadCircle({
    required this.accentColor,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
    this.imageUrl,
  });

  final Color accentColor;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback? onTap;
  final String? imageUrl;

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
    if (imageUrl != null) {
      return ClipOval(child: _buildPreview(fallbackColor));
    }
    return Icon(Icons.file_upload_outlined, size: 18, color: fallbackColor);
  }

  Widget _buildPreview(Color fallbackColor) {
    if (imageUrl == null) return const SizedBox.shrink();
    if (imageUrl!.startsWith('file://')) {
      return Image.file(
        File(imageUrl!.substring(7)),
        fit: BoxFit.cover,
        errorBuilder: (_, e, s) =>
            Icon(Icons.file_upload_outlined, size: 18, color: fallbackColor),
      );
    }
    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, e, s) =>
          Icon(Icons.file_upload_outlined, size: 18, color: fallbackColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fallbackColor = AppColors.onSurfaceSubtle(brightness);
    final borderColor =
        isSelected ? accentColor : fallbackColor.withValues(alpha: 0.35);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? accentColor.withValues(alpha: 0.12) : null,
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2.0 : 1.5,
          ),
        ),
        child: _buildContent(fallbackColor),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
