import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_colors.dart';

class AppFabToast extends StatefulWidget {
  const AppFabToast({super.key, this.fab, this.enabled = true});

  final Widget? fab;
  final bool enabled;

  @override
  State<AppFabToast> createState() => AppFabToastState();
}

class AppFabToastState extends State<AppFabToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 150),
  );
  Timer? _timer;
  String? _message;
  int _generation = 0;
  bool _transitioning = false;

  Future<void> show(String message) async {
    if (!widget.enabled) return;
    final generation = ++_generation;
    _timer?.cancel();
    await _replace(message, generation);
    if (!mounted || generation != _generation) return;
    _timer = Timer(const Duration(seconds: 4), () {
      unawaited(_replace(null, generation));
    });
  }

  Future<void> _replace(String? message, int generation) async {
    setState(() => _transitioning = true);
    try {
      if (!MediaQuery.disableAnimationsOf(context)) {
        await _fade.reverse().orCancel;
      }
      if (!mounted || generation != _generation) return;
      setState(() => _message = message);
      if (!MediaQuery.disableAnimationsOf(context)) {
        await _fade.forward().orCancel;
      } else {
        _fade.value = 1;
      }
      if (mounted && generation == _generation) {
        setState(() => _transitioning = false);
      }
    } on TickerCanceled {
      // A newer hint or disposal owns the animation now.
    }
  }

  void _dismiss() {
    _timer?.cancel();
    unawaited(_replace(null, ++_generation));
  }

  @override
  void didUpdateWidget(AppFabToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      ++_generation;
      _timer?.cancel();
      _fade.value = 1;
      _message = null;
      _transitioning = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    final brightness = Theme.of(context).brightness;
    return SizedBox(
      width: MediaQuery.sizeOf(context).width - AppSpacing.lg * 2,
      child: Align(
        alignment: Alignment.bottomRight,
        heightFactor: 1,
        child: IgnorePointer(
          ignoring: _transitioning,
          child: FadeTransition(
            opacity: _fade,
            child: message == null
                ? widget.fab ?? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.xs,
                      right: AppSpacing.xs,
                      bottom: AppSpacing.innerGap,
                    ),
                    child: Semantics(
                      liveRegion: true,
                      child: SnackBar(
                        animation: const AlwaysStoppedAnimation(1),
                        backgroundColor: AppColors.modalBackground(brightness),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: AppColors.navBorder(brightness),
                          ),
                        ),
                        padding: const EdgeInsets.only(
                          left: AppSpacing.lg,
                          right: AppSpacing.xs,
                          top: AppSpacing.xs,
                          bottom: AppSpacing.xs,
                        ),
                        content: Row(
                          children: [
                            Expanded(
                              child: Text(
                                message,
                                style: TextStyle(
                                  color: AppColors.onSurface(brightness),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            IconButton(
                              onPressed: _dismiss,
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).closeButtonTooltip,
                              color: AppColors.onSurface(brightness),
                              icon: const Icon(Icons.close, size: 20),
                            ),
                          ],
                        ),
                        behavior: SnackBarBehavior.floating,
                        margin: EdgeInsets.zero,
                        dismissDirection: DismissDirection.none,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
