import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/agent.dart';
import '../bloc/agents_cubit.dart';
import '../widgets/agent_detail_body.dart';
import '../widgets/agent_format.dart';
import '../widgets/approve_agent_sheet.dart';
import '../widgets/deactivate_agent_sheet.dart';
import 'agent_edit_page.dart';

/// Standalone agent detail screen — pushed from the agents list on a
/// narrow layout (the wide layout shows the detail inline as a split
/// pane instead).
///
/// Owns its own [AgentsCubit], loads the agent list on mount and
/// resolves the requested agent by [agentId] from that list — so the
/// detail and list always agree.
class AgentDetailPage extends StatelessWidget {
  const AgentDetailPage({super.key, required this.agentId});

  /// Server-issued id of the agent to display.
  final String agentId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AgentsCubit>(
      create: (_) => getIt<AgentsCubit>()..load(),
      child: _AgentDetailView(agentId: agentId),
    );
  }
}

class _AgentDetailView extends StatelessWidget {
  const _AgentDetailView({required this.agentId});

  final String agentId;

  Future<void> _onApprove(BuildContext context, Agent agent) async {
    final result = await ApproveAgentSheet.show(context);
    if (result == null || !context.mounted) return;
    await context.read<AgentsCubit>().approveAgent(
          agent.agentId,
          name: result.name,
          type: result.type,
          iconKey: result.iconKey,
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

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient(brightness),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
          actions: [
            // The edit action is only useful for an agent that exists in
            // the loaded list — disabled while loading / on a missing id.
            // Pending agents have nothing editable yet, so the button is
            // hidden entirely until they are approved.
            BlocBuilder<AgentsCubit, AgentsState>(
              builder: (context, state) {
                final agent = state.agentById(agentId);
                if (agent != null && agent.isPending) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  tooltip: l10n.agentsEditIcon,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: agent == null
                      ? null
                      : () => AgentEditPage.push(context, agentId),
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Stack(
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
                        child: CircularProgressIndicator(
                          color: AppColors.brandRed,
                        ),
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
              const Positioned(
                width: 0,
                height: 0,
                child: FabRegistrar(fab: null),
              ),
            ],
          ),
        ),
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
    final brightness = Theme.of(context).brightness;
    final agent = context.select<AgentsCubit, Agent?>(
      (cubit) => cubit.state.agentById(agentId),
    );
    final name =
        agent == null ? l10n.agentsDetailTitle : agentDisplayName(l10n, agent);
    final statusLabel = switch (agent?.status) {
      AgentStatus.active => l10n.agentsStatusActive,
      AgentStatus.pending => l10n.agentsStatusPending,
      AgentStatus.deactivated => l10n.agentsStatusDeactivated,
      null => '',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (statusLabel.isNotEmpty)
          Text(
            statusLabel,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 11,
            ),
          ),
      ],
    );
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
        padding: const EdgeInsets.symmetric(horizontal: 32),
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
              const SizedBox(height: 8),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealAccent,
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
