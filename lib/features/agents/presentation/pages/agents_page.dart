import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/agent.dart';
import '../bloc/agents_cubit.dart';
import '../widgets/agent_card.dart';
import '../widgets/agent_detail_body.dart';
import '../widgets/agent_format.dart';
import '../widgets/approve_agent_sheet.dart';
import '../widgets/deactivate_agent_sheet.dart';
import 'agent_detail_page.dart';

/// Standalone agents screen — the list of every agent for the
/// organization.
///
/// Reached from the bottom-nav "Agents" tab.
///
/// Provides the singleton [AgentsCubit] via [BlocProvider.value] so the
/// provider never takes ownership (and never calls [close]) when the
/// user switches tabs. [load] is triggered only on the first mount —
/// subsequent tab returns reuse the in-memory state; pull-to-refresh
/// handles explicit refresh.
///
/// Layout adapts to the available width: on a narrow phone the list
/// fills the screen and tapping a row pushes [AgentDetailPage]; on a
/// wide screen (tablet / landscape) a split view shows the master list
/// on the left and the selected agent's detail in a pane on the right.
class AgentsPage extends StatefulWidget {
  const AgentsPage({super.key});

  @override
  State<AgentsPage> createState() => _AgentsPageInitState();
}

class _AgentsPageInitState extends State<AgentsPage> {
  @override
  void initState() {
    super.initState();
    // First open loads (skeleton); returning to the tab does a quiet refresh
    // so the list reflects agents enrolled meanwhile (mobile has no SignalR —
    // staleness is corrected on focus, on app resume, and on push).
    getIt<AgentsCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AgentsCubit>.value(
      value: getIt<AgentsCubit>(),
      child: const _AgentsView(),
    );
  }
}

/// Width at or above which the split view kicks in.
const double _kSplitBreakpoint = 720;

class _AgentsView extends StatefulWidget {
  const _AgentsView();

  @override
  State<_AgentsView> createState() => _AgentsViewState();
}

class _AgentsViewState extends State<_AgentsView> {
  /// Agent currently open in the split-view detail pane. Always `null`
  /// on a narrow layout — that layout pushes a full page instead.
  String? _selectedAgentId;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text.trim();
      if (next == _query) return;
      setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Agent> _filter(List<Agent> agents) {
    if (_query.isEmpty) return agents;
    final needle = _query.toLowerCase();
    return agents
        .where((a) => (a.name ?? '').toLowerCase().contains(needle))
        .toList(growable: false);
  }

  /// Opens [agentId]. On a wide layout the selection updates the inline
  /// detail pane; on a narrow layout it pushes [AgentDetailPage]. Both
  /// layouts share the singleton [AgentsCubit] so list updates are
  /// immediate — no explicit reload on return is needed.
  Future<void> _openAgent(String agentId, bool isSplit) async {
    if (isSplit) {
      setState(() => _selectedAgentId = agentId);
      return;
    }
    await context.push('/agents/$agentId');
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
          title: BlocBuilder<AgentsCubit, AgentsState>(
            builder: (context, state) {
              final brightness = Theme.of(context).brightness;
              final total = state.agents.length;
              final showSummary =
                  state.status == AgentsStatus.loaded && total > 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.agentsScreenTitle,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  if (showSummary) ...[
                    const SizedBox(height: 3),
                    Text(
                      l10n.agentsListSummary(total, state.activeCount),
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isSplit =
                      constraints.maxWidth >= _kSplitBreakpoint;
                  // The split view shows an inline detail pane; the
                  // narrow layout pushes a full page, so any stale
                  // selection is dropped when we shrink below the
                  // breakpoint.
                  if (!isSplit && _selectedAgentId != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _selectedAgentId = null);
                      }
                    });
                  }
                  return BlocBuilder<AgentsCubit, AgentsState>(
                    builder: (context, state) {
                      final list = RefreshIndicator(
                        color: AppColors.brandRed,
                        backgroundColor:
                            AppColors.cardSurface(brightness),
                        onRefresh: () =>
                            context.read<AgentsCubit>().load(),
                        child: _Body(
                          state: state,
                          selectedAgentId:
                              isSplit ? _selectedAgentId : null,
                          onOpenAgent: (id) => _openAgent(id, isSplit),
                          searchController: _searchController,
                          filtered: _filter(state.agents),
                        ),
                      );
                      if (!isSplit) return list;
                      return Row(
                        children: [
                          SizedBox(width: 340, child: list),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: AppColors.navBorder(brightness),
                          ),
                          Expanded(
                            child: _SplitDetailPane(
                              agentId: _selectedAgentId,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              // Suppress any shell FAB — agents enroll from the CLI, so
              // there is no in-app "add" affordance.
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

/// Switches between the loading / error / empty / loaded states of the
/// agents list.
///
/// The search bar is static chrome — it stays mounted above the content
/// area in every state (including loading), per the skeleton-pattern
/// rule. Only the area below the search bar swaps to a skeleton, error
/// card, empty state or the agent list. Each content view is itself
/// scrollable so [RefreshIndicator] keeps working in all states.
class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.selectedAgentId,
    required this.onOpenAgent,
    required this.searchController,
    required this.filtered,
  });

  final AgentsState state;
  final String? selectedAgentId;
  final ValueChanged<String> onOpenAgent;
  final TextEditingController searchController;
  final List<Agent> filtered;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: AppSearchField(
            controller: searchController,
            hint: l10n.agentsSearchHint,
          ),
        ),
        Expanded(
          child: switch (state.status) {
            AgentsStatus.initial ||
            AgentsStatus.loading =>
              const _AgentsSkeleton(),
            AgentsStatus.error => _AgentsError(
                message: agentsErrorMessage(l10n, state.error!),
                onRetry: () => context.read<AgentsCubit>().load(),
              ),
            AgentsStatus.loaded => _AgentsList(
                agents: state.agents,
                filtered: filtered,
                selectedAgentId: selectedAgentId,
                onOpenAgent: onOpenAgent,
              ),
          },
        ),
      ],
    );
  }
}

class _AgentsList extends StatelessWidget {
  const _AgentsList({
    required this.agents,
    required this.filtered,
    required this.selectedAgentId,
    required this.onOpenAgent,
  });

  final List<Agent> agents;
  final List<Agent> filtered;
  final String? selectedAgentId;
  final ValueChanged<String> onOpenAgent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (agents.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _AgentsEmpty(),
          )
        else if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                l10n.agentsSearchEmpty,
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 13,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
            sliver: SliverList.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final agent = filtered[index];
                return AgentCard(
                  agent: agent,
                  selected: agent.agentId == selectedAgentId,
                  onTap: () => onOpenAgent(agent.agentId),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Detail pane of the split view — resolves the selected agent from the
/// [AgentsCubit] and renders [AgentDetailBody], or a prompt when nothing
/// is selected yet.
class _SplitDetailPane extends StatelessWidget {
  const _SplitDetailPane({required this.agentId});

  final String? agentId;

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

    if (agentId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 32,
                color: AppColors.onSurfaceSubtle(brightness),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.agentsSplitPrompt,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return BlocConsumer<AgentsCubit, AgentsState>(
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
        final agent = state.agentById(agentId!);
        if (agent == null) {
          return Center(
            child: Text(
              l10n.agentsDetailNotFound,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
              ),
            ),
          );
        }
        return Column(
          children: [
            // Pane title — agent name only. The edit affordance now
            // lives inline inside the Details tab, matching the web
            // panel's split-view detail.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      agentDisplayName(l10n, agent),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AgentDetailBody(
                agent: agent,
                isMutating: state.mutatingAgentId == agent.agentId,
                onApprove: () => _onApprove(context, agent),
                onDeactivate: () => _onDeactivate(context, agent),
                onReactivate: () => context
                    .read<AgentsCubit>()
                    .reactivateAgent(agent.agentId),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Empty-state for the agents list.
class _AgentsEmpty extends StatelessWidget {
  const _AgentsEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    // Non-scrollable content: this sits inside the list's
    // SliverFillRemaining(hasScrollBody: false), and the parent
    // CustomScrollView (AlwaysScrollableScrollPhysics) already drives
    // pull-to-refresh. A nested ListView here gets unbounded height and
    // throws a viewport layout exception.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      // Column (mainAxisSize.max) absorbs the height that
      // SliverFillRemaining(hasScrollBody: false) stretches us to, keeping the
      // card at its natural size and pinned to the top, full width.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.cardFill(brightness),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder(brightness)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  size: 32,
                  color: AppColors.onSurfaceSubtle(brightness),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.agentsEmpty,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.agentsEmptyHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.onSurfaceSubtle(brightness),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated skeleton placeholder shown while the agents list loads.
class _AgentsSkeleton extends StatelessWidget {
  const _AgentsSkeleton();

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
            height: 66,
            delay: Duration(milliseconds: i * 80),
          ),
        ),
      ),
    );
  }
}

/// Inline error card for a failed agents-list load, with a retry button.
class _AgentsError extends StatelessWidget {
  const _AgentsError({required this.message, required this.onRetry});

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
                child: Text(l10n.agentsRetry),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
