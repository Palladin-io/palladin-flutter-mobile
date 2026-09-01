import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../../vault/presentation/pages/import_vault_picker_page.dart';

/// Account-level hand-off to the existing on-device import flow.
class DataImportPage extends StatelessWidget {
  const DataImportPage({super.key});

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
          title: l10n.settingsDataImportTitle,
          subtitle: l10n.settingsDataImportSubtitle,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          0,
          AppSpacing.screenH,
          AppSpacing.screenBottom,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            decoration: BoxDecoration(
              color: AppColors.cardFill(brightness),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder(brightness)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.file_upload_outlined,
                  color: AppColors.brandRed,
                  size: 28,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.importIntroTitle,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.innerGap),
                Text(
                  l10n.settingsDataImportBody,
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                PrimaryButton(
                  label: l10n.settingsDataImportAction,
                  leading: const Icon(
                    Icons.file_upload_outlined,
                    color: AppColors.onBrandRed,
                    size: 18,
                  ),
                  onPressed: () => ImportVaultPickerPage.push(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
