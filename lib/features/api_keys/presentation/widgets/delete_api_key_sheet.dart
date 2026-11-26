import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../../core/widgets/confirmation_sheet.dart';

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
    return ConfirmationSheet(
      title: l10n.apiKeysDeleteConfirmTitle,
      message: l10n.apiKeysDeleteConfirmBody(keyName),
      confirmLabel: l10n.apiKeysDeletePermanently,
      cancelLabel: l10n.apiKeysCancel,
    );
  }
}
