import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../cubit/onboarding_cubit.dart';
import '../widgets/onboarding_scaffold.dart';
import '../widgets/primary_button.dart';

/// Screen 2 of onboarding — displays the 24-word recovery mnemonic.
///
/// Offers copy-to-clipboard and share actions. The user must tap
/// "I've Saved My Recovery Key" to advance to the confirmation step.
///
/// Fires `mb:onboarding:recovery-key-page-viewed` on mount.
class RecoveryKeyBackupPage extends StatefulWidget {
  const RecoveryKeyBackupPage({super.key});

  @override
  State<RecoveryKeyBackupPage> createState() => _RecoveryKeyBackupPageState();
}

class _RecoveryKeyBackupPageState extends State<RecoveryKeyBackupPage> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.capture('onboarding', 'recovery-key-page-viewed');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mnemonic = context.select<OnboardingCubit, List<String>>(
      (c) => c.state.mnemonic,
    );

    return OnboardingScaffold(
      currentStep: 1,
      title: l10n.onboardingRecoveryTitle,
      subtitle: l10n.onboardingRecoverySubtitle,
      footer: PrimaryButton(
        label: l10n.onboardingRecoverySaved,
        onPressed: () => context.read<OnboardingCubit>().acknowledgeRecoveryBackup(),
      ),
      children: [
        _WarningBanner(message: l10n.onboardingRecoveryWarning),
        const SizedBox(height: 16),
        _MnemonicGrid(words: mnemonic),
        const SizedBox(height: 12),
        _SecondaryAction(
          icon: Icons.content_copy,
          label: l10n.onboardingRecoveryCopy,
          onPressed: () => _copyToClipboard(mnemonic, l10n),
        ),
        const SizedBox(height: 8),
        _SecondaryAction(
          icon: Icons.ios_share,
          label: l10n.onboardingRecoveryShare,
          onPressed: () => _share(mnemonic),
        ),
      ],
    );
  }

  Future<void> _copyToClipboard(List<String> words, AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: words.join(' ')));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.onboardingRecoveryCopied),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _share(List<String> words) async {
    await Share.share(words.join(' '));
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warningBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.brandRed, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MnemonicGrid extends StatelessWidget {
  const _MnemonicGrid({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: words.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.4,
      ),
      itemBuilder: (_, index) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.45),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  words[index],
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 16, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
