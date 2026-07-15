import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Rotating login message matching the web panel's timing and fade behavior.
class RotatingWelcome extends StatefulWidget {
  const RotatingWelcome({
    super.key,
    required this.messages,
    required this.textColor,
  });

  final List<String> messages;
  final Color textColor;

  @override
  State<RotatingWelcome> createState() => _RotatingWelcomeState();
}

class _RotatingWelcomeState extends State<RotatingWelcome> {
  static const _rotationInterval = Duration(milliseconds: 3800);
  static const _swapDelay = Duration(milliseconds: 350);
  static const _fadeDuration = Duration(milliseconds: 300);

  Timer? _rotationTimer;
  Timer? _swapTimer;
  var _index = 0;
  var _visible = true;
  bool? _animationsDisabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (_animationsDisabled == disabled) return;
    _animationsDisabled = disabled;
    _stopTimers();
    if (!disabled && widget.messages.length > 1) {
      _rotationTimer = Timer.periodic(_rotationInterval, (_) => _rotate());
    }
  }

  @override
  void didUpdateWidget(covariant RotatingWelcome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(oldWidget.messages, widget.messages)) return;
    _index = 0;
    _visible = true;
    _stopTimers();
    if (_animationsDisabled == false && widget.messages.length > 1) {
      _rotationTimer = Timer.periodic(_rotationInterval, (_) => _rotate());
    }
  }

  void _rotate() {
    if (!mounted || widget.messages.isEmpty) return;
    setState(() => _visible = false);
    _swapTimer?.cancel();
    _swapTimer = Timer(_swapDelay, () {
      if (!mounted || widget.messages.isEmpty) return;
      setState(() {
        _index = (_index + 1) % widget.messages.length;
        _visible = true;
      });
    });
  }

  void _stopTimers() {
    _rotationTimer?.cancel();
    _swapTimer?.cancel();
    _rotationTimer = null;
    _swapTimer = null;
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) return const SizedBox(height: 18);
    final index = _index.clamp(0, widget.messages.length - 1);
    return SizedBox(
      height: 18,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: _animationsDisabled == true ? Duration.zero : _fadeDuration,
        child: Text(
          widget.messages[index],
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: widget.textColor, height: 1.4),
        ),
      ),
    );
  }
}
