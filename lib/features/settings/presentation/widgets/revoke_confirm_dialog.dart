import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Confirmation dialog shown before revoking an API key.
///
/// Resolves to `true` when the user confirms the (irreversible) revoke,
/// `false` (or `null`) when they cancel or dismiss it.
class RevokeConfirmDialog extends StatelessWidget {
  const RevokeConfirmDialog({super.key, required this.keyName});

  /// Name of the key being revoked — interpolated into the warning copy.
  final String keyName;

  /// Shows the dialog and returns the user's decision.
  static Future<bool> show(BuildContext context, String keyName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => RevokeConfirmDialog(keyName: keyName),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return AlertDialog(
      backgroundColor: AppColors.modalBackground(brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        l10n.settingsRevokeConfirmTitle,
        style: TextStyle(
          color: AppColors.onSurface(brightness),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        l10n.settingsRevokeConfirmBody(keyName),
        style: TextStyle(
          color: AppColors.onSurfaceMuted(brightness),
          fontSize: 13,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.onSurfaceSubtle(brightness),
          ),
          child: Text(l10n.settingsCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.brandRed,
          ),
          child: Text(
            l10n.settingsRevoke,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
