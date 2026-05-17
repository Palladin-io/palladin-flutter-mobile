import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Confirmation dialog shown before permanently deleting an API key.
///
/// Resolves to `true` when the user confirms the (irreversible) delete,
/// `false` (or `null`) when they cancel or dismiss it.
class DeleteApiKeyDialog extends StatelessWidget {
  const DeleteApiKeyDialog({super.key, required this.keyName});

  /// Name of the key being deleted — interpolated into the warning copy.
  final String keyName;

  /// Shows the dialog and returns the user's decision.
  static Future<bool> show(BuildContext context, String keyName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => DeleteApiKeyDialog(keyName: keyName),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return AlertDialog(
      backgroundColor: AppColors.modalBackground(brightness),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        l10n.apiKeysDeleteConfirmTitle,
        style: TextStyle(
          color: AppColors.onSurface(brightness),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        l10n.apiKeysDeleteConfirmBody(keyName),
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
          child: Text(l10n.apiKeysCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppColors.brandRed),
          child: Text(
            l10n.apiKeysDeletePermanently,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
