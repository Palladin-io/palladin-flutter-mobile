import 'package:flutter/material.dart';

import '../../../../core/widgets/icon_picker_grid.dart'
    show IconPickerGrid, IconPresetTile, ImagePresetTile;
import 'vault_visuals.dart';

/// Horizontal row of icon-circles used in vault create / edit forms.
///
/// Tracks the last uploaded custom URL internally so the [ImagePresetTile]
/// stays visible at the last slot even after the user switches to a preset —
/// mirroring the browser sheet behaviour.
class VaultIconPicker extends StatefulWidget {
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
  final Widget? moreTile;

  @override
  State<VaultIconPicker> createState() => _VaultIconPickerState();
}

class _VaultIconPickerState extends State<VaultIconPicker> {
  String? _savedCustomUrl;

  @override
  void initState() {
    super.initState();
    if (VaultVisuals.isCustomUrl(widget.selected)) {
      _savedCustomUrl = widget.selected;
    }
  }

  @override
  void didUpdateWidget(VaultIconPicker old) {
    super.didUpdateWidget(old);
    if (VaultVisuals.isCustomUrl(widget.selected)) {
      _savedCustomUrl = widget.selected;
    }
  }

  bool get _isCustomUrl => VaultVisuals.isCustomUrl(widget.selected);

  @override
  Widget build(BuildContext context) {
    final choices = VaultVisuals.iconChoices;
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
