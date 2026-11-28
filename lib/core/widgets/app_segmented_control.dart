import '../theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

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
    this.edgeToEdge = false,
    this.trailing,
  });
  final T value;
  final List<AppSegment<T>> options;
  final ValueChanged<T> onChanged;
  final bool edgeToEdge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      height: edgeToEdge ? 50 : AppSpacing.controlHeight,
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(edgeToEdge ? 0 : 10),
      ),
      child: Container(
        padding: edgeToEdge
            ? const EdgeInsets.all(AppSpacing.chipGap)
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(edgeToEdge ? 0 : 10),
          border: edgeToEdge
              ? Border(
                  bottom: BorderSide(color: AppColors.cardBorder(brightness)),
                )
              : Border.all(color: AppColors.cardBorder(brightness)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in options) ...[
              _SegmentButton(
                label: option.label,
                badge: option.badge,
                icon: option.icon,
                selected: value == option.value,
                onTap: () => onChanged(option.value),
              ),
              if (edgeToEdge && (option != options.last || trailing != null))
                const SizedBox(width: AppSpacing.chipGap),
            ],
            ?trailing,
          ],
        ),
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
        ? AppColors.onSurface(brightness)
        : AppColors.onSurfaceMuted(brightness);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: icon == null ? null : label,
        child: Tooltip(
          message: icon == null ? '' : label,
          excludeFromSemantics: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: selected
                  ? Border.all(color: AppColors.onSurface(brightness))
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: onTap,
                overlayColor: AppTheme.tabOverlay(Theme.of(context).brightness),
                borderRadius: BorderRadius.circular(6),
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
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (badge != null && badge! > 0) ...[
                        const SizedBox(width: AppSpacing.chipGap),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brandRed,
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
