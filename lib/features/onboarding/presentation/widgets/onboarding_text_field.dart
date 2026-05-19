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
    this.reserveSpace = true,
  });

  final bool visible;
  final Widget child;

  /// Total reserved height of the slot (only used when [reserveSpace] is true).
  final double height;

  /// When true (default) the slot always occupies [height] px so the
  /// parent layout never shifts — suitable for fixed-height forms like
  /// login screens. When false the height collapses to 0 when the
  /// feedback is hidden — suitable for scrollable forms where a layout
  /// shift is acceptable.
  final bool reserveSpace;

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

  Widget _innerContent() => Padding(
        padding: const EdgeInsets.only(top: FieldFeedbackSlot._kTopPadding),
        child: widget.child,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.reserveSpace) {
      // Fixed-height slot: always occupies space, content slides from above.
      return SizedBox(
        height: widget.height,
        child: ClipRect(
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _controller,
              child: _innerContent(),
            ),
          ),
        ),
      );
    }

    // Collapsing slot: height animates from 0, content fades in.
    // Use SizeTransition so no space is reserved when feedback is hidden.
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      alignment: -1.0,
      child: FadeTransition(
        opacity: _controller,
        child: _innerContent(),
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
/// - [focusBorderColor] — focused-state border; null = [AppColors.brandRed]
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
    this.prefixIcon,
    this.suffixIcon,
    this.autocorrect = false,
    this.enableSuggestions = false,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.borderColor,
    this.focusBorderColor,
    this.fillColor,
    this.feedbackChild,
    this.feedbackVisible = false,
    this.feedbackReserveSpace = true,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final bool obscureText;

  /// Maximum number of lines for the input. Default 1 (single-line).
  /// Set to a higher value (e.g. 3) for multi-line inputs like notes.
  /// Forced to 1 when [obscureText] is true (Flutter requirement).
  final int maxLines;

  /// Optional icon rendered as [InputDecoration.prefixIcon]. Wrap in
  /// [Padding] to control spacing — the field sets
  /// `prefixIconConstraints: BoxConstraints()` so the icon does not
  /// inflate the input height.
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Color? borderColor;
  final Color? focusBorderColor;

  /// Background fill of the input. Defaults to
  /// [AppColors.inputFill] (brightness-aware — navy in dark, near-transparent
  /// in light) when null. Pass a different color when reusing this field on
  /// screens with a different surface tone.
  final Color? fillColor;

  /// Widget shown inside the [FieldFeedbackSlot] below the input.
  /// Always provide this when feedback is needed so the slot height is
  /// reserved from the first build. Use [feedbackVisible] to toggle it.
  final Widget? feedbackChild;

  /// Whether [feedbackChild] is currently visible.
  final bool feedbackVisible;

  /// Passed through to [FieldFeedbackSlot.reserveSpace]. Default true
  /// (login/onboarding screens keep the layout stable). Set to false on
  /// scrollable forms where a collapsing slot is preferred.
  final bool feedbackReserveSpace;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // Active-state color: text color (cream in dark, navy in light).
    // Red was misleading — it matched the error state and made focused
    // inputs look invalid even when they were fine.
    final activeColor = AppColors.onSurface(brightness);
    final field = TextField(
      cursorColor: activeColor,
      controller: controller,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      style: TextStyle(color: AppColors.inputText(brightness), fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: AppColors.inputHint(brightness)),
        filled: true,
        fillColor: fillColor ?? AppColors.inputFill(brightness),
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
          borderSide: BorderSide(
            color: borderColor ?? AppColors.inputBorder(brightness),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: focusBorderColor ?? activeColor,
            width: 1.5,
          ),
        ),
        prefixIcon: prefixIcon,
        // Strip the default 48px min-width that Material applies to
        // prefix icons — without this the search/glyph in tight rows
        // pushes the input height up and breaks alignment with form
        // fields elsewhere on the screen. Wrap [prefixIcon] in
        // [Padding] to control the gap between icon and text.
        prefixIconConstraints: const BoxConstraints(),
        suffixIcon: suffixIcon,
      ),
    );

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
          const SizedBox(height: 8),
        ],
        field,
        if (feedbackChild != null)
          FieldFeedbackSlot(
            visible: feedbackVisible,
            reserveSpace: feedbackReserveSpace,
            child: feedbackChild!,
          ),
      ],
    );
  }
}
