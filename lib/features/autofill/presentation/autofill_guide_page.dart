import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_bar_title.dart';
import '../../../core/widgets/app_screen.dart';
import '../../../core/widgets/fab_registrar.dart';
import '../../../core/widgets/setup_card.dart';
import '../../../l10n/generated/app_localizations.dart';

class AutofillGuidePage extends StatelessWidget {
  const AutofillGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;

    return AppScreen.appBar(
      floatingActionButton: const FabRegistrar(fab: null),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
        title: AppBarTitle(title: l10n.autofillGuideTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          0,
          AppSpacing.screenH,
          AppSpacing.screenBottom,
        ),
        children: [
          SetupCard(
            title: l10n.autofillGuideEnableTitle,
            descriptions: [
              isIos
                  ? l10n.autofillGuideIosEnable
                  : l10n.autofillGuideAndroidEnable,
              if (!isIos) l10n.autofillGuideChrome,
            ],
            actions: const [],
          ),
          SetupCard(
            title: l10n.autofillGuidePrepareTitle,
            descriptions: [l10n.autofillGuidePrepare],
            actions: const [],
          ),
          SetupCard(
            title: l10n.autofillGuideUseTitle,
            descriptions: [
              isIos ? l10n.autofillGuideIosUse : l10n.autofillGuideAndroidUse,
            ],
            actions: const [],
          ),
          SetupCard(
            title: l10n.autofillGuideHelpTitle,
            descriptions: [l10n.autofillGuideHelp],
            actions: const [],
          ),
        ],
      ),
    );
  }
}
