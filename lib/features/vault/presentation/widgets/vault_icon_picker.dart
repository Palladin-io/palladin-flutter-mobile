import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'vault_visuals.dart';

/// Horizontal row of 32 px icon circles used in the create / edit
/// vault forms. Mirrors the Astro prototype 1:1 — selected swatch
/// gets a 2 px brand-red ring; the rest sit on a tinted background.
///
/// The selected icon is paired with the picked [accentColor] so the
/// active circle always shows the same hue as the color picker
/// selection. Inactive circles use a flat slate tint.
class VaultIconPicker extends StatelessWidget {
  const VaultIconPicker({
    super.key,
    required this.selected,
    required this.accentColor,
    required this.onSelected,
  });

  /// Currently-selected icon name (matches `VaultIconChoice.name`).
  final String selected;

  /// Color used to tint the active swatch. Comes from the color
  /// picker's current selection so the two pickers stay in sync.
  final Color accentColor;

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final choices = VaultVisuals.iconChoices;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final choice in choices)
          _IconCircle(
            icon: choice.icon,
            isSelected: choice.name == selected,
            accentColor: accentColor,
            onTap: () => onSelected(choice.name),
          ),
      ],
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({
    required this.icon,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected
        ? accentColor.withValues(alpha: 0.15)
        : AppColors.vaultSlate.withValues(alpha: 0.10);
    final iconColor = isSelected ? accentColor : AppColors.textPrimary;

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
                ? Border.all(color: AppColors.brandRed, width: 2)
                : null,
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}
