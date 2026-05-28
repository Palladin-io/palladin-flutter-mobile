import 'package:flutter/material.dart';

import '../../../../core/widgets/icon_picker_grid.dart'
    show IconPickerGrid, IconPresetTile;
import 'vault_visuals.dart';

/// Horizontally-scrollable icon picker for vault entries.
///
/// Shows the entry-specific preset icons (each with its own palette color).
/// The selected icon is highlighted using [accentColor]. The upload affordance
/// is rendered separately below this widget by the caller.
class EntryIconPicker extends StatelessWidget {
  const EntryIconPicker({
    super.key,
    required this.selected,
    required this.accentColor,
    required this.onSelected,
    this.moreTile,
  });

  final String selected;

  /// Accent used for the selected icon's ring and fill.
  final Color accentColor;

  final ValueChanged<String> onSelected;

  /// Optional trailing tile that opens the full icon + color browser.
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
      moreTile: moreTile,
    );
  }
}
