import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Shared styled TextField for onboarding and authentication screens.
///
/// Encapsulates the dark-surface fill, rounded border, and consistent
/// text style. Optionally renders a label above the field and a
/// fixed-height animated error slot below it — so layout never shifts
/// when an error appears or disappears.
///
/// ## Error slot
/// Pass [errorMessage] (even as an empty string) to reserve the 28 px
/// slot below the input. When the string is non-empty the message
/// slides down and fades in; when it is empty the slot stays invisible
/// but keeps its height so nothing in the parent Column moves.
/// Omit [errorMessage] entirely (null) to skip the slot — use this when
/// you handle feedback differently (e.g. a strength-bar below the field).
///
/// ## Border behaviour
/// - [borderColor]      — enabled-state border; null = no border (default)
/// - [focusBorderColor] — focused-state border; null = [AppColors.tealAccent]
class OnboardingTextField extends StatelessWidget {
  const OnboardingTextField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.obscureText = false,
    this.suffixIcon,
    this.autocorrect = false,
    this.enableSuggestions = false,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.onSubmitted,
    this.borderColor,
    this.focusBorderColor,
    this.errorMessage,
  });

  final TextEditingController controller;

  /// Optional label rendered above the input.
  final String? label;

  final String? hintText;
  final bool obscureText;
  final Widget? suffixIcon;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextCapitalization textCapitalization;

  /// Keyboard action button (e.g. [TextInputAction.done]).
  final TextInputAction? textInputAction;

  /// Called when the user submits via the keyboard action button.
  final ValueChanged<String>? onSubmitted;

  final Color? borderColor;
  final Color? focusBorderColor;

  /// When non-null, a fixed-height (28 px) animated error slot is
  /// rendered below the input. An empty string reserves the space
  /// silently; a non-empty string shows the animated error message.
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final hasError = errorMessage != null && errorMessage!.isNotEmpty;

    final field = TextField(
      controller: controller,
      obscureText: obscureText,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        filled: true,
        fillColor: AppColors.darkSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: (borderColor != null || hasError)
              ? BorderSide(
                  color: hasError ? AppColors.brandRed : borderColor!,
                  width: 1,
                )
              : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError
                ? AppColors.brandRed
                : (focusBorderColor ?? AppColors.tealAccent),
            width: 1.5,
          ),
        ),
        suffixIcon: suffixIcon,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
        ],
        field,
        // Fixed-height error slot — height never changes so parent
        // Column layout (Spacers, buttons) stay put. The message
        // slides down and fades in/out within the reserved space.
        if (errorMessage != null)
          SizedBox(
            height: 28,
            child: ClipRect(
              child: AnimatedSlide(
                offset: hasError ? Offset.zero : const Offset(0, -1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: hasError ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.brandRed,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
