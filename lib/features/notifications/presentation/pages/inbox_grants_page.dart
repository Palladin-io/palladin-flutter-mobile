import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../grants/presentation/widgets/context_grants_tab.dart';

/// Full-screen org-wide grants list, reached from the Inbox kebab menu.
///
/// This is the inbox's only **mutable** surface — the notification log itself
/// is immutable. It reuses [ContextGrantsTab] with no agent/vault/entry filter,
/// so it shows every org grant with live state and inline Revoke / re-grant,
/// without duplicating any list/card logic.
class InboxGrantsPage extends StatelessWidget {
  const InboxGrantsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient(brightness),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          centerTitle: false,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          titleSpacing: 0,
          iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
          title: Text(
            l10n.inboxGrantsMenu,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ContextGrantsTab(
            emptyTitle: l10n.inboxGrantsEmpty,
            emptyHint: l10n.inboxGrantsEmptyHint,
          ),
        ),
      ),
    );
  }
}
