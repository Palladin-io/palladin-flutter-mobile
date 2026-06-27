import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../cubit/audit_log_cubit.dart';
import '../widgets/audit_legend_sheet.dart';
import '../widgets/audit_log_content.dart';

/// Org-wide audit Logs screen (CVT-66).
///
/// Reached from the settings drawer's "Audit" item. Shows every audit event
/// across the organization with group quick-filter chips, a `tune` filter
/// sheet (vault + agent + date range), free-text search and a colour/icon
/// legend modal. Pushed full-screen, so the AppBar carries a back arrow.
class GlobalAuditLogPage extends StatelessWidget {
  const GlobalAuditLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuditLogCubit>(
      create: (_) => getIt<AuditLogCubit>(param1: null)..load(),
      child: const _GlobalAuditLogView(),
    );
  }
}

class _GlobalAuditLogView extends StatelessWidget {
  const _GlobalAuditLogView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    // Title→content gap (headerGap) is owned by AppScreen.appBar.
    return AppScreen.appBar(
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleSpacing: 0,
        iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
        title: Text(
          l10n.auditScreenTitle,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: l10n.auditLegendTitle,
            icon: Icon(
              Icons.info_outline,
              size: 20,
              color: AppColors.onSurfaceMuted(brightness),
            ),
            onPressed: () => AuditLegendSheet.show(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          const AuditLogContent(
            groups: AuditEventType.orgGroups,
            showVaultFilter: true,
            // Title→content gap (headerGap) is owned by AppScreen.appBar, so
            // the content starts flush at the top.
            contentPadding: EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              0,
              AppSpacing.screenH,
              AppSpacing.listBottom,
            ),
          ),
          // Claim the shell FAB slot with `null` so no FAB leaks from the
          // page we were pushed over.
          const Positioned(width: 0, height: 0, child: FabRegistrar(fab: null)),
        ],
      ),
    );
  }
}
