import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/brand_hero.dart';
import '../../data/autofill_cache_service.dart';
import '../../domain/autofill_preparation.dart';
import 'autofill_preparation_card.dart';

/// Gives real preparation the Home content area, keeping shell navigation intact.
class AutoFillHomeBody extends StatelessWidget {
  const AutoFillHomeBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final service = context.read<AutoFillCacheService?>();
    if (service == null) return child;
    return ValueListenableBuilder<AutoFillPreparation>(
      valueListenable: service.preparation,
      child: child,
      builder: (context, state, normalHome) {
        final total = state.total;
        final active =
            (state.phase == AutoFillPreparationPhase.preparing ||
                state.phase == AutoFillPreparationPhase.publishing) &&
            total != null &&
            total > 0;
        if (!active) return normalHome ?? child;
        return CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenH,
                  vertical: AppSpacing.screenBottom,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    BrandHero(
                      textColor: BrandHero.textColorFor(
                        Theme.of(context).brightness,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.section),
                    const AutoFillPreparationCard(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
