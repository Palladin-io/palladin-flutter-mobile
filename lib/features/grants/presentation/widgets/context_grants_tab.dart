import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../approval/presentation/widgets/regrant_sheet.dart';
import '../../../grants/presentation/widgets/revoke_grant_sheet.dart';
import '../../domain/entities/grant.dart';
import '../../domain/exceptions/grants_exceptions.dart';
import '../cubit/org_grants_cubit.dart';
import 'grant_format.dart';
import 'org_grant_card.dart';

/// Reusable grants list scoped to a single agent / vault / entry — the body of the
/// Agent→Grants, Vault→Agents and Entry→Agents detail tabs (CVT-120/132). Mirrors the web
/// `OrgGrantsPanel` filtered by `agentId` / `vaultId` / `entryId`: same `OrgGrantCard`, same
/// revoke / re-grant flow. Provides its own [OrgGrantsCubit] scoped to the given filter.
///
/// Exactly one of [agentId] / [vaultId] / [entryId] is expected.
class ContextGrantsTab extends StatelessWidget {
  const ContextGrantsTab({
    super.key,
    this.agentId,
    this.vaultId,
    this.entryId,
    required this.emptyTitle,
    required this.emptyHint,
    this.contentPadding = const EdgeInsets.fromLTRB(20, 4, 20, 96),
  });

  final String? agentId;
  final String? vaultId;
  final String? entryId;
  final String emptyTitle;
  final String emptyHint;

  /// List/empty padding. Defaults to the standard screen padding; pass zero
  /// horizontal when the host already provides it (e.g. the vault TabBarView).
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OrgGrantsCubit>(
      create: (_) => getIt<OrgGrantsCubit>()
        ..load(agentId: agentId, vaultId: vaultId, entryId: entryId),
      child: _ContextGrantsView(
        emptyTitle: emptyTitle,
        emptyHint: emptyHint,
        contentPadding: contentPadding,
      ),
    );
  }
}

class _ContextGrantsView extends StatelessWidget {
  const _ContextGrantsView({
    required this.emptyTitle,
    required this.emptyHint,
    required this.contentPadding,
  });

  final String emptyTitle;
  final String emptyHint;
  final EdgeInsets contentPadding;

  Future<void> _revoke(BuildContext context, Grant grant) async {
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<OrgGrantsCubit>();
    final result = await RevokeGrantSheet.show(
      context,
      grant.agentName?.trim().isNotEmpty == true
          ? grant.agentName!.trim()
          : l10n.grantUnnamedAgent,
    );
    if (result == null) return;
    await cubit.revokeGrant(grant.vaultId, grant.id, reason: result.reason);
  }

  Future<void> _regrant(BuildContext context, Grant grant) async {
    final cubit = context.read<OrgGrantsCubit>();
    final done = await RegrantSheet.show(context, grant);
    if (done == true) await cubit.reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return BlocConsumer<OrgGrantsCubit, OrgGrantsState>(
      listenWhen: (p, c) => p.mutationError != c.mutationError && c.mutationError != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(grantsErrorMessage(l10n, state.mutationError!))));
        context.read<OrgGrantsCubit>().acknowledgeMutationError();
      },
      builder: (context, state) {
        return switch (state.status) {
          OrgGrantsStatus.initial || OrgGrantsStatus.loading => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: AppColors.tealAccent),
              ),
            ),
          OrgGrantsStatus.error => _ErrorState(
              message: grantsErrorMessage(l10n, state.error ?? GrantsErrorKind.unknown),
              brightness: brightness,
              onRetry: () => context.read<OrgGrantsCubit>().reload(),
            ),
          OrgGrantsStatus.loaded => state.grants.isEmpty
              ? _EmptyState(
                  title: emptyTitle,
                  hint: emptyHint,
                  brightness: brightness,
                  padding: contentPadding,
                )
              : RefreshIndicator(
                  color: AppColors.tealAccent,
                  onRefresh: () => context.read<OrgGrantsCubit>().reload(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: contentPadding,
                    itemCount: state.grants.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => OrgGrantCard(
                      grant: state.grants[i],
                      isRevoking: state.revokingGrantId == state.grants[i].id,
                      onRevoke: () => _revoke(context, state.grants[i]),
                      onRegrant: () => _regrant(context, state.grants[i]),
                    ),
                  ),
                ),
        };
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.hint,
    required this.brightness,
    required this.padding,
  });

  final String title;
  final String hint;
  final Brightness brightness;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding.copyWith(top: 40),
      children: [
        Icon(Icons.key_off_outlined, size: 40, color: AppColors.onSurfaceSubtle(brightness)),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.onSurfaceMuted(brightness), fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.brightness, required this.onRetry});

  final String message;
  final Brightness brightness;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(color: AppColors.onSurfaceMuted(brightness), fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: Text(l10n.vaultRetry)),
        ],
      ),
    );
  }
}
