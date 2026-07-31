import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Opens Flutter's runtime registry of bundled open-source licences.
class OpenSourceLicensesSection extends StatelessWidget {
  const OpenSourceLicensesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.settingsOpenSourceSection.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textTertiaryMobile,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Material(
          color: AppColors.cardFill(brightness),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.cardBorder(brightness)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.code_rounded, color: AppColors.brandRed),
            title: Text(
              l10n.settingsOpenSourceLicenses,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              l10n.settingsOpenSourceLicensesHint,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 12,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l10n.appTitle,
              applicationLegalese: l10n.settingsOpenSourceLegalese,
            ),
          ),
        ),
      ],
    );
  }
}
