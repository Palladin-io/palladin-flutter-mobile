import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Compact, single-accent on/off toggle — the app's switch idiom.
///
/// Replaces the bulky two-tone Material [Switch]: a 32×18 pill that is
/// `AppColors.brandRed` when ON and a neutral track when OFF, with a white
/// thumb. Used for per-channel notification preferences and any compact
/// settings row. `null` [onChanged] renders a dimmed, non-interactive toggle
/// (e.g. mandatory/locked rows).
class AppToggle extends StatelessWidget {
  const AppToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;

  /// Called with the new value on tap. When `null` the toggle is locked
  /// (dimmed, ignores taps).
  final ValueChanged<bool>? onChanged;

  static const double _width = 32;
  static const double _height = 18;
  static const double _thumb = 14;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final locked = onChanged == null;

    final trackOn = AppColors.brandRed;
    final trackOff = AppColors.toggleTrackOff(brightness);
    final track = value ? trackOn : trackOff;

    final toggle = Opacity(
      opacity: locked ? 0.45 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeInOut,
        width: _width,
        height: _height,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: track,
          borderRadius: BorderRadius.circular(_height / 2),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: _thumb,
            height: _thumb,
            decoration: const BoxDecoration(
              color: AppColors.onBrandRed,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );

    if (locked) return toggle;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged!(!value),
      child: toggle,
    );
  }
}
