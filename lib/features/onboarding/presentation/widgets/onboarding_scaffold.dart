import 'package:flutter/material.dart';

import '../../../../core/widgets/app_brand_background.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/auth_brand_layout.dart';
import 'onboarding_progress_dots.dart';

/// Common scaffold shared by all three onboarding screens.
///
/// Keeps the dark background, progress dots, title, subtitle, and
/// scrollable content area consistent across the wizard. Individual
/// screens pass their step-specific [children] in.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.currentStep,
    required this.title,
    required this.subtitle,
    required this.children,
    this.footer,
    this.onBack,
    this.centerContent = false,
    this.header,
    this.bottom,
    this.titleFontSize = 22,
    this.useAuthBrandLayout = false,
    this.contentTopSpacing,
    this.showTitleBlock = true,
    this.centerFooterInRemainingSpace = false,
    this.centerFooterAbovePinnedBottom = false,
  }) : assert(
         !(centerFooterInRemainingSpace || centerFooterAbovePinnedBottom) ||
             contentTopSpacing != null,
         'A fixed content start is required when centering the footer.',
       );

  final int currentStep;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? footer;
  final Widget? header;
  final Widget? bottom;
  final double titleFontSize;
  final bool useAuthBrandLayout;
  final double? contentTopSpacing;
  final bool showTitleBlock;

  /// Places [footer] in the visual center of the flexible space between the
  /// last child and [bottom]. All three regions stay in one scroll view, so a
  /// compact screen scrolls instead of clipping the final form actions.
  final bool centerFooterInRemainingSpace;
  final bool centerFooterAbovePinnedBottom;

  /// When non-null, a back arrow is shown to the left of the progress dots.
  final VoidCallback? onBack;

  /// Vertically centers the title, [children], and footer as one form block.
  /// The block remains scrollable when the available height is constrained.
  final bool centerContent;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _OnboardingBackground(
        useAuthBrandLayout: useAuthBrandLayout,
        brightness: brightness,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              useAuthBrandLayout ? 0 : AppSpacing.headerGap,
              AppSpacing.screenH,
              AppSpacing.xxl,
            ),
            child: _OnboardingContentWidth(
              enabled: useAuthBrandLayout,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header ??
                      Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: onBack != null
                                ? GestureDetector(
                                    onTap: onBack,
                                    child: Icon(
                                      Icons.arrow_back_ios_new,
                                      color: AppColors.onSurfaceMuted(
                                        brightness,
                                      ),
                                      size: 18,
                                    ),
                                  )
                                : null,
                          ),
                          Expanded(
                            child: OnboardingProgressDots(
                              currentStep: currentStep,
                            ),
                          ),
                          const SizedBox(width: 28),
                        ],
                      ),
                  if (contentTopSpacing != null &&
                      (centerFooterInRemainingSpace ||
                          centerFooterAbovePinnedBottom))
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: IntrinsicHeight(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(height: contentTopSpacing!),
                                    if (showTitleBlock) ...[
                                      _TitleBlock(
                                        title: title,
                                        subtitle: subtitle,
                                        brightness: brightness,
                                        titleFontSize: titleFontSize,
                                      ),
                                      const SizedBox(height: AppSpacing.xl),
                                    ],
                                    ...children,
                                    if (footer != null)
                                      Expanded(
                                        child: Center(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: AppSpacing.fieldGap,
                                            ),
                                            child: footer!,
                                          ),
                                        ),
                                      ),
                                    if (centerFooterInRemainingSpace) ?bottom,
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else if (contentTopSpacing != null)
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(height: contentTopSpacing!),
                                  if (showTitleBlock) ...[
                                    _TitleBlock(
                                      title: title,
                                      subtitle: subtitle,
                                      brightness: brightness,
                                      titleFontSize: titleFontSize,
                                    ),
                                    const SizedBox(height: AppSpacing.xl),
                                  ],
                                  ...children,
                                  if (footer != null) ...[
                                    const SizedBox(height: AppSpacing.fieldGap),
                                    footer!,
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else if (centerContent)
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _TitleBlock(
                                    title: title,
                                    subtitle: subtitle,
                                    brightness: brightness,
                                    titleFontSize: titleFontSize,
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  ...children,
                                  if (footer != null) ...[
                                    const SizedBox(height: AppSpacing.fieldGap),
                                    footer!,
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else ...[
                    const SizedBox(height: AppSpacing.headerGap),
                    _TitleBlock(
                      title: title,
                      subtitle: subtitle,
                      brightness: brightness,
                      titleFontSize: titleFontSize,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children,
                        ),
                      ),
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: AppSpacing.fieldGap),
                      footer!,
                    ],
                  ],
                  if (bottom != null && !centerFooterInRemainingSpace) ...[
                    if (!centerFooterAbovePinnedBottom)
                      const SizedBox(height: AppSpacing.fieldGap),
                    bottom!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingBackground extends StatelessWidget {
  const _OnboardingBackground({
    required this.useAuthBrandLayout,
    required this.brightness,
    required this.child,
  });

  final bool useAuthBrandLayout;
  final Brightness brightness;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (useAuthBrandLayout) {
      return AuthBrandBackground(child: child);
    }
    return AppBrandBackground(showDarkGrain: true, child: child);
  }
}

class _OnboardingContentWidth extends StatelessWidget {
  const _OnboardingContentWidth({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return enabled ? AuthContentWidth(child: child) : child;
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.title,
    required this.subtitle,
    required this.brightness,
    required this.titleFontSize,
  });

  final String title;
  final String subtitle;
  final Brightness brightness;
  final double titleFontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: titleFontSize,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface(brightness),
            height: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.onSurfaceSubtle(brightness),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
