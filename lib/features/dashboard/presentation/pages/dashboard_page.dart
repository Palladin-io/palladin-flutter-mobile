import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../agents/presentation/widgets/approve_agent_sheet.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../cubit/dashboard_cubit.dart';
import '../widgets/onboarding_checklist.dart';
import '../widgets/unknown_agent_card.dart';

/// Home tab — replaces the post-unlock placeholder.
///
/// Shows one of three content states below a static greeting + search:
/// the onboarding checklist, an unknown-agent prompt, or the normal
/// (empty) dashboard. The [DashboardCubit] is a shell-lifetime singleton;
/// [load] runs on each mount to refresh after the user returns to the tab.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final DashboardCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = getIt<DashboardCubit>()..load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DashboardCubit>.value(
      value: _cubit,
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatefulWidget {
  const _DashboardView();

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onVaultCta() {
    context.read<DashboardCubit>().onVaultCtaTapped();
    context.go('/vaults');
  }

  void _onApiKeyCta() {
    context.read<DashboardCubit>().onApiKeyCtaTapped();
    final auth = context.read<AuthBloc>().state;
    final permissions = auth is AuthAuthenticated ? auth.permissions : 0;
    final canReadApiKeys = (permissions & Permissions.readApiKey) != 0;
    context.go(canReadApiKeys ? '/api-keys' : '/vaults');
  }

  void _onAgentCta() {
    context.read<DashboardCubit>().onAgentCtaTapped();
    context.go('/agents');
  }

  Future<void> _onRegisterApprove(PendingGrant grant) async {
    // Reuse the existing approve-agent sheet to capture the new agent's
    // name/type/icon. Full "register & approve" wiring (crypto envelope +
    // enrollment) is out of scope here — opening the sheet is the stub.
    await ApproveAgentSheet.show(
      context,
      initialName: grant.agentName,
    );
    if (!mounted) return;
    context.read<DashboardCubit>().load();
  }

  void _onReject(PendingGrant grant) {
    // Stub for now — rejection flow is tracked separately.
    // TODO(approvals): wire reject endpoint + remove from pending list.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthBloc>().state;
    final name = _displayName(auth);

    return AppScreen(
      header: _GreetingHeader(name: name),
      floatingActionButton: const FabRegistrar(fab: null),
      body: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) {
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    0,
                    AppSpacing.screenH,
                    AppSpacing.fieldGap,
                  ),
                  child: AppSearchField(
                    controller: _searchController,
                    hint: l10n.dashboardSearchHint,
                  ),
                ),
              ),
              ..._contentSlivers(context, state),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _contentSlivers(BuildContext context, DashboardState state) {
    return switch (state) {
      DashboardInitial() || DashboardLoading() => const [_SkeletonSliver()],
      DashboardOnboarding(:final status, :final notificationStepDone) => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.listBottom,
          ),
          sliver: SliverToBoxAdapter(
            child: OnboardingChecklist(
              status: status,
              notificationStepDone: notificationStepDone,
              onSkipSetup: () => context.read<DashboardCubit>().skipSetup(),
              onEnableNotifications: () =>
                  context.read<DashboardCubit>().enableNotifications(),
              onSkipNotification: () =>
                  context.read<DashboardCubit>().skipNotificationStep(),
              onVaultCta: _onVaultCta,
              onApiKeyCta: _onApiKeyCta,
              onAgentCta: _onAgentCta,
            ),
          ),
        ),
      ],
      DashboardUnknownAgent(:final grant) => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.listBottom,
          ),
          sliver: SliverList.list(
            children: [
              _SectionHeader(
                title: AppLocalizations.of(context)!.dashboardPendingApprovals,
                badge: '1',
              ),
              const SizedBox(height: AppSpacing.cardGap),
              UnknownAgentCard(
                grant: grant,
                onRegisterApprove: () => _onRegisterApprove(grant),
                onReject: () => _onReject(grant),
              ),
              const SizedBox(height: AppSpacing.section),
              _SectionHeader(
                title: AppLocalizations.of(context)!.dashboardRecentActivity,
              ),
              const SizedBox(height: AppSpacing.cardGap),
              const _ActivityEmpty(),
            ],
          ),
        ),
      ],
      DashboardLoaded() => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.listBottom,
          ),
          sliver: SliverList.list(
            children: [
              _SectionHeader(
                title: AppLocalizations.of(context)!.dashboardRecentActivity,
              ),
              const SizedBox(height: AppSpacing.cardGap),
              const _ActivityEmpty(),
            ],
          ),
        ),
      ],
      DashboardError() => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorView(
            onRetry: () => context.read<DashboardCubit>().load(),
          ),
        ),
      ],
    };
  }

  String _displayName(AuthState state) {
    if (state is AuthAuthenticated &&
        state.email != null &&
        state.email!.isNotEmpty) {
      final local = state.email!.split('@').first;
      if (local.isEmpty) return '';
      return local[0].toUpperCase() + local.substring(1);
    }
    return '';
  }
}

/// Greeting header (rendered above the search bar) — "Good morning" over
/// the user's name, with a bell that opens the inbox.
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.headerGap,
        AppSpacing.screenH,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.dashboardGoodMorning,
                  style: TextStyle(
                    color: AppColors.onSurfaceSubtle(brightness),
                    fontSize: 13,
                  ),
                ),
                if (name.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    name,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => context.go('/inbox'),
            icon: Icon(
              Icons.notifications_outlined,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
            tooltip: l10n.navInbox,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.badge});

  final String title;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: AppSpacing.chipGap),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.chipGap,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.brandRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: AppColors.brandRed,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        Text(
          l10n.dashboardSeeAll,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          Icon(
            Icons.history,
            size: 28,
            color: AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.3),
          ),
          const SizedBox(height: AppSpacing.chipGap),
          Text(
            l10n.dashboardNoActivity,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonSliver extends StatelessWidget {
  const _SkeletonSliver();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.listBottom,
      ),
      sliver: SliverList.separated(
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.cardGap),
        itemBuilder: (_, index) => SkeletonBox(
          height: index == 0 ? 96 : 84,
          delay: Duration(milliseconds: index * 80),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.brandRed, size: 40),
            const SizedBox(height: AppSpacing.section),
            Text(
              l10n.errorCannotConnectToServer,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.tealAccent,
              ),
              child: Text(l10n.vaultRetry),
            ),
          ],
        ),
      ),
    );
  }
}
