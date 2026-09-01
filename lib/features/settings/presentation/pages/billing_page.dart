import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Honest placeholder for the planned Billing module.
class BillingPage extends StatelessWidget {
  const BillingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return AppScreen.appBar(
      floatingActionButton: const FabRegistrar(fab: null),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
        title: AppBarTitle(
          title: l10n.settingsBillingTitle,
          subtitle: l10n.settingsBillingSubtitle,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.cardFill(brightness),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder(brightness)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.credit_card_outlined,
                  color: AppColors.premiumAmber,
                  size: 32,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.settingsBillingComingSoon,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.innerGap),
                Text(
                  l10n.settingsBillingComingSoonBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
