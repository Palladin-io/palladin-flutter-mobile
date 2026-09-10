import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../core/widgets/primary_button.dart';

/// Confirmation bottom sheet shown before permanently deleting an API key.
///
/// Resolves to `true` when the user confirms, `false` (or `null`) when
/// they cancel or dismiss without confirming.
class DeleteApiKeySheet extends StatelessWidget {
  const DeleteApiKeySheet({super.key, required this.keyName});

  final String keyName;

  static Future<bool> show(BuildContext context, String keyName) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DeleteApiKeySheet(keyName: keyName),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.modalBackground(brightness),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.fieldGap,
            AppSpacing.screenH,
            AppSpacing.screenH,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetHandle(),
              const SizedBox(height: AppSpacing.xl),
              Text(
                l10n.apiKeysDeleteConfirmTitle,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.innerGap),
              Text(
                l10n.apiKeysDeleteConfirmBody(keyName),
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              PrimaryButton(
                label: l10n.apiKeysDeletePermanently,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: AppSpacing.innerGap),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onSurface(brightness),
                  side: BorderSide(color: AppColors.onSurface(brightness)),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  l10n.apiKeysCancel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
