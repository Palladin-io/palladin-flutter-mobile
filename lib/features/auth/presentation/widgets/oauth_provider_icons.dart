import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Provider artwork sourced from the vendors' official brand resources.
///
/// Google: https://developers.google.com/identity/branding-guidelines
/// Apple: https://appleid.cdn-apple.com/appleid/button/logo
/// X: https://about.x.com/en/who-we-are/brand-toolkit
final Uint8List _googleLogoBytes = base64Decode(
  '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',
);

final Uint8List _appleLogoBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAYAAAAehFoBAAAAAXNSR0IArs4c6QAAAcBJREFUWIXtmcuN2zAURW88myxZwksFo523LEEdmCWwhClBHdgdiB2YHViuQHIFonfe3SzGdoQJAoQSaSmIDsCNAJKHD48fkcAvBEANoAXAhZT27iT4ggHQL0DwT6W/Oz4ju2TZobS8ATgAKL6GfIF8B/BjA+B9bpMI3r/hM9z/DJu5BWJZhXOzCg8REdR1Dedc0nazLPQiwr7vSZLW2pRt5xF2zpEkQwhUSi1f+CFblmXSdt8AfGAiSilst1uICK7XK263G87nM6y1UEpht9sBAC6Xy9SuAEwcsTHmmasP6rrmfr//7XvbtiyKYr6UMMYwFu/9fMIhhCjZrutSTMBxFbXW0dE1xkyedKM3Dq11dB3v/djunvw/W3MIIbpOUaT5sXlZDp9Op8k5PFoYI1YJkjwejxSR1086AKNOYVrryakxerQiEh3hruvmSwkArKoqSjjBYWiasFKKTdP8lezhcJh30g2lvfckSeccy7Kk1prWWjZNwxACq6pKIcv1XiI3q3BuVuHcrMK5WYVzswGQ5nbjNZw3AJq5LSLogM9nr4AEB5PMJWDwwGgWLh0weFh8IADcPexzCz5Kc3d6RvYnLLrCi476658AAAAASUVORK5CYII=',
);

class GoogleProviderIcon extends StatelessWidget {
  const GoogleProviderIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Image.memory(
        _googleLogoBytes,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      ),
    );
  }
}

class AppleProviderIcon extends StatelessWidget {
  const AppleProviderIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Image.memory(
        _appleLogoBytes,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      ),
    );
  }
}

class XProviderIcon extends StatelessWidget {
  const XProviderIcon({super.key});

  static Color colorFor(Brightness brightness) =>
      AppColors.onSurface(brightness);

  @override
  Widget build(BuildContext context) {
    final color = colorFor(Theme.of(context).brightness);
    return ExcludeSemantics(
      child: CustomPaint(
        size: const Size(19.6, 20),
        painter: _XLogoPainter(color),
      ),
    );
  }
}

class _XLogoPainter extends CustomPainter {
  const _XLogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(714.163, 519.284)
      ..lineTo(1160.89, 0)
      ..lineTo(1055.03, 0)
      ..lineTo(667.137, 450.887)
      ..lineTo(357.328, 0)
      ..lineTo(0, 0)
      ..lineTo(468.492, 681.821)
      ..lineTo(0, 1226.37)
      ..lineTo(105.866, 1226.37)
      ..lineTo(515.491, 750.218)
      ..lineTo(842.672, 1226.37)
      ..lineTo(1200, 1226.37)
      ..lineTo(714.137, 519.284)
      ..close()
      ..moveTo(569.165, 687.828)
      ..lineTo(521.697, 619.934)
      ..lineTo(144.011, 79.6944)
      ..lineTo(306.615, 79.6944)
      ..lineTo(611.412, 515.685)
      ..lineTo(658.88, 583.579)
      ..lineTo(1055.08, 1150.3)
      ..lineTo(892.476, 1150.3)
      ..lineTo(569.165, 687.854)
      ..close();

    canvas
      ..save()
      ..scale(size.width / 1200, size.height / 1226.37)
      ..drawPath(path, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_XLogoPainter oldDelegate) => color != oldDelegate.color;
}
