import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared sheet chrome that fills its host's bounded height.
/// The host owns height constraints, routing and modal semantics.
class SheetSurface extends StatelessWidget {
  const SheetSurface({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
    this.showClose = false,
  });
  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.modalBackground(brightness),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.navBorder(brightness)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.lg,
                  AppSpacing.screenH,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (showClose)
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
