import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../bloc/settings_cubit.dart';
import '../widgets/api_key_list.dart';
import '../widgets/generate_api_key_dialog.dart';
import '../widgets/org_settings_section.dart';

/// Dedicated settings screen — organization details and API-key
/// management.
///
/// Reached from the settings drawer's "Organization & API keys" item.
/// Owns a fresh [SettingsCubit] which loads both sections on mount;
/// each section renders its own loading / error / content state so a
/// failure in one never blanks the other.
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

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient(brightness),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
          title: Text(
            l10n.settingsScreenTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            color: AppColors.brandRed,
            backgroundColor: AppColors.cardSurface(brightness),
            onRefresh: () => context.read<SettingsCubit>().load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: const [
                OrgSettingsSection(),
                SizedBox(height: 24),
                ApiKeyList(),
                SizedBox(height: 16),
                _GenerateKeyButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width button that opens the generate-API-key bottom sheet.
class _GenerateKeyButton extends StatelessWidget {
  const _GenerateKeyButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: () => GenerateApiKeyDialog.show(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandRed,
          foregroundColor: AppColors.onBrandRed,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.add, size: 18),
        label: Text(
          l10n.settingsGenerateApiKey,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
