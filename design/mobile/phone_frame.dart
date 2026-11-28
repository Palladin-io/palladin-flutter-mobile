import 'package:flutter/material.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';

/// Device-sized constraints and MediaQuery must agree, including pushed routes.
class PreviewPhoneFrame extends StatelessWidget {
  const PreviewPhoneFrame({super.key, required this.child});
  final Widget child;
  static const screenSize = Size(390, 844);
  static const safeInsets = EdgeInsets.only(top: 24, bottom: 24);

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ColoredBox(
      color: AppColors.darkBackground,
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox.fromSize(
            size: screenSize,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.cardFill(brightness),
                ),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: screenSize,
                    padding: safeInsets,
                    viewPadding: safeInsets,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
