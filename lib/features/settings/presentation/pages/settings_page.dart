import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/permissions.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../bloc/settings_cubit.dart';
import '../widgets/org_settings_section.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

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
    final auth = context.watch<AuthBloc>().state;
    final canEdit =
        auth is AuthAuthenticated &&
        (auth.permissions & Permissions.organizationManagement) != 0;

    return AppScreen.appBar(
      safeAreaBottom: false,
      // Suppress any FAB leaking from the page we were pushed over.
      floatingActionButton: const FabRegistrar(fab: null),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
        title: AppBarTitle(
          title: l10n.settingsGeneralTitle,
          subtitle: l10n.settingsGeneralSubtitle,
        ),
      ),
      body: OrgSettingsSection(canEdit: canEdit),
    );
  }
}
