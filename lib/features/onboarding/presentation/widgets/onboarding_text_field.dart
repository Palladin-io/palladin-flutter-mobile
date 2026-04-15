import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Reusable animated feedback slot used below every input field.
///
/// Reserves [height] px at all times so the parent layout never shifts.
/// When [visible] is true, [child] slides down from above and fades in;
/// when false, it slides back up and fades out — all within the fixed
/// reserved space.
///
/// The top padding inside the slot (gap from input edge to content) is
/// always [_kTopPadding] — defined once here so every form in the app
/// has identical spacing.
class FieldFeedbackSlot extends StatelessWidget {
  const FieldFeedbackSlot({
    super.key,
    required this.visible,
    required this.child,
    this.height = 28,
  });

  final bool visible;
  final Widget child;

  /// Total reserved height of the slot. Defaults to 28 px, which fits a
  /// single line of 12 px text with [_kTopPadding] above it. Pass a
  /// larger value (e.g. 36) when the content is taller (strength bar +
  /// label).
  final double height;

  /// Gap between the bottom of the input and the top of the feedback
  /// content. Defined once here — change it and every field updates.
  static const double _kTopPadding = 4;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRect(
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child: Padding(
              padding: const EdgeInsets.only(top: _kTopPadding),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared styled TextField for onboarding and authentication screens.
///
/// Encapsulates the dark-surface fill, rounded border, and consistent
/// text style. Optionally renders a label above the field and a
/// fixed-height animated error slot below it via [FieldFeedbackSlot].
///
/// ## Error slot
/// Pass [errorMessage] (even as an empty string) to reserve the slot.
/// Non-empty string → error slides in; empty string → slot stays
/// invisible but height is reserved. Omit entirely (null) when you
/// handle feedback yourself (e.g. strength bar with a custom slot).
///
/// ## Border behaviour
/// - [borderColor]      — enabled-state border; null = no border
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
    this.feedbackChild,
    this.feedbackVisible = false,
  });

  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final bool obscureText;
  final Widget? suffixIcon;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Color? borderColor;
  final Color? focusBorderColor;

  /// When non-null, a [FieldFeedbackSlot] is rendered below the input.
  /// Empty string reserves the space silently; non-empty shows the error.
  final String? errorMessage;

  /// Custom feedback widget rendered in a [FieldFeedbackSlot] below the input.
  /// Use [feedbackVisible] to control visibility. Takes precedence over
  /// [errorMessage] when both are set — use one or the other, not both.
  final Widget? feedbackChild;
  final bool feedbackVisible;

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
        if (feedbackChild != null)
          FieldFeedbackSlot(
            visible: feedbackVisible,
            child: feedbackChild!,
          )
        else if (errorMessage != null)
          FieldFeedbackSlot(
            visible: hasError,
            child: Text(
              errorMessage!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.brandRed,
              ),
            ),
          ),
      ],
    );
  }
}
