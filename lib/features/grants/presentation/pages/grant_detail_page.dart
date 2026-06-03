import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../cubit/grant_detail_cubit.dart';
import '../widgets/grant_format.dart';
import '../widgets/grant_status_chip.dart';
import '../widgets/revoke_grant_sheet.dart';

/// Detail screen for a single grant — status, agent, target entry,
/// expiry / use limits, and key timestamps. Offers a revoke action for
/// active grants. Carries no crypto material.
class GrantDetailPage extends StatelessWidget {
  const GrantDetailPage({
    super.key,
    required this.vaultId,
    required this.grantId,
  });

  final String vaultId;
  final String grantId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<GrantDetailCubit>(
      create: (_) => getIt<GrantDetailCubit>(
        param1: vaultId,
        param2: grantId,
      )..load(),
      child: const _GrantDetailView(),
    );
  }
}

class _GrantDetailView extends StatelessWidget {
  const _GrantDetailView();

  Future<void> _onRevoke(BuildContext context, Grant grant) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await RevokeGrantSheet.show(
      context,
      grantAgentDisplayName(l10n, grant),
    );
    if (result == null || !context.mounted) return;
    await context.read<GrantDetailCubit>().revoke(reason: result.reason);
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
          titleSpacing: 0,
          iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
          title: Text(
            l10n.grantDetailTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: BlocConsumer<GrantDetailCubit, GrantDetailState>(
            listenWhen: (prev, curr) =>
                prev.revoked != curr.revoked ||
                (prev.mutationError != curr.mutationError &&
                    curr.mutationError != null),
            listener: (context, state) {
              if (state.revoked) {
                if (context.canPop()) context.pop();
                return;
              }
              if (state.mutationError != null) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    content:
                        Text(grantsErrorMessage(l10n, state.mutationError!)),
                  ));
                context.read<GrantDetailCubit>().acknowledgeMutationError();
              }
            },
            builder: (context, state) => switch (state.status) {
              GrantDetailStatus.initial ||
              GrantDetailStatus.loading =>
                const _DetailSkeleton(),
              GrantDetailStatus.error => _DetailError(
                  message: grantsErrorMessage(l10n, state.error!),
                  onRetry: () => context.read<GrantDetailCubit>().load(),
                ),
              GrantDetailStatus.loaded => _DetailBody(
                  grant: state.grant!,
                  isRevoking: state.isRevoking,
                  onRevoke: () => _onRevoke(context, state.grant!),
                ),
            },
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.grant,
    required this.isRevoking,
    required this.onRevoke,
  });

  final Grant grant;
  final bool isRevoking;
  final VoidCallback onRevoke;

  String _expiryLine(AppLocalizations l10n) {
    if (grant.expiresAt != null) {
      return l10n.grantDetailExpiresAt(_formatDate(grant.expiresAt!));
    }
    if (grant.queryLimit != null) {
      return l10n.grantDetailUsesLimit(grant.queryCount ?? 0, grant.queryLimit!);
    }
    return l10n.grantDetailNoExpiry;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final canRevoke = grant.status == GrantStatus.active ||
        grant.status == GrantStatus.pending;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _Section(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    grantAgentDisplayName(l10n, grant),
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                GrantStatusChip(status: grant.status),
              ],
            ),
            const SizedBox(height: 12),
            _Field(
              label: l10n.grantDetailScope,
              value: grantScopeLabel(l10n, grant.scope),
            ),
            _Field(
              label: l10n.grantDetailEntry,
              value: grant.scope == GrantScope.full
                  ? l10n.grantScopeFull
                  : (grant.entryLabel ?? l10n.grantEntryUnknown),
            ),
            _Field(
              label: l10n.grantDetailExpiry,
              value: _expiryLine(l10n),
            ),
          ],
        ),
        if (grant.reason != null && grant.reason!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          _Section(
            children: [
              Text(
                l10n.grantDetailReason,
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                grant.reason!.trim(),
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _Section(
          children: [
            _Field(
              label: l10n.grantDetailRequested,
              value: _formatDate(grant.createdAt),
            ),
            if (grant.approvedAt != null)
              _Field(
                label: l10n.grantDetailApproved,
                value: grant.approvedByName != null
                    ? l10n.grantDetailApprovedBy(
                        _formatDate(grant.approvedAt!),
                        grant.approvedByName!,
                      )
                    : _formatDate(grant.approvedAt!),
              ),
            if (grant.revokedAt != null)
              _Field(
                label: l10n.grantDetailRevoked,
                value: _formatDate(grant.revokedAt!),
              ),
          ],
        ),
        if (canRevoke) ...[
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: isRevoking ? null : onRevoke,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandRed,
              foregroundColor: AppColors.onBrandRed,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: isRevoking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onBrandRed,
                    ),
                  )
                : Text(
                    l10n.grantsRevoke,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}

/// Card-style section wrapper.
class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// Label + value row inside a section.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SkeletonBox(
            height: 110,
            delay: Duration(milliseconds: i * 80),
          ),
        ),
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return ListView(
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
                child: Text(l10n.grantsRetry),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Formats a local [DateTime] as `YYYY-MM-DD HH:MM`.
String _formatDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}
