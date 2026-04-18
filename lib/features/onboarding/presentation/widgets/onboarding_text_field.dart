import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Reusable animated feedback slot used below every input field.
///
/// Reserves [height] px at all times so the parent layout never shifts.
/// When [visible] is true, [child] slides down from above and fades in;
/// when false, it slides back up and fades out — all within the fixed
/// reserved space.
///
/// Uses an explicit [AnimationController] so both enter and exit are
/// guaranteed to animate regardless of widget-tree position or rebuild
/// order. [didUpdateWidget] calls [forward] or [reverse] whenever
/// [visible] changes.
class FieldFeedbackSlot extends StatefulWidget {
  const FieldFeedbackSlot({
    super.key,
    required this.visible,
    required this.child,
    this.height = 28,
  });

  final bool visible;
  final Widget child;

  /// Total reserved height of the slot.
  final double height;

  /// Gap between the bottom of the input and the top of the feedback
  /// content. Defined once here — change it and every field updates.
  static const double _kTopPadding = 4;

  @override
  State<FieldFeedbackSlot> createState() => _FieldFeedbackSlotState();
}

class _FieldFeedbackSlotState extends State<FieldFeedbackSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
      value: widget.visible ? 1.0 : 0.0,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(FieldFeedbackSlot old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      widget.visible ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ClipRect(
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _controller,
            child: Padding(
              padding: const EdgeInsets.only(top: FieldFeedbackSlot._kTopPadding),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared styled TextField for onboarding and authentication screens.
///
/// Pass [feedbackChild] + [feedbackVisible] to show an animated feedback
/// row below the input (strength label, error message, etc.). The slot
/// always reserves [FieldFeedbackSlot]'s height so the layout never shifts.
///
/// ## Border behaviour
/// - [borderColor]      — enabled-state border; null = no border
/// - [focusBorderColor] — focused-state border; null = [AppColors.tealAccent]
///
/// For error state pass [AppColors.brandRed] to both border params and
/// set [feedbackVisible] to true with a red-styled [feedbackChild].
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

  /// Widget shown inside the [FieldFeedbackSlot] below the input.
  /// Always provide this when feedback is needed so the slot height is
  /// reserved from the first build. Use [feedbackVisible] to toggle it.
  final Widget? feedbackChild;

  /// Whether [feedbackChild] is currently visible.
  final bool feedbackVisible;

  @override
  Widget build(BuildContext context) {
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
          borderSide: borderColor != null
              ? BorderSide(color: borderColor!, width: 1)
              : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: focusBorderColor ?? AppColors.tealAccent,
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
          ),
      ],
    );
  }
}
