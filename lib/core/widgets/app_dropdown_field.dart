import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared labelled dropdown — the select counterpart of [OnboardingTextField].
///
/// Owns the 44px bordered box, `isDense` styling and 13px text in ONE place so
/// every select (entry type, agent type, grant subject…) is exactly as tall as
/// the app's text inputs. Without this each `DropdownButton` rendered at the
/// Material default (~56px) and looked oversized next to the form fields.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.enabled = true,
    this.filled = true,
  });

  /// Optional caption rendered above the box (11px muted, like the inputs).
  final String? label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  /// Shown inside the closed box when [value] is null.
  final Widget? hint;

  /// When false the dropdown is non-interactive.
  final bool enabled;

  /// Fills the box with [AppColors.inputFill] (form fields). Pass false for a
  /// transparent box on already-tinted surfaces (e.g. modal sheets).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceMuted(brightness),
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
        ],
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.fieldGap),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? AppColors.inputFill(brightness) : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.inputBorder(brightness)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              isDense: true,
              hint: hint,
              icon: Icon(
                Icons.expand_more,
                size: 18,
                color: AppColors.onSurfaceSubtle(brightness),
              ),
              dropdownColor: AppColors.modalBackground(brightness),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.inputText(brightness),
                fontSize: 13,
              ),
              items: items,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }
}
