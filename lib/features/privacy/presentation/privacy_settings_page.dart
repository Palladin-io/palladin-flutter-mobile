import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_bar_title.dart';
import '../../../core/widgets/app_screen.dart';
import '../../../core/widgets/fab_registrar.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'consent_choices.dart';

class PrivacySettingsPage extends StatelessWidget {
  const PrivacySettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppScreen.appBar(
      floatingActionButton: const FabRegistrar(fab: null),
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        title: AppBarTitle(title: l10n.privacyTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          0,
          AppSpacing.screenH,
          AppSpacing.screenBottom,
        ),
        children: [
          Text(l10n.privacySubtitle),
          const SizedBox(height: AppSpacing.section),
          const ConsentChoices(source: 'mobile_settings'),
        ],
      ),
    );
  }
}
