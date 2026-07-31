import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/secure_clipboard.dart';
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
  final _exportButtonKey = GlobalKey();

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
      onBack: () => context.read<OnboardingCubit>().goBack(),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SecondaryAction(
            icon: Icons.content_copy,
            label: l10n.onboardingRecoveryCopy,
            onPressed: () => _copyToClipboard(mnemonic, l10n),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          _SecondaryAction(
            key: _exportButtonKey,
            icon: Icons.file_download_outlined,
            label: l10n.onboardingRecoveryExport,
            onPressed: () => _exportToFile(mnemonic),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          PrimaryButton(
            label: l10n.onboardingRecoverySaved,
            onPressed: () =>
                context.read<OnboardingCubit>().acknowledgeRecoveryBackup(),
          ),
        ],
      ),
      children: [
        _WarningBanner(message: l10n.onboardingRecoveryWarning),
        const SizedBox(height: AppSpacing.section),
        _MnemonicGrid(words: mnemonic),
      ],
    );
  }

  Future<void> _copyToClipboard(
    List<String> words,
    AppLocalizations l10n,
  ) async {
    await SecureClipboard.copy(words.join(' '));
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

  Future<void> _exportToFile(List<String> words) async {
    final l10n = AppLocalizations.of(context)!;
    final box =
        _exportButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero;

    final content = words
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');

    // Hand the recovery key to share_plus as in-memory bytes via
    // XFile.fromData so we never write a predictably-named file into
    // the temp directory ourselves. share_plus may spill a temporary
    // file into the app's cache sandbox under a UUID name — the OS
    // manages cleanup of that cache.
    //
    // We use fileNameOverrides (rather than XFile.fromData.name, which
    // is ignored on most platforms) so the recipient sees a friendly
    // filename.
    final bytes = Uint8List.fromList(utf8.encode(content));
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'text/plain')],
      fileNameOverrides: const ['palladin-recovery-key.txt'],
      subject: l10n.recoveryShareSubject,
      sharePositionOrigin: origin,
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.warningBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.brandRed,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.innerGap),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.onSurface(brightness),
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
    final brightness = Theme.of(context).brightness;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: words.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.innerGap,
        mainAxisSpacing: AppSpacing.innerGap,
        childAspectRatio: 4.8,
      ),
      itemBuilder: (_, index) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.innerGap),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder(brightness)),
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
                    color: AppColors.onSurfaceSubtle(brightness),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  words[index],
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurface(brightness),
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
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final foreground = AppColors.onSurface(brightness);
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 16, color: foreground),
        label: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: BorderSide(color: AppColors.cardBorder(brightness)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
