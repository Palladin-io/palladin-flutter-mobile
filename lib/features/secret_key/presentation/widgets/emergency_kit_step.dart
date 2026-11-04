import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../config/env_config.dart';
import '../../../../core/crypto/identity/secret_key_codec.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/services/emergency_kit_pdf_service.dart';
import '../emergency_kit_export.dart';

/// Mandatory "save your Emergency Kit" step shared by onboarding, the
/// security upgrade and account recovery. The caller owns [accountSecret].
class EmergencyKitStep extends StatefulWidget {
  const EmergencyKitStep({
    super.key,
    required this.email,
    required this.accountId,
    required this.accountSecret,
    required this.onContinue,
    this.pdfService,
    this.config,
  });

  final String email;
  final String accountId;
  final Uint8List accountSecret;
  final VoidCallback onContinue;
  final EmergencyKitPdfService? pdfService;
  final EnvConfig? config;

  @override
  State<EmergencyKitStep> createState() => _EmergencyKitStepState();
}

class _EmergencyKitStepState extends State<EmergencyKitStep> {
  bool _saving = false;
  bool _saved = false;
  bool _confirmed = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await exportEmergencyKit(
        context: context,
        service: widget.pdfService ?? getIt<EmergencyKitPdfService>(),
        config: widget.config ?? getIt<EnvConfig>(),
        email: widget.email,
        accountId: widget.accountId,
        accountSecret: widget.accountSecret,
      );
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      AppLogger.w('EmergencyKit', 'Export failed: ${error.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.emergencyKitSaveFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.headerGap,
              AppSpacing.screenH,
              AppSpacing.section,
            ),
            children: [
              Text(
                l10n.emergencyKitTitle,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.emergencyKitIntro,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              _FactorRow(
                icon: Icons.key_outlined,
                title: l10n.emergencyKitSecretKeyTitle,
                hint: l10n.emergencyKitSecretKeyHint,
              ),
              const SizedBox(height: AppSpacing.cardGap),
              _FactorRow(
                icon: Icons.password_outlined,
                title: l10n.emergencyKitRecoveryPhraseTitle,
                hint: l10n.emergencyKitRecoveryPhraseHint,
              ),
              const SizedBox(height: AppSpacing.section),
              _KitPreview(
                email: widget.email,
                secretKey: SecretKeyCodec.format(
                  widget.accountId,
                  widget.accountSecret,
                ),
              ),
              const SizedBox(height: AppSpacing.innerGap),
              Text(
                l10n.emergencyKitContents,
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              PrimaryButton(
                label: l10n.emergencyKitSave,
                leading: const Icon(Icons.ios_share, size: 18),
                isLoading: _saving,
                onPressed: _save,
              ),
              const SizedBox(height: AppSpacing.section),
              WarningZone(
                title: l10n.emergencyKitStoreSeparatelyTitle,
                message: l10n.emergencyKitStoreSeparatelyMessage,
              ),
            ],
          ),
        ),
        _Footer(
          confirmed: _confirmed,
          enabled: _saved,
          onConfirmed: (value) => setState(() => _confirmed = value),
          onContinue: _saved && _confirmed ? widget.onContinue : null,
        ),
      ],
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.brandRed, size: 20),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                hint,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KitPreview extends StatelessWidget {
  const _KitPreview({required this.email, required this.secretKey});

  final String email;
  final String secretKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final labelStyle = TextStyle(
      color: AppColors.onSurfaceSubtle(brightness),
      fontSize: 11,
    );
    final valueStyle = TextStyle(
      color: AppColors.onSurface(brightness),
      fontSize: 13,
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.emergencyKitPdfTitle,
            style: valueStyle.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(l10n.emergencyKitPreviewAccount, style: labelStyle),
          const SizedBox(height: AppSpacing.xxs),
          Text(email, style: valueStyle),
          const SizedBox(height: AppSpacing.innerGap),
          Text(l10n.emergencyKitSecretKeyTitle, style: labelStyle),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(
            secretKey,
            key: const ValueKey('emergencyKitSecretKey'),
            style: valueStyle.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          Text(l10n.emergencyKitPreviewPassword, style: labelStyle),
          const SizedBox(height: AppSpacing.xs),
          Container(
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.cardBorder(brightness)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.confirmed,
    required this.enabled,
    required this.onConfirmed,
    required this.onContinue,
  });

  final bool confirmed;
  final bool enabled;
  final ValueChanged<bool> onConfirmed;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        border: Border(top: BorderSide(color: AppColors.navBorder(brightness))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The footer fill sits between the tile and the page Material, so
          // the tile needs its own ink surface.
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              key: const ValueKey('emergencyKitSavedConfirm'),
              value: confirmed,
              onChanged: enabled
                  ? (value) => onConfirmed(value ?? false)
                  : null,
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.brandRed,
              title: Text(
                l10n.emergencyKitSavedConfirm,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            label: l10n.emergencyKitContinue,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}
