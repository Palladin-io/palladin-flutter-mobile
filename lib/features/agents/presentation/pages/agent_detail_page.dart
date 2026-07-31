import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/agent.dart';
import '../bloc/agents_cubit.dart';
import '../widgets/agent_detail_body.dart';
import '../widgets/agent_format.dart';
import '../widgets/approve_agent_sheet.dart';
import '../widgets/deactivate_agent_sheet.dart';

/// Standalone agent detail screen — pushed from the agents list on a
/// narrow layout (the wide layout shows the detail inline as a split
/// pane instead).
///
/// Shares the singleton [AgentsCubit] with [AgentsPage] via
/// [BlocProvider.value] so state changes (icon save, approve, deactivate)
/// are immediately visible in the list without a manual reload.
class AgentDetailPage extends StatefulWidget {
  const AgentDetailPage({super.key, required this.agentId});

  /// Server-issued id of the agent to display.
  final String agentId;

  @override
  State<AgentDetailPage> createState() => _AgentDetailPageState();
}

class _AgentDetailPageState extends State<AgentDetailPage> {
  @override
  void initState() {
    super.initState();
    // Load only when the singleton has never loaded — e.g. when the user
    // lands on this page via deep link without going through AgentsPage.
    final cubit = getIt<AgentsCubit>();
    if (cubit.state.status == AgentsStatus.initial) {
      cubit.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AgentsCubit>.value(
      value: getIt<AgentsCubit>(),
      child: _AgentDetailView(agentId: widget.agentId),
    );
  }
}

class _AgentDetailView extends StatelessWidget {
  const _AgentDetailView({required this.agentId});

  final String agentId;

  Future<void> _onApprove(BuildContext context, Agent agent) async {
    final result = await ApproveAgentSheet.show(
      context,
      initialName: agent.name,
      initialType: agent.type,
    );
    if (result == null || !context.mounted) return;
    await context.read<AgentsCubit>().approveAgent(
      agent.agentId,
      name: result.name,
      type: result.type,
      iconKey: result.iconKey,
      iconColor: result.iconColor,
    );
  }

  Future<void> _onDeactivate(BuildContext context, Agent agent) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await DeactivateAgentSheet.show(
      context,
      agentDisplayName(l10n, agent),
    );
    if (!confirmed || !context.mounted) return;
    await context.read<AgentsCubit>().deactivateAgent(agent.agentId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    // The shared AgentDetailBody owns the title→tabs (headerGap) gap so the
    // split-view pane and this pushed page have identical rhythm — hence
    // gapAfterHeader is left to the body here.
    return AppScreen.appBar(
      gapAfterHeader: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
        title: _AppBarTitle(agentId: agentId),
        // No edit action — the Details tab now hosts the edit form
        // inline, matching the web panel's split-view detail.
      ),
      body: Stack(
        children: [
          BlocConsumer<AgentsCubit, AgentsState>(
            // Surface a failed approve / deactivate / reactivate as a
            // snackbar so the agent card stays visible, then clear
            // the transient flag so it does not re-fire.
            listenWhen: (prev, curr) =>
                prev.mutationError != curr.mutationError &&
                curr.mutationError != null,
            listener: (context, state) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      agentsErrorMessage(l10n, state.mutationError!),
                    ),
                  ),
                );
              context.read<AgentsCubit>().acknowledgeMutationError();
            },
            builder: (context, state) {
              return switch (state.status) {
                AgentsStatus.initial || AgentsStatus.loading => const Center(
                  child: CircularProgressIndicator(color: AppColors.brandRed),
                ),
                AgentsStatus.error => _CenteredMessage(
                  message: agentsErrorMessage(l10n, state.error!),
                  onRetry: () => context.read<AgentsCubit>().load(),
                ),
                AgentsStatus.loaded => _LoadedBody(
                  agentId: agentId,
                  state: state,
                  onApprove: _onApprove,
                  onDeactivate: _onDeactivate,
                ),
              };
            },
          ),
          // Suppress any shell FAB on this screen.
          const Positioned(width: 0, height: 0, child: FabRegistrar(fab: null)),
        ],
      ),
    );
  }
}

/// Resolves the loaded agent and renders [AgentDetailBody], or a
/// not-found message when the agent is absent from the list.
class _LoadedBody extends StatelessWidget {
  const _LoadedBody({
    required this.agentId,
    required this.state,
    required this.onApprove,
    required this.onDeactivate,
  });

  final String agentId;
  final AgentsState state;
  final Future<void> Function(BuildContext, Agent) onApprove;
  final Future<void> Function(BuildContext, Agent) onDeactivate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final agent = state.agentById(agentId);
    if (agent == null) {
      return _CenteredMessage(message: l10n.agentsDetailNotFound);
    }
    return AgentDetailBody(
      agent: agent,
      isMutating: state.mutatingAgentId == agent.agentId,
      onApprove: () => onApprove(context, agent),
      onDeactivate: () => onDeactivate(context, agent),
      onReactivate: () =>
          context.read<AgentsCubit>().reactivateAgent(agent.agentId),
    );
  }
}

/// Resolves the agent name for the AppBar title, falling back to the
/// generic screen title while the list is still loading.
class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.agentId});

  final String agentId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final agent = context.select<AgentsCubit, Agent?>(
      (cubit) => cubit.state.agentById(agentId),
    );
    final name = agent == null
        ? l10n.agentsDetailTitle
        : agentDisplayName(l10n, agent);
    final statusLabel = switch (agent?.status) {
      AgentStatus.active => l10n.agentsStatusActive,
      AgentStatus.pending => l10n.agentsStatusPending,
      AgentStatus.deactivated => l10n.agentsStatusDeactivated,
      AgentStatus.deactivating => l10n.agentsDeactivating,
      null => '',
    };

    return AppBarTitle(title: name, subtitle: statusLabel);
  }
}

/// Centered message used for the error and not-found states, with an
/// optional retry affordance.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandRed,
                ),
                child: Text(l10n.agentsRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
