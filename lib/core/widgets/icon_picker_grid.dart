import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Responsive two-row icon grid.
///
/// Measures its available width via [LayoutBuilder], then derives the
/// number of columns so that tiles of [tileSize] fit with [gap] spacing.
/// Always renders exactly two rows. The last slot is reserved for
/// [moreTile] when one is provided; remaining slots show preset items via
/// [itemBuilder].
class IconPickerGrid extends StatelessWidget {
  const IconPickerGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.leadingTile,
    this.moreTile,
    this.tileSize = 40.0,
    this.gap = 10.0,
  });

  /// Number of preset icon items.
  final int itemCount;

  /// Builds a preset tile for the given index (0-based).
  /// [isLast] is true when this is the last visible preset slot — use it
  /// to inject the custom image tile without needing to know [visiblePresets].
  final Widget Function(int index, bool isLast) itemBuilder;

  /// Optional first tile (e.g. upload circle). Occupies slot 0.
  final Widget? leadingTile;

  /// Optional last tile (e.g. "..." browser button). Occupies the final
  /// slot of the second row. When null, the grid ends after all items
  /// (or after two rows, whichever comes first).
  final Widget? moreTile;

  final double tileSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final cols =
            ((available + gap) / (tileSize + gap)).floor().clamp(3, 12);
        final totalSlots = cols * 2;

        final leadingCount = leadingTile != null ? 1 : 0;
        final moreCount = moreTile != null ? 1 : 0;

        final presetSlots = totalSlots - leadingCount - moreCount;
        final visiblePresets = itemCount.clamp(0, presetSlots);

        final totalItems = leadingCount + visiblePresets + moreCount;

        return GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            childAspectRatio: 1,
          ),
          itemCount: totalItems,
          itemBuilder: (_, index) {
            if (leadingTile != null && index == 0) return leadingTile!;
            final presetIndex = index - leadingCount;
            if (presetIndex < visiblePresets) {
              return itemBuilder(presetIndex, presetIndex == visiblePresets - 1);
            }
            return moreTile!;
          },
        );
      },
    );
  }
}

/// 40×40 square icon tile — shared across agent, vault and entry pickers.
///
/// Unselected: tinted with [paletteColor] (each icon has its own accent).
/// Selected: tinted with [selectedColor] (user-chosen or accent color).
class IconPresetTile extends StatelessWidget {
  const IconPresetTile({
    super.key,
    required this.icon,
    required this.paletteColor,
    required this.isSelected,
    required this.selectedColor,
    required this.onTap,
  });

  final IconData icon;
  final Color paletteColor;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = isSelected
        ? selectedColor.withValues(alpha: 0.25)
        : paletteColor.withValues(alpha: 0.12);
    final iconColor = isSelected ? selectedColor : paletteColor;
    final borderColor = isSelected ? selectedColor : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }
}

/// Tile showing a custom uploaded image (file:// or https://) in the
/// preset icon grid. Replaces the last preset slot when a custom URL is
/// active so the "more" tile always stays at the end.
///
/// [size] controls the tile dimensions — defaults to 40 (compact picker),
/// pass 48 for the full browser grid. Border radius scales with size
/// (size × 0.25) so the corners stay proportional.
class ImagePresetTile extends StatelessWidget {
  const ImagePresetTile({
    super.key,
    required this.imageUrl,
    required this.selectedColor,
    required this.onTap,
    this.isSelected = true,
    this.size = 40.0,
  });

  final String imageUrl;
  final Color selectedColor;
  final VoidCallback onTap;
  final bool isSelected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected ? selectedColor : Colors.transparent;
    final radius = size * 0.25;
    Widget img;
    if (imageUrl.startsWith('file://')) {
      img = Image.file(
        File(imageUrl.substring(7)),
        width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, e, s) =>
            Icon(Icons.image, size: size * 0.5, color: selectedColor),
      );
    } else {
      img = Image.network(
        imageUrl,
        width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, e, s) =>
            Icon(Icons.image, size: size * 0.5, color: selectedColor),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - 1.5),
            child: img,
          ),
        ),
      ),
    );
  }
}

/// Trailing "more" tile — muted slate square that opens the full icon
/// browser. Shared across any picker that needs a browser affordance.
class IconMoreTile extends StatelessWidget {
  const IconMoreTile({super.key, required this.onTap, this.semanticLabel});

  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.brandRed, width: 1.5),
            ),
            child: const Center(
              child: Icon(
                Icons.more_horiz,
                size: 20,
                color: AppColors.brandRed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
