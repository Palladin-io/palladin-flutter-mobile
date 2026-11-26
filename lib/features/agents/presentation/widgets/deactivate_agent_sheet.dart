import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../../core/widgets/confirmation_sheet.dart';

/// Confirmation bottom sheet shown before deactivating an active agent.
///
/// Resolves to `true` when the user confirms, `false` (or `null`) when
/// they cancel or dismiss without confirming.
class DeactivateAgentSheet extends StatelessWidget {
  const DeactivateAgentSheet({super.key, required this.agentName});

  final String agentName;

  static Future<bool> show(BuildContext context, String agentName) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DeactivateAgentSheet(agentName: agentName),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ConfirmationSheet(
      title: l10n.agentsDeactivateConfirmTitle,
      message: l10n.agentsDeactivateConfirmBody(agentName),
      confirmLabel: l10n.agentsDeactivate,
      cancelLabel: l10n.apiKeysCancel,
    );
  }
}
