import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'brand_tab_indicator.dart';

/// Full-width framed tabs; long translations remain horizontally scrollable.
class AppDetailTabs extends StatefulWidget implements PreferredSizeWidget {
  const AppDetailTabs({
    super.key,
    required this.tabs,
    this.controller,
    this.disabledIndices = const {},
    this.onSelected,
  });

  final List<Tab> tabs;
  final TabController? controller;
  final Set<int> disabledIndices;
  final ValueChanged<int>? onSelected;

  @override
  Size get preferredSize => const Size.fromHeight(50);

  @override
  State<AppDetailTabs> createState() => _AppDetailTabsState();
}

class _AppDetailTabsState extends State<AppDetailTabs> {
  bool _canScrollBack = false;
  bool _canScrollForward = true;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    const style = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
    return LayoutBuilder(
      builder: (context, constraints) {
        var widest = 0.0;
        for (final tab in widget.tabs) {
          final painter = TextPainter(
            text: TextSpan(
              text: tab.text,
              style: DefaultTextStyle.of(context).style.merge(style),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final width = painter.width + AppSpacing.cardPadding * 2;
          if (width > widest) widest = width;
          painter.dispose();
        }
        final scrollable =
            widest * widget.tabs.length >
            constraints.maxWidth - AppSpacing.chipGap * 2;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.chipGap,
            horizontal: AppSpacing.chipGap,
          ),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            border: Border.symmetric(
              horizontal: BorderSide(color: AppColors.cardBorder(brightness)),
            ),
          ),
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.axis == Axis.horizontal) {
                    final back = notification.metrics.extentBefore > 1;
                    final forward = notification.metrics.extentAfter > 1;
                    if (back != _canScrollBack ||
                        forward != _canScrollForward) {
                      setState(() {
                        _canScrollBack = back;
                        _canScrollForward = forward;
                      });
                    }
                  }
                  return false;
                },
                child: TabBar(
                  controller: widget.controller,
                  onTap: (index) {
                    if (widget.disabledIndices.contains(index)) {
                      final controller =
                          widget.controller ?? DefaultTabController.of(context);
                      controller.index = controller.previousIndex;
                      return;
                    }
                    widget.onSelected?.call(index);
                  },
                  isScrollable: scrollable,
                  tabAlignment: scrollable
                      ? TabAlignment.start
                      : TabAlignment.fill,
                  labelPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.cardPadding,
                  ),
                  labelColor: AppColors.onSurface(brightness),
                  unselectedLabelColor: AppColors.onSurfaceMuted(brightness),
                  indicator: BrandTabIndicator(
                    color: AppColors.onSurface(brightness),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.chipGap / 2,
                  ),
                  dividerHeight: 0,
                  labelStyle: style,
                  tabs: [
                    for (final (index, tab) in widget.tabs.indexed)
                      Tab(
                        height: 36,
                        child: Opacity(
                          opacity: widget.disabledIndices.contains(index)
                              ? 0.4
                              : 1,
                          child: Semantics(
                            enabled: !widget.disabledIndices.contains(index),
                            child:
                                tab.child ??
                                (tab.text != null
                                    ? Text(tab.text!)
                                    : tab.icon ?? const SizedBox.shrink()),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (scrollable && _canScrollBack) _overflowHint(brightness, true),
              if (scrollable && _canScrollForward)
                _overflowHint(brightness, false),
            ],
          ),
        );
      },
    );
  }

  Widget _overflowHint(Brightness brightness, bool leading) => Positioned(
    left: leading ? 0 : null,
    right: leading ? null : 0,
    top: 0,
    bottom: 0,
    child: IgnorePointer(
      child: Container(
        width: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: leading ? Alignment.centerLeft : Alignment.centerRight,
            end: leading ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              AppColors.cardFill(brightness),
              AppColors.cardFill(brightness).withValues(alpha: 0),
            ],
          ),
        ),
        child: Icon(
          leading ? Icons.chevron_left : Icons.chevron_right,
          size: 14,
          color: AppColors.onSurfaceMuted(brightness),
        ),
      ),
    ),
  );
}
