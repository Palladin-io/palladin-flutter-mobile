import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../bloc/settings_cubit.dart';
import 'settings_error_text.dart';

/// Organization block of the settings screen — shows the org name in an
/// editable field with a Save button, plus a member-count subtitle.
///
/// Loads, error and content states are all handled here so the screen
/// can drop the section in without branching. Save success / failure is
/// surfaced via a snackbar driven by [SettingsCubit]'s transient
/// `orgSave*` flags.
class OrgSettingsSection extends StatefulWidget {
  const OrgSettingsSection({super.key});

  @override
  State<OrgSettingsSection> createState() => _OrgSettingsSectionState();
}

class _OrgSettingsSectionState extends State<OrgSettingsSection> {
  final TextEditingController _nameController = TextEditingController();

  /// The name last synced from the cubit — used to detect dirty edits
  /// and to avoid clobbering in-progress typing on unrelated rebuilds.
  String _syncedName = '';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Pushes the org name from state into the field, but only when it
  /// actually changed server-side — never overwrites the user's
  /// in-progress edits on an unrelated rebuild.
  void _syncControllerFromState(String orgName) {
    if (orgName == _syncedName) return;
    _syncedName = orgName;
    _nameController.text = orgName;
  }

  bool _canSave(SettingsState state) {
    if (state.isSavingOrg) return false;
    final trimmed = _nameController.text.trim();
    return trimmed.isNotEmpty && trimmed != state.org?.name;
  }

  void _onSave() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    context.read<SettingsCubit>().saveOrgName(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return BlocConsumer<SettingsCubit, SettingsState>(
      // Surface save success / failure exactly once via a snackbar, then
      // tell the cubit to clear the transient flags so the snackbar
      // doesn't re-fire on the next rebuild.
      listenWhen: (prev, curr) =>
          prev.orgSaveSucceeded != curr.orgSaveSucceeded ||
          prev.orgSaveError != curr.orgSaveError,
      listener: (context, state) {
        if (state.orgSaveSucceeded) {
          _showSnack(context, l10n.settingsOrgSaved);
          context.read<SettingsCubit>().acknowledgeOrgSaveResult();
        } else if (state.orgSaveError != null) {
          _showSnack(context, settingsErrorMessage(l10n, state.orgSaveError!));
          context.read<SettingsCubit>().acknowledgeOrgSaveResult();
        }
      },
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(title: l10n.settingsOrganization),
            const SizedBox(height: AppSpacing.md),
            switch (state.orgStatus) {
              SectionStatus.initial ||
              SectionStatus.loading => const _OrgSkeleton(),
              SectionStatus.error => _OrgError(
                message: settingsErrorMessage(l10n, state.orgError!),
                onRetry: () => context.read<SettingsCubit>().loadOrg(),
              ),
              SectionStatus.loaded => _buildLoaded(
                context,
                l10n,
                brightness,
                state,
              ),
            },
          ],
        );
      },
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    AppLocalizations l10n,
    Brightness brightness,
    SettingsState state,
  ) {
    _syncControllerFromState(state.org?.name ?? '');
    final memberCount = state.org?.memberCount ?? 1;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OnboardingTextField(
            controller: _nameController,
            label: l10n.settingsOrgNameLabel,
            hintText: l10n.settingsOrgNameHint,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_canSave(state)) _onSave();
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.settingsOrgMembers(memberCount),
            style: TextStyle(
              fontSize: 11,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          PrimaryButton(
            label: l10n.settingsSave,
            isLoading: state.isSavingOrg,
            onPressed: _canSave(state) ? _onSave : null,
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Uppercase section heading used by the organization block.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textTertiaryMobile,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Animated skeleton placeholder shown while the org details load.
class _OrgSkeleton extends StatelessWidget {
  const _OrgSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonBox(height: 132);
  }
}

/// Inline error card for a failed org load, with a retry affordance.
class _OrgError extends StatelessWidget {
  const _OrgError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: AppColors.brandRed),
            child: Text(l10n.settingsRetry),
          ),
        ],
      ),
    );
  }
}
