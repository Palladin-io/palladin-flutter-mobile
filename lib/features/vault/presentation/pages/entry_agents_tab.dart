import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../grants/presentation/widgets/context_grants_tab.dart';
import '../../domain/entities/entry_entity.dart';

/// Lists the grants that currently give agents access to this Entry.
///
/// Discovery visibility is intentionally configured beside each field on the
/// Details tab. This surface contains access records only; the host page owns
/// the add-grant FAB.
class EntryAgentsTab extends StatelessWidget {
  const EntryAgentsTab({
    super.key,
    required this.entry,
    required this.grantsRefresh,
    required this.onUpdated,
  });

  final EntryEntity entry;
  final int grantsRefresh;

  /// Retained for source compatibility with the detail host.
  final ValueChanged<EntryEntity> onUpdated;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ContextGrantsTab(
      key: ValueKey(grantsRefresh),
      entryId: entry.id,
      emptyTitle: l10n.entryAgentsEmptyTitle,
      emptyHint: l10n.entryAgentsEmptyHint,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.fieldGap,
        AppSpacing.screenH,
        AppSpacing.listBottom,
      ),
    );
  }
}
