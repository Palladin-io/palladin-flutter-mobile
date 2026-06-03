import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../cubit/pending_grants_cubit.dart';
import '../widgets/approval_format.dart';
import 'grant_approval_page.dart';

/// Cross-vault approval inbox — every pending grant request awaiting the
/// owner. Tapping a request opens the approve/deny screen.
class PendingGrantsPage extends StatelessWidget {
  const PendingGrantsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PendingGrantsCubit>(
      create: (_) => getIt<PendingGrantsCubit>()..load(),
      child: const _PendingGrantsView(),
    );
  }
}

class _PendingGrantsView extends StatelessWidget {
  const _PendingGrantsView();

  Future<void> _openApproval(BuildContext context, PendingGrant grant) async {
    final cubit = context.read<PendingGrantsCubit>();
    final handled = await GrantApprovalPage.push(context, grant);
    // The approval screen returns `true` when the grant was approved or
    // denied — drop it from the inbox so it disappears immediately.
    if (handled == true) {
      cubit.removeGrant(grant.grantId);
    }
  }

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
          titleSpacing: 20,
          iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
          title: Text(
            l10n.approvalInboxTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            color: AppColors.brandRed,
            backgroundColor: AppColors.cardSurface(brightness),
            onRefresh: () => context.read<PendingGrantsCubit>().load(),
            child: BlocBuilder<PendingGrantsCubit, PendingGrantsState>(
              builder: (context, state) => switch (state.status) {
                PendingGrantsStatus.initial ||
                PendingGrantsStatus.loading =>
                  const _Skeleton(),
                PendingGrantsStatus.error => _ErrorView(
                    message: approvalErrorMessage(l10n, state.error!),
                    onRetry: () => context.read<PendingGrantsCubit>().load(),
                  ),
                PendingGrantsStatus.loaded => _List(
                    grants: state.grants,
                    onOpen: (g) => _openApproval(context, g),
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.grants, required this.onOpen});

  final List<PendingGrant> grants;
  final ValueChanged<PendingGrant> onOpen;

  @override
  Widget build(BuildContext context) {
    if (grants.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: const [_Empty()],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      itemCount: grants.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _PendingCard(grant: grants[i], onTap: () => onOpen(grants[i])),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.grant, required this.onTap});

  final PendingGrant grant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder(brightness)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pendingAgentDisplayName(l10n, grant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.approvalCardRequest(
                  pendingEntryLabel(l10n, grant),
                  grant.vaultName ?? l10n.approvalVaultUnknown,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 12,
                ),
              ),
              if (grant.reason != null && grant.reason!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  grant.reason!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.onSurfaceSubtle(brightness),
                    fontSize: 12,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 32,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.approvalInboxEmpty,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.approvalInboxEmptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: List.generate(
        4,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SkeletonBox(
            height: 84,
            delay: Duration(milliseconds: i * 80),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder(brightness)),
          ),
          child: Column(
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealAccent,
                ),
                child: Text(l10n.approvalRetry),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
