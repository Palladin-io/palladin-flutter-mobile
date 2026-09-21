import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'primary_button_glow.dart';

class AppSegment<T> {
  const AppSegment({
    required this.value,
    required this.label,
    this.badge,
    this.icon,
  });
  final T value;
  final String label;
  final int? badge;
  final IconData? icon;
}

/// Canonical 44px under-title segment track, shared by Inbox and the library.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final T value;
  final List<AppSegment<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      height: AppSpacing.controlHeight,
      // Fixed track inset, matching the original Inbox control.
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options)
            _SegmentButton(
              label: option.label,
              badge: option.badge,
              icon: option.icon,
              selected: value == option.value,
              onTap: () => onChanged(option.value),
            ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fg = selected
        ? AppColors.onBrandRed
        : AppColors.onSurfaceMuted(brightness);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: icon == null ? null : label,
        child: Tooltip(
          message: icon == null ? '' : label,
          excludeFromSemantics: true,
          child: PrimaryButtonGlow(
            enabled: selected,
            radius: 8,
            child: Material(
              color: selected ? AppColors.brandRed : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                // Cell is stretched to the track height — center the label so the
                // selected pill fills the full height with the text centred.
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null)
                        Icon(icon, size: 20, color: fg)
                      else
                        Text(
                          label,
                          style: TextStyle(
                            color: fg,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (badge != null) ...[
                        const SizedBox(width: AppSpacing.chipGap),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.onBrandRed.withValues(alpha: 0.25)
                                : AppColors.brandRed,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$badge',
                            style: const TextStyle(
                              color: AppColors.onBrandRed,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
