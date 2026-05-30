import 'package:flutter/material.dart';

import '../../../../core/widgets/icon_picker_grid.dart'
    show IconPickerGrid, IconPresetTile, ImagePresetTile;
import 'vault_visuals.dart';

/// Icon picker for vault entries.
///
/// Tracks the last uploaded custom URL internally so the [ImagePresetTile]
/// stays visible at the last slot even after the user switches to a preset —
/// mirroring the browser sheet behaviour.
class EntryIconPicker extends StatefulWidget {
  const EntryIconPicker({
    super.key,
    required this.selected,
    required this.accentColor,
    required this.onSelected,
    this.moreTile,
  });

  final String selected;
  final Color accentColor;
  final ValueChanged<String> onSelected;
  final Widget? moreTile;

  @override
  State<EntryIconPicker> createState() => _EntryIconPickerState();
}

class _EntryIconPickerState extends State<EntryIconPicker> {
  String? _savedCustomUrl;

  @override
  void initState() {
    super.initState();
    if (EntryVisuals.isCustomUrl(widget.selected)) {
      _savedCustomUrl = widget.selected;
    }
  }

  @override
  void didUpdateWidget(EntryIconPicker old) {
    super.didUpdateWidget(old);
    if (EntryVisuals.isCustomUrl(widget.selected)) {
      _savedCustomUrl = widget.selected;
    }
  }

  bool get _isCustomUrl => EntryVisuals.isCustomUrl(widget.selected);

  @override
  Widget build(BuildContext context) {
    final choices = EntryVisuals.iconChoices;
    final customUrl = _savedCustomUrl;
    return IconPickerGrid(
      itemCount: choices.length,
      itemBuilder: (i, isLast) {
        if (customUrl != null && isLast) {
          return ImagePresetTile(
            imageUrl: customUrl,
            selectedColor: widget.accentColor,
            isSelected: _isCustomUrl,
            onTap: () => widget.onSelected(customUrl),
          );
        }
        return IconPresetTile(
          icon: choices[i].icon,
          paletteColor: choices[i].paletteColor,
          isSelected: !_isCustomUrl && choices[i].name == widget.selected,
          selectedColor: widget.accentColor,
          onTap: () => widget.onSelected(choices[i].name),
        );
      },
      moreTile: widget.moreTile,
    );
  }
}
