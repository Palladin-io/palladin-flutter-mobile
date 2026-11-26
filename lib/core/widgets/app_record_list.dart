import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// One continuous surface with lazy rows and full-width separators.
class AppRecordList extends StatelessWidget {
  const AppRecordList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      sliver: SliverList.separated(
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          thickness: 1,
          color: AppColors.cardBorder(brightness),
        ),
      ),
    );
  }
}
