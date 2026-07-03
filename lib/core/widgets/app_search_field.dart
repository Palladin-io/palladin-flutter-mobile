import 'package:flutter/material.dart';

import '../../features/onboarding/presentation/widgets/onboarding_text_field.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared search input used across mobile lists (vaults, entries,
/// agents, audit, …).
///
/// Thin wrapper around [OnboardingTextField] so every text input in the
/// app — form fields and search bars alike — shares the same border,
/// fill, focus styling, and animated decoration code path. Pass
/// [onToggleFilter] to surface the trailing `tune` toggle for filter
/// chips; omit it for screens that don't have filters yet.
///
/// This widget is purely presentational — controllers, query state and
/// filter logic are owned by the caller.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.focusNode,
    this.filterActive = false,
    this.onToggleFilter,
  });

  /// Text editing controller backing the field. Owned by the caller
  /// (and disposed by them).
  final TextEditingController controller;

  /// Optional focus node — pass when the caller needs to observe or drive
  /// focus (e.g. to reveal focus-driven suggestions). Owned and disposed
  /// by the caller.
  final FocusNode? focusNode;

  /// Placeholder shown when the field is empty.
  final String hint;

  /// Optional change callback — caller typically calls `setState` here
  /// to re-filter its list.
  final ValueChanged<String>? onChanged;

  /// `true` when the filter panel is currently visible. Tints the
  /// `tune` icon with [AppColors.brandRed] so users can see the toggle
  /// is active.
  final bool filterActive;

  /// Tap handler for the trailing `tune` icon. When `null`, the icon is
  /// not rendered — use this for screens without filters.
  final VoidCallback? onToggleFilter;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return OnboardingTextField(
      controller: controller,
      focusNode: focusNode,
      hintText: hint,
      onChanged: onChanged,
      // Use the brightness-aware default fill from OnboardingTextField
      // and the design's input-border tone so the search bar matches
      // every other input on the screen.
      borderColor: AppColors.inputBorder(brightness),
      prefixIcon: const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.fieldGap),
        child: Icon(
          Icons.search,
          size: 18,
          color: AppColors.textTertiaryMobile,
        ),
      ),
      suffixIcon: onToggleFilter != null
          ? GestureDetector(
              onTap: onToggleFilter,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.fieldGap),
                child: Icon(
                  Icons.tune,
                  size: 18,
                  color: filterActive
                      ? AppColors.brandRed
                      : AppColors.textTertiaryMobile,
                ),
              ),
            )
          : null,
    );
  }
}
