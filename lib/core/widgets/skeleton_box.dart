import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Pulsing skeleton placeholder used while content loads.
///
/// Follows the project-wide skeleton pattern: an [AnimationController]
/// looping `repeat(reverse: true)` with a `0.4 → 0.85` opacity [Tween].
/// Multiple rows can be staggered by passing an increasing [delay]
/// (commonly `index * 80 ms`).
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    required this.height,
    this.borderRadius = 12,
    this.delay = Duration.zero,
  });

  final double height;
  final double borderRadius;

  /// Staggers the start of the animation so a column of skeletons does
  /// not pulse in lockstep.
  final Duration delay;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = Tween<double>(begin: 0.4, end: 0.85).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.delay == Duration.zero) {
      _ctrl.repeat(reverse: true);
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final base = AppColors.onSurface(brightness).withValues(alpha: 0.08);
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withValues(alpha: base.a * _anim.value),
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: AppColors.cardBorder(brightness)),
        ),
      ),
    );
  }
}
