import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'vault_visuals.dart';

/// Horizontal row of 24 px color circles used in the create / edit
/// vault forms. Selected swatch gets a 2 px primary-text ring; the
/// rest are flat fills.
class VaultColorPicker extends StatelessWidget {
  const VaultColorPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// Currently-selected color hex (e.g. `#FF4F4F`).
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = VaultVisuals.colorChoices;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final hex in colors)
          _ColorCircle(
            color: VaultVisuals.colorFor(hex),
            isSelected: hex == selected,
            onTap: () => onSelected(hex),
          ),
      ],
    );
  }
}

class _ColorCircle extends StatelessWidget {
  const _ColorCircle({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // Wrap the swatch in a 32 px hit area so neighbouring chips
        // stay reachable on small phones without enlarging the dot.
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(color: AppColors.textPrimary, width: 2)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
