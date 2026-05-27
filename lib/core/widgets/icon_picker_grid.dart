import 'package:flutter/material.dart';

/// Responsive two-row icon grid.
///
/// Measures its available width via [LayoutBuilder], then derives the
/// number of columns so that tiles of [tileSize] fit with [gap] spacing.
/// Always renders exactly two rows. The last slot is reserved for
/// [moreTile] when one is provided; remaining slots show preset items via
/// [itemBuilder].
///
/// Usage — agents (with browser):
/// ```dart
/// IconPickerGrid(
///   itemCount: agentIconOptions.length,
///   itemBuilder: (i) => _IconTile(iconKey: agentIconOptions[i], …),
///   moreTile: _MoreIconTile(onTap: _openBrowser),
/// )
/// ```
///
/// Usage — vault/entry (no browser, upload in slot 0):
/// ```dart
/// IconPickerGrid(
///   itemCount: choices.length,
///   itemBuilder: (i) => _IconTile(choice: choices[i], …),
///   leadingTile: _UploadCircle(…),
/// )
/// ```
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
  final Widget Function(int index) itemBuilder;

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

        // Count fixed boundary tiles.
        final leadingCount = leadingTile != null ? 1 : 0;
        final moreCount = moreTile != null ? 1 : 0;

        // Preset items that fit in the remaining slots.
        final presetSlots = totalSlots - leadingCount - moreCount;
        final visiblePresets = itemCount.clamp(0, presetSlots);

        final totalItems = leadingCount + visiblePresets + moreCount;

        return GridView.builder(
          shrinkWrap: true,
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
            if (presetIndex < visiblePresets) return itemBuilder(presetIndex);
            return moreTile!;
          },
        );
      },
    );
  }
}
