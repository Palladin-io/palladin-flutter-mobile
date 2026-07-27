import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../grants/presentation/widgets/context_grants_tab.dart';
import '../../data/models/agent_discovery_provisioning.dart';
import '../cubit/agent_discovery_cubit.dart';

/// Combines encrypted Discovery provisioning health with scoped grants.
class VaultAgentsTab extends StatelessWidget {
  const VaultAgentsTab({super.key, required this.vaultId});

  final String vaultId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocProvider<AgentDiscoveryCubit>(
      create: (_) => getIt<AgentDiscoveryCubit>()..load(vaultId),
      child: Column(
        children: [
          _DiscoveryPanel(vaultId: vaultId),
          const SizedBox(height: AppSpacing.fieldGap),
          Expanded(
            child: ContextGrantsTab(
              vaultId: vaultId,
              emptyTitle: l10n.vaultAgentsEmptyTitle,
              emptyHint: l10n.vaultAgentsEmptyHint,
              contentPadding: const EdgeInsets.fromLTRB(
                0,
                0,
                0,
                AppSpacing.listBottom,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryPanel extends StatelessWidget {
  const _DiscoveryPanel({required this.vaultId});
  final String vaultId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        border: Border.all(color: AppColors.cardBorder(brightness)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.vaultDiscoveryTitle,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l10n.vaultDiscoveryAccessDisclaimer,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: AppSpacing.innerGap),
            BlocBuilder<AgentDiscoveryCubit, AgentDiscoveryState>(
              builder: (context, state) => switch (state) {
                AgentDiscoveryLoading() => const LinearProgressIndicator(
                  color: AppColors.brandRed,
                ),
                AgentDiscoveryError() => Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        context.read<AgentDiscoveryCubit>().load(vaultId),
                    child: Text(l10n.vaultRetry),
                  ),
                ),
                AgentDiscoveryLoaded(:final items, :final currentVdkVersion) =>
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.vaultDiscoveryVdkVersion(currentVdkVersion),
                        style: const TextStyle(
                          color: AppColors.textTertiaryMobile,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      if (items.isEmpty)
                        Text(
                          l10n.vaultDiscoveryNoActiveAgents,
                          style: const TextStyle(
                            color: AppColors.textTertiaryMobile,
                            fontSize: 12,
                          ),
                        )
                      else
                        Column(
                          children: items
                              .map((item) => _ProvisioningRow(item: item))
                              .toList(growable: false),
                        ),
                    ],
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProvisioningRow extends StatelessWidget {
  const _ProvisioningRow({required this.item});
  final AgentDiscoveryProvisioning item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final statusColor = item.isCurrent
        ? AppColors.positiveAccent
        : AppColors.premiumAmber;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Icon(Icons.smart_toy_outlined, size: 18, color: statusColor),
          const SizedBox(width: AppSpacing.chipGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.agentName?.trim().isNotEmpty == true
                      ? item.agentName!.trim()
                      : _shortId(item.agentId),
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  l10n.vaultDiscoveryKeyVersion(item.recipientKeyVersion),
                  style: const TextStyle(
                    color: AppColors.textTertiaryMobile,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            item.isCurrent
                ? l10n.vaultDiscoveryCurrent
                : l10n.vaultDiscoveryPending,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _shortId(String value) => value.length <= 15
      ? value
      : '${value.substring(0, 8)}…${value.substring(value.length - 6)}';
}
