import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../cubit/vault_detail_cubit.dart';

/// Vault detail screen — shows the vault header (icon, name, mode)
/// and placeholder sections for entries and agents (which will be
/// filled in by later tickets).
///
/// The settings cog navigates to `/vaults/:id/settings` for edit /
/// delete actions.
class VaultDetailPage extends StatelessWidget {
  const VaultDetailPage({super.key, required this.vaultId});

  final String vaultId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<VaultDetailCubit>(
      create: (_) => getIt<VaultDetailCubit>()..load(vaultId),
      child: _VaultDetailView(vaultId: vaultId),
    );
  }
}

class _VaultDetailView extends StatefulWidget {
  const _VaultDetailView({required this.vaultId});

  final String vaultId;

  @override
  State<_VaultDetailView> createState() => _VaultDetailViewState();
}

class _VaultDetailViewState extends State<_VaultDetailView> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.capture('vault', 'detail-viewed');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        title: BlocBuilder<VaultDetailCubit, VaultDetailState>(
          builder: (context, state) {
            if (state is VaultDetailLoaded) {
              return Text(state.vault.name);
            }
            return Text(l10n.vaultTitle);
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.vaultSettings,
            onPressed: () =>
                context.push('/vaults/${widget.vaultId}/settings'),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.darkBackgroundGradient,
        ),
        child: SafeArea(
          top: false,
          child: BlocBuilder<VaultDetailCubit, VaultDetailState>(
            builder: (context, state) {
              return switch (state) {
                VaultDetailInitial() ||
                VaultDetailLoading() =>
                  const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.tealAccent,
                    ),
                  ),
                VaultDetailDeleted() => const SizedBox.shrink(),
                VaultDetailError(:final kind) => _DetailError(kind: kind),
                VaultDetailLoaded(:final vault) => _DetailBody(vault: vault),
              };
            },
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.vault});

  final VaultEntity vault;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(vault: vault),
          const SizedBox(height: 24),
          _StatRow(vault: vault, l10n: l10n),
          const SizedBox(height: 32),
          _SectionTitle(title: l10n.vaultSectionEntries),
          const SizedBox(height: 12),
          _PlaceholderCard(
            icon: Icons.shield_outlined,
            title: l10n.vaultEntriesPlaceholderTitle,
            subtitle: l10n.vaultEntriesPlaceholderSubtitle,
          ),
          const SizedBox(height: 24),
          _SectionTitle(title: l10n.vaultSectionAgents),
          const SizedBox(height: 12),
          _PlaceholderCard(
            icon: Icons.smart_toy_outlined,
            title: l10n.vaultAgentsPlaceholderTitle,
            subtitle: l10n.vaultAgentsPlaceholderSubtitle,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.vault});

  final VaultEntity vault;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = _resolveAccentColor(vault.color);
    final isFull = vault.grantMode == GrantMode.full;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            vault.icon ?? '🔒',
            style: const TextStyle(fontSize: 28),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vault.name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              if (vault.description != null &&
                  vault.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  vault.description!,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isFull
                          ? AppColors.tealAccent
                          : AppColors.strengthFair)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (isFull
                            ? AppColors.tealAccent
                            : AppColors.strengthFair)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  (isFull ? l10n.vaultModeFull : l10n.vaultModeGranular)
                      .toUpperCase(),
                  style: TextStyle(
                    color: isFull
                        ? AppColors.tealAccent
                        : AppColors.strengthFair,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _resolveAccentColor(String? raw) {
    if (raw == null || raw.isEmpty) return AppColors.tealAccent;
    final cleaned = raw.startsWith('#') ? raw.substring(1) : raw;
    if (cleaned.length != 6) return AppColors.tealAccent;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return AppColors.tealAccent;
    return Color(0xFF000000 | value);
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.vault, required this.l10n});

  final VaultEntity vault;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            label: l10n.vaultStatEntries,
            value: vault.entryCount.toString(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatChip(
            label: l10n.vaultStatActiveGrants,
            value: vault.activeGrantCount.toString(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatChip(
            label: l10n.vaultStatMembers,
            value: vault.memberCount.toString(),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.textPrimary.withValues(alpha: 0.04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.textPrimary.withValues(alpha: 0.04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.textTertiary, size: 24),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.kind});

  final VaultErrorKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          switch (kind) {
            VaultErrorKind.notFound => l10n.vaultErrorNotFound,
            VaultErrorKind.forbidden => l10n.vaultErrorForbidden,
            VaultErrorKind.planLimitReached => l10n.vaultErrorPlanLimitReached,
            VaultErrorKind.fullModeNotAllowed =>
              l10n.vaultErrorFullModeNotAllowed,
            VaultErrorKind.networkError => l10n.errorCannotConnectToServer,
            VaultErrorKind.unknown => l10n.vaultErrorUnknown,
          },
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
