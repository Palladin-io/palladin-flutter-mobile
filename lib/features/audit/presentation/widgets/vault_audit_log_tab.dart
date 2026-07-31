import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../cubit/audit_log_cubit.dart';
import 'audit_log_content.dart';

/// The vault-detail **Logs** tab.
///
/// Read-only, filterable audit feed scoped to a single vault: search bar with
/// a `tune` filter trigger (agent + date range), group quick-filter chips and
/// expandable audit rows with cursor pagination. Provides its own
/// [AuditLogCubit] scoped to [vaultId].
class VaultAuditLogTab extends StatelessWidget {
  const VaultAuditLogTab({
    super.key,
    required this.vaultId,
    this.contentPadding = const EdgeInsets.fromLTRB(
      AppSpacing.screenH,
      AppSpacing.fieldGap,
      AppSpacing.screenH,
      AppSpacing.listBottom,
    ),
  });

  final String vaultId;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuditLogCubit>(
      create: (_) => getIt<AuditLogCubit>(param1: vaultId)..load(),
      child: AuditLogContent(
        groups: AuditEventType.vaultGroups,
        showVaultFilter: false,
        contentPadding: contentPadding,
      ),
    );
  }
}
