import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../bloc/settings_cubit.dart';
import '../widgets/open_source_licenses_section.dart';
import '../widgets/org_settings_section.dart';

/// Dedicated settings screen — organization details only.
///
/// Reached from the settings drawer's "Organization" item. API-key
/// management lives on its own standalone screen ([ApiKeysPage]).
///
/// Owns a fresh [SettingsCubit] which loads the organization section on
/// mount; the section renders its own loading / error / content state.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SettingsCubit>(
      create: (_) => getIt<SettingsCubit>()..load(),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return AppScreen.appBar(
      // Suppress any FAB leaking from the page we were pushed over.
      floatingActionButton: const FabRegistrar(fab: null),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
        title: AppBarTitle(title: l10n.settingsScreenTitle),
      ),
      body: RefreshIndicator(
        color: AppColors.brandRed,
        backgroundColor: AppColors.cardSurface(brightness),
        onRefresh: () => context.read<SettingsCubit>().load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Title→content gap (headerGap) is owned by AppScreen.appBar.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.screenBottom,
          ),
          children: const [
            OrgSettingsSection(),
            SizedBox(height: AppSpacing.section),
            OpenSourceLicensesSection(),
          ],
        ),
      ),
    );
  }
}
