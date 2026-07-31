import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../grants/presentation/widgets/context_grants_tab.dart';

/// Shows grants scoped to the current Vault.
class VaultAgentsTab extends StatelessWidget {
  const VaultAgentsTab({super.key, required this.vaultId});

  final String vaultId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ContextGrantsTab(
      vaultId: vaultId,
      emptyTitle: l10n.vaultAgentsEmptyTitle,
      emptyHint: l10n.vaultAgentsEmptyHint,
      contentPadding: const EdgeInsets.fromLTRB(0, 0, 0, AppSpacing.listBottom),
    );
  }
}
