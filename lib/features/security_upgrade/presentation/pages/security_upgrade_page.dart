import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/storage/biometric_key_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/auth_brand_layout.dart';
import '../../../../core/widgets/mnemonic_word_grid.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../secret_key/presentation/widgets/emergency_kit_step_screen.dart';
import '../../data/security_upgrade_remote_datasource.dart';
import '../../data/security_upgrade_service.dart';
import '../../domain/security_upgrade_start.dart';
import '../cubit/security_upgrade_cubit.dart';

/// Full-screen, non-dismissable security upgrade (first unlock after the
/// release, or a resumed upgrade). No algorithm names are shown.
class SecurityUpgradePage extends StatelessWidget {
  const SecurityUpgradePage({super.key, required this.start, this.cubit});

  final SecurityUpgradeStart start;

  /// Test seam; production builds the cubit from DI.
  final SecurityUpgradeCubit? cubit;

  @override
  Widget build(BuildContext context) => BlocProvider<SecurityUpgradeCubit>(
    create: (_) =>
        (cubit ??
              SecurityUpgradeCubit(
                service: getIt<SecurityUpgradeService>(),
                start: start,
              ))
          ..start(),
    child: const _SecurityUpgradeView(),
  );
}

class _SecurityUpgradeView extends StatelessWidget {
  const _SecurityUpgradeView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SecurityUpgradeCubit, SecurityUpgradeState>(
      builder: (context, state) {
        final cubit = context.read<SecurityUpgradeCubit>();
        final child = switch (state) {
          SecurityUpgradeProgress() => _ProgressView(state: state),
          SecurityUpgradeRecoveryPhrase(:final words) => _PhraseView(
            words: words,
          ),
          SecurityUpgradeConfirmPhrase() => _ConfirmView(
            key: ValueKey(state.positions.join(',')),
            state: state,
          ),
          SecurityUpgradeEmergencyKit(:final email, :final accountId) =>
            EmergencyKitStepScreen(
              email: email,
              accountId: accountId,
              accountSecret: cubit.emergencyKitSecret!,
              onContinue: cubit.acknowledgeEmergencyKit,
            ),
          SecurityUpgradeDone() => _DoneView(state: state),
        };
        return PopScope(canPop: false, child: child);
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    required this.subtitle,
    required this.children,
    this.footer,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuthBrandBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    AppSpacing.xxxl,
                    AppSpacing.screenH,
                    AppSpacing.section,
                  ),
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.onSurfaceMuted(brightness),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.section),
                    ...children,
                  ],
                ),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    AppSpacing.md,
                    AppSpacing.screenH,
                    AppSpacing.screenBottom,
                  ),
                  child: footer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.state});

  final SecurityUpgradeProgress state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final total = state.vaultsTotal;
    final vaultsDetail = switch (state.vaults) {
      UpgradeStepStatus.failed when total != null =>
        l10n.securityUpgradeStoppedAt(state.vaultsDone, total),
      UpgradeStepStatus.running when total != null => l10n.securityUpgradeCount(
        state.vaultsDone,
        total,
      ),
      final status => _statusLabel(l10n, status),
    };
    final error = state.error;
    return _Frame(
      title: l10n.securityUpgradeTitle,
      subtitle: l10n.securityUpgradeSubtitle,
      footer: error == null
          ? null
          : PrimaryButton(
              label: l10n.securityUpgradeRetry,
              onPressed: context.read<SecurityUpgradeCubit>().retry,
            ),
      children: [
        _StepRow(
          icon: Icons.key_outlined,
          label: l10n.securityUpgradeStepAccountKey,
          status: state.accountKey,
          detail: _statusLabel(l10n, state.accountKey),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        _StepRow(
          icon: Icons.shield_outlined,
          label: l10n.securityUpgradeStepVaults,
          status: state.vaults,
          detail: vaultsDetail,
        ),
        const SizedBox(height: AppSpacing.cardGap),
        _StepRow(
          icon: Icons.smart_toy_outlined,
          label: l10n.securityUpgradeStepAgents,
          status: state.agents,
          detail: _statusLabel(l10n, state.agents),
        ),
        const SizedBox(height: AppSpacing.section),
        if (error != null)
          WarningZone(
            title: l10n.securityUpgradeErrorTitle,
            message: error == SecurityUpgradeErrorKind.network
                ? l10n.securityUpgradeNetworkError
                : l10n.securityUpgradeServerError,
          )
        else
          Text(
            l10n.securityUpgradeEntriesUnchanged,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 12,
              height: 1.4,
            ),
          ),
      ],
    );
  }

  static String _statusLabel(AppLocalizations l10n, UpgradeStepStatus status) =>
      switch (status) {
        UpgradeStepStatus.waiting => l10n.securityUpgradeStatusWaiting,
        UpgradeStepStatus.running => l10n.securityUpgradeStatusRunning,
        UpgradeStepStatus.done => l10n.securityUpgradeStatusDone,
        UpgradeStepStatus.failed => l10n.securityUpgradeStatusStopped,
      };
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final UpgradeStepStatus status;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final (statusIcon, color) = switch (status) {
      UpgradeStepStatus.done => (Icons.check, AppColors.positiveAccent),
      UpgradeStepStatus.failed => (Icons.priority_high, AppColors.brandRed),
      _ => (icon, AppColors.onSurfaceMuted(brightness)),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.navBorder(brightness)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: status == UpgradeStepStatus.running
                ? const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brandRed,
                  )
                : Icon(statusIcon, size: 20, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(detail, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PhraseView extends StatelessWidget {
  const _PhraseView({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Frame(
      title: l10n.securityUpgradePhraseTitle,
      subtitle: l10n.securityUpgradePhraseSubtitle,
      footer: PrimaryButton(
        label: l10n.securityUpgradePhraseWritten,
        onPressed: context.read<SecurityUpgradeCubit>().acknowledgePhrase,
      ),
      children: [
        MnemonicWordGrid(words: words),
        const SizedBox(height: AppSpacing.section),
        WarningZone(
          title: l10n.securityUpgradePhraseWarningTitle,
          message: l10n.securityUpgradePhraseWarning,
        ),
      ],
    );
  }
}

class _ConfirmView extends StatefulWidget {
  const _ConfirmView({super.key, required this.state});

  final SecurityUpgradeConfirmPhrase state;

  @override
  State<_ConfirmView> createState() => _ConfirmViewState();
}

class _ConfirmViewState extends State<_ConfirmView> {
  late final _controllers = [
    for (final _ in widget.state.positions) TextEditingController(),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<SecurityUpgradeCubit>();
    return _Frame(
      title: l10n.securityUpgradeConfirmTitle,
      subtitle: l10n.securityUpgradeConfirmSubtitle,
      footer: PrimaryButton(
        label: l10n.securityUpgradeConfirmAction,
        onPressed: () => cubit.confirmPhrase([
          for (final controller in _controllers) controller.text.trim(),
        ]),
      ),
      children: [
        for (var i = 0; i < _controllers.length; i++) ...[
          OnboardingTextField(
            controller: _controllers[i],
            label: l10n.securityUpgradeConfirmWord(widget.state.positions[i]),
          ),
          const SizedBox(height: AppSpacing.fieldGap),
        ],
        if (widget.state.mismatch)
          Text(
            l10n.securityUpgradeConfirmMismatch,
            style: const TextStyle(color: AppColors.brandRed, fontSize: 12),
          ),
        TextButton(
          onPressed: cubit.backToPhrase,
          child: Text(l10n.securityUpgradeConfirmBack),
        ),
      ],
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.state});

  final SecurityUpgradeDone state;

  void _finish(BuildContext context) {
    // The biometric copy holds the previous master key; it is re-enrolled
    // explicitly from Security after the upgrade.
    getIt<BiometricKeyStore>().clear().catchError((_) {});
    context.read<AuthBloc>().add(
      VaultUnlocked(masterKey: state.masterKey, privateKey: state.privateKey),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Frame(
      title: l10n.securityUpgradeDoneTitle,
      subtitle: l10n.securityUpgradeDoneSubtitle,
      footer: PrimaryButton(
        label: l10n.securityUpgradeDoneAction,
        onPressed: () => _finish(context),
      ),
      children: [
        WarningZone(
          title: l10n.securityUpgradeDoneDevicesTitle,
          message: l10n.securityUpgradeDoneDevices,
        ),
      ],
    );
  }
}
