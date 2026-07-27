import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/vault_member.dart';
import '../../domain/repositories/vault_members_repository.dart';
import '../cubit/vault_members_cubit.dart';

/// Vault Detail Members tab with server-owned staged removal progress.
class VaultMembersTab extends StatelessWidget {
  const VaultMembersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final currentUserId = auth is AuthAuthenticated ? auth.userId : null;
    final canRemove =
        auth is AuthAuthenticated &&
        (auth.permissions & Permissions.organizationManagement) != 0;
    return BlocConsumer<VaultMembersCubit, VaultMembersState>(
      listenWhen: (previous, current) =>
          previous.removalRequested != current.removalRequested ||
          previous.error != current.error,
      listener: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        if (state.removalRequested) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.vaultMemberRemovalStarted)),
          );
        } else if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_errorText(l10n, state.error!))),
          );
        }
      },
      builder: (context, state) {
        if (state.status == VaultMembersStatus.loading &&
            state.members.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.brandRed),
          );
        }
        if (state.status == VaultMembersStatus.error && state.members.isEmpty) {
          return _MembersError(
            onRetry: () => context.read<VaultMembersCubit>().load(),
          );
        }
        if (state.members.isEmpty) {
          return Center(
            child: Text(AppLocalizations.of(context)!.vaultMembersEmpty),
          );
        }
        return RefreshIndicator(
          onRefresh: () =>
              context.read<VaultMembersCubit>().load(preserveContent: true),
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: AppSpacing.listBottom),
            itemCount: state.members.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.cardGap),
            itemBuilder: (context, index) {
              final member = state.members[index];
              return _MemberCard(
                member: member,
                isCurrentUser: member.id == currentUserId,
                canRemove: canRemove,
                busy: state.removingMemberId == member.id,
              );
            },
          ),
        );
      },
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.isCurrentUser,
    required this.canRemove,
    required this.busy,
  });

  final VaultMember member;
  final bool isCurrentUser;
  final bool canRemove;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final l10n = AppLocalizations.of(context)!;
    final name = member.name?.isNotEmpty == true
        ? member.name!
        : _shortId(member.id);
    final removable =
        canRemove &&
        !isCurrentUser &&
        member.status == VaultMemberStatus.active &&
        !busy;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        border: Border.all(color: AppColors.cardBorder(brightness)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.vaultBlue.withValues(alpha: 0.16),
              foregroundColor: AppColors.vaultBlue,
              child: Text(name.characters.first.toUpperCase()),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCurrentUser ? '$name · ${l10n.vaultMemberYou}' : name,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _StatusLabel(status: member.status),
                ],
              ),
            ),
            if (busy)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (removable)
              IconButton(
                tooltip: l10n.vaultMemberRemove,
                icon: const Icon(Icons.person_remove_outlined),
                color: AppColors.brandRed,
                onPressed: () => _confirmRemoval(context, member, name),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemoval(
    BuildContext context,
    VaultMember member,
    String name,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.vaultMemberRemoveTitle),
        content: Text(l10n.vaultMemberRemoveBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.vaultCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.vaultMemberRemove),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<VaultMembersCubit>().requestRemoval(member);
    }
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});
  final VaultMemberStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (text, color) = switch (status) {
      VaultMemberStatus.active => (
        l10n.vaultMemberActive,
        AppColors.positiveAccent,
      ),
      VaultMemberStatus.pending => (
        l10n.vaultMemberPending,
        AppColors.vaultPeach,
      ),
      VaultMemberStatus.waitingForRotation => (
        l10n.vaultMemberRotating,
        AppColors.vaultBlue,
      ),
      VaultMemberStatus.blockedLastMember => (
        l10n.vaultMemberBlockedLast,
        AppColors.brandRed,
      ),
    };
    return Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    );
  }
}

class _MembersError extends StatelessWidget {
  const _MembersError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.vaultMembersLoadError),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.vaultRetry)),
        ],
      ),
    );
  }
}

String _shortId(String value) => value.length <= 15
    ? value
    : '${value.substring(0, 8)}…${value.substring(value.length - 6)}';

String _errorText(AppLocalizations l10n, VaultMembersErrorKind kind) =>
    switch (kind) {
      VaultMembersErrorKind.forbidden => l10n.vaultMemberForbidden,
      VaultMembersErrorKind.protectedMember => l10n.vaultMemberProtected,
      VaultMembersErrorKind.network => l10n.vaultMemberNetworkError,
      VaultMembersErrorKind.unknown => l10n.vaultMembersLoadError,
    };
