import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_screen.dart';
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

    return BlocBuilder<AgentsCubit, AgentsState>(
      builder: (context, state) {
        final total = state.agents.length;
        final showSummary = state.status == AgentsStatus.loaded && total > 0;
        return AppScreen.titled(
          title: l10n.agentsScreenTitle,
          subtitle: showSummary
              ? l10n.agentsListSummary(total, state.activeCount)
              : null,
          // Agents enroll from the CLI — no in-app add affordance; claim the
          // shell FAB with null so a covered page's FAB doesn't leak.
          floatingActionButton: const FabRegistrar(fab: null),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isSplit = constraints.maxWidth >= _kSplitBreakpoint;
              // The split view shows an inline detail pane; the narrow
              // layout pushes a full page, so any stale selection is
              // dropped when we shrink below the breakpoint.
              if (!isSplit && _selectedAgentId != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _selectedAgentId = null);
                  }
                });
              }
              final list = RefreshIndicator(
                color: AppColors.brandRed,
                backgroundColor: AppColors.cardSurface(brightness),
                onRefresh: () => context.read<AgentsCubit>().load(),
                child: _Body(
                  state: state,
                  selectedAgentId: isSplit ? _selectedAgentId : null,
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
                  Expanded(child: _SplitDetailPane(agentId: _selectedAgentId)),
                ],
              );
            },
          ),
        );
      },
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
        // Header→search gap (headerGap) is owned by the titled header;
        // search→content gap below is fieldGap.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.fieldGap,
          ),
          child: AppSearchField(
            controller: searchController,
            hint: l10n.agentsSearchHint,
          ),
        ),
        Expanded(
          child: switch (state.status) {
            AgentsStatus.initial ||
            AgentsStatus.loading => const _AgentsSkeleton(),
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
          SliverFillRemaining(hasScrollBody: false, child: _AgentsEmpty())
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              0,
              AppSpacing.screenH,
              AppSpacing.listBottom,
            ),
            sliver: SliverList.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.cardGap),
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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 32,
                color: AppColors.onSurfaceSubtle(brightness),
              ),
              const SizedBox(height: AppSpacing.fieldGap),
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
              content: Text(agentsErrorMessage(l10n, state.mutationError!)),
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
            // panel's split-view detail. Top gap (headerGap) is owned by
            // AppScreen.appBar above the split row.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                0,
                AppSpacing.screenH,
                0,
              ),
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
                onReactivate: () =>
                    context.read<AgentsCubit>().reactivateAgent(agent.agentId),
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
      // search → empty-state gap (fieldGap) is owned by the search bar above.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      // Column (mainAxisSize.max) absorbs the height that
      // SliverFillRemaining(hasScrollBody: false) stretches us to, keeping the
      // card at its natural size and pinned to the top, full width.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
              vertical: 28,
            ),
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
                const SizedBox(height: AppSpacing.fieldGap),
                Text(
                  l10n.agentsEmpty,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
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
      // search → first skeleton gap (fieldGap) is owned by the search bar.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      children: List.generate(
        4,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
          child: SkeletonBox(height: 66, delay: Duration(milliseconds: i * 80)),
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
      // search → error card gap (fieldGap) is owned by the search bar.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
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
              const SizedBox(height: AppSpacing.sm),
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
