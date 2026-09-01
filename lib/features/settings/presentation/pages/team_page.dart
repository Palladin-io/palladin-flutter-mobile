import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../shell/presentation/pages/app_shell.dart';
import '../../domain/entities/organization_management.dart';
import '../../domain/exceptions/settings_exceptions.dart';
import '../bloc/settings_cubit.dart';
import '../bloc/team_cubit.dart';
import '../widgets/settings_error_text.dart';

class TeamPage extends StatelessWidget {
  const TeamPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final permissions = auth is AuthAuthenticated ? auth.permissions : 0;
    return BlocProvider<TeamCubit>(
      create: (_) => getIt<TeamCubit>()
        ..load(
          canInvite: (permissions & Permissions.addUser) != 0,
          canManage: (permissions & Permissions.organizationManagement) != 0,
        ),
      child: _TeamView(permissions: permissions),
    );
  }
}

class _TeamView extends StatefulWidget {
  const _TeamView({required this.permissions});

  final int permissions;

  @override
  State<_TeamView> createState() => _TeamViewState();
}

class _TeamViewState extends State<_TeamView> {
  final _searchController = TextEditingController();
  bool _filtersOpen = false;
  bool _showMembers = true;
  bool _showPending = true;
  bool _inviteSheetOpen = false;
  Widget? _cachedFab;

  bool get _canInvite => (widget.permissions & Permissions.addUser) != 0;
  bool get _canManage =>
      (widget.permissions & Permissions.organizationManagement) != 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openMember(String userId) async {
    await context.push(AppRoutes.settingsTeamMember(userId));
    if (mounted) {
      await context.read<TeamCubit>().load(
        canInvite: _canInvite,
        canManage: _canManage,
      );
    }
  }

  Future<void> _openInvitation(String invitationId) async {
    await context.push(AppRoutes.settingsTeamInvitation(invitationId));
    if (mounted) {
      await context.read<TeamCubit>().load(
        canInvite: _canInvite,
        canManage: _canManage,
      );
    }
  }

  Future<void> _openInvite() async {
    if (_inviteSheetOpen) return;
    setState(() => _inviteSheetOpen = true);
    final result = await InviteMemberSheet.show(context);
    if (!mounted) return;
    setState(() => _inviteSheetOpen = false);

    final cubit = context.read<TeamCubit>();
    final state = cubit.state;
    if (state.completedAction == TeamAction.invite) {
      _showActionMessage(context, state);
    } else if (state.actionError != null) {
      // The sheet already rendered the failure inline. Do not replay it as a
      // snackbar after the user dismisses the draft.
      cubit.acknowledgeActionResult();
    }

    if (result == InviteMemberSheetResult.manageSeats && mounted) {
      await context.push(AppRoutes.settingsBilling);
    }
  }

  void _showActionMessage(BuildContext context, TeamState state) {
    // Invite errors belong to the root modal so they remain visible beside
    // the draft. A snackbar here would be obscured by that modal.
    if (_inviteSheetOpen) return;
    final l10n = AppLocalizations.of(context)!;
    final message = state.actionError != null
        ? settingsErrorMessage(l10n, state.actionError!)
        : switch (state.completedAction) {
            TeamAction.invite => l10n.teamInvitationSent,
            TeamAction.cancelInvitation => l10n.teamInvitationCancelled,
            TeamAction.resendInvitation => l10n.teamInvitationResent,
            TeamAction.updateInvitationRole => l10n.teamInvitationRoleUpdated,
            TeamAction.updateMemberRoles => l10n.teamMemberRolesUpdated,
            null => null,
          };
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    context.read<TeamCubit>().acknowledgeActionResult();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final fab = _canInvite
        ? (_cachedFab ??= Padding(
            padding: const EdgeInsets.only(
              bottom: AppSpacing.innerGap,
              right: AppSpacing.xs,
            ),
            child: AppFab(tooltip: l10n.teamInvite, onPressed: _openInvite),
          ))
        : null;

    return BlocListener<TeamCubit, TeamState>(
      listenWhen: (previous, current) =>
          previous.actionError != current.actionError ||
          previous.completedAction != current.completedAction,
      listener: _showActionMessage,
      child: AppScreen.appBar(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
          title: AppBarTitle(
            title: l10n.teamScreenTitle,
            subtitle: l10n.teamScreenSubtitle,
          ),
        ),
        body: Stack(
          children: [
            BlocBuilder<TeamCubit, TeamState>(
              builder: (context, state) => RefreshIndicator(
                color: AppColors.brandRed,
                backgroundColor: AppColors.cardSurface(brightness),
                onRefresh: () => context.read<TeamCubit>().load(
                  canInvite: _canInvite,
                  canManage: _canManage,
                ),
                child: _buildScroll(context, state),
              ),
            ),
            Positioned(width: 0, height: 0, child: FabRegistrar(fab: fab)),
          ],
        ),
      ),
    );
  }

  Widget _buildScroll(BuildContext context, TeamState state) {
    final l10n = AppLocalizations.of(context)!;
    final query = _searchController.text.trim().toLowerCase();
    final entries = <_TeamEntry>[
      if (_showMembers)
        for (final member in state.members) _MemberEntry(member),
      if (_canInvite && _showPending)
        for (final invitation in state.invitations)
          _InvitationEntry(invitation),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final filtered = query.isEmpty
        ? entries
        : entries
              .where((entry) => entry.searchText.contains(query))
              .toList(growable: false);

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
            child: Column(
              children: [
                AppSearchField(
                  controller: _searchController,
                  hint: l10n.teamSearchHint,
                  onChanged: (_) => setState(() {}),
                  filterActive: _filtersOpen,
                  onToggleFilter: _canInvite
                      ? () => setState(() => _filtersOpen = !_filtersOpen)
                      : null,
                ),
                if (_filtersOpen) ...[
                  const SizedBox(height: AppSpacing.innerGap),
                  Row(
                    children: [
                      FilterChip(
                        label: Text(l10n.teamFilterMembers),
                        selected: _showMembers,
                        onSelected: (value) =>
                            setState(() => _showMembers = value),
                      ),
                      const SizedBox(width: AppSpacing.chipGap),
                      FilterChip(
                        label: Text(l10n.teamFilterPending),
                        selected: _showPending,
                        onSelected: (value) =>
                            setState(() => _showPending = value),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        ...switch (state.status) {
          TeamStatus.initial ||
          TeamStatus.loading => [const _TeamSkeletonSliver()],
          TeamStatus.error => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _MessageState(
                icon: Icons.cloud_off_outlined,
                message: settingsErrorMessage(l10n, state.error!),
              ),
            ),
          ],
          TeamStatus.loaded when entries.isEmpty => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _MessageState(
                icon: Icons.group_outlined,
                message: l10n.teamEmpty,
              ),
            ),
          ],
          TeamStatus.loaded when filtered.isEmpty => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _MessageState(
                icon: Icons.search_off,
                message: l10n.teamNoMatches,
              ),
            ),
          ],
          TeamStatus.loaded => [
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
                itemBuilder: (context, index) => switch (filtered[index]) {
                  _MemberEntry(:final member) => TeamMemberCard(
                    member: member,
                    onTap: () => _openMember(member.userId),
                  ),
                  _InvitationEntry(:final invitation) => _InvitationCard(
                    invitation: invitation,
                    onTap: () => _openInvitation(invitation.id),
                  ),
                },
              ),
            ),
          ],
        },
      ],
    );
  }
}

sealed class _TeamEntry {
  const _TeamEntry();

  String get label;
  String get searchText;
}

class _MemberEntry extends _TeamEntry {
  const _MemberEntry(this.member);

  final OrganizationMember member;

  @override
  String get label =>
      member.displayName.trim().isEmpty ? member.email : member.displayName;

  @override
  String get searchText => [
    label,
    member.email,
    ...member.roles.map((role) => role.name),
  ].join(' ').toLowerCase();
}

class _InvitationEntry extends _TeamEntry {
  const _InvitationEntry(this.invitation);

  final OrganizationInvitation invitation;

  @override
  String get label => invitation.email;

  @override
  String get searchText =>
      '${invitation.email} ${invitation.roleName}'.toLowerCase();
}

class TeamMemberCard extends StatelessWidget {
  const TeamMemberCard({super.key, required this.member, required this.onTap});

  final OrganizationMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final displayName = member.displayName.trim().isEmpty
        ? member.email
        : member.displayName;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  child: Row(
                    children: [
                      _Avatar(
                        label: displayName,
                        color: AppColors.positiveAccent,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.onSurface(brightness),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (member.isOwner)
                                  _Badge(
                                    label: l10n.teamOwner,
                                    color: AppColors.premiumAmber,
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              member.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.onSurfaceMuted(brightness),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AppColors.onSurfaceSubtle(brightness),
                      ),
                    ],
                  ),
                ),
                _MemberCardFooter(member: member),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberCardFooter extends StatelessWidget {
  const _MemberCardFooter({required this.member});

  final OrganizationMember member;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final subtle = AppColors.onSurfaceSubtle(brightness);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final joined = DateFormat.yMMMd(locale).format(member.joinedAt.toLocal());
    return Container(
      key: const ValueKey('team-member-card-footer'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.innerGap,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardFooterOverlay(brightness),
        border: Border(
          top: BorderSide(color: AppColors.cardBorder(brightness)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.teamRoleCount(member.roles.length),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: subtle, fontSize: 11),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.calendar_today_outlined, size: 12, color: subtle),
                const SizedBox(width: AppSpacing.chipGap),
                Flexible(
                  child: Text(
                    l10n.teamJoined(joined),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(color: subtle, fontSize: 11),
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

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({required this.invitation, required this.onTap});

  final OrganizationInvitation invitation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.cardFill(brightness),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder(brightness)),
        ),
        child: Row(
          children: [
            _Avatar(label: invitation.email, color: AppColors.vaultBlue),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          invitation.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.onSurface(brightness),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _Badge(
                        label: l10n.teamPending,
                        color: AppColors.vaultBlue,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.innerGap),
                  Text(
                    invitation.roleName,
                    style: TextStyle(
                      color: AppColors.onSurfaceMuted(brightness),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final initial = label.trim().isEmpty ? '?' : label.trim().characters.first;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        initial.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.innerGap,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TeamSkeletonSliver extends StatelessWidget {
  const _TeamSkeletonSliver();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      sliver: SliverList.separated(
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.cardGap),
        itemBuilder: (_, index) =>
            SkeletonBox(height: 104, delay: Duration(milliseconds: index * 80)),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.onSurfaceSubtle(brightness), size: 30),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurfaceMuted(brightness),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum InviteMemberSheetResult { manageSeats }

class InviteMemberSheet extends StatefulWidget {
  const InviteMemberSheet({super.key});

  static Future<InviteMemberSheetResult?> show(
    BuildContext context, {
    SettingsCubit? settingsCubit,
  }) async {
    final cubit = context.read<TeamCubit>();
    final shell = AppShellScope.of(context);
    shell.setBottomNavHidden(true);
    try {
      return await showModalBottomSheet<InviteMemberSheetResult>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (_) {
          final sheet = BlocProvider.value(
            value: cubit,
            child: const InviteMemberSheet(),
          );
          if (settingsCubit != null) {
            return BlocProvider.value(value: settingsCubit, child: sheet);
          }
          return BlocProvider<SettingsCubit>(
            create: (_) => getIt<SettingsCubit>()..loadOrg(),
            child: sheet,
          );
        },
      );
    } finally {
      shell.setBottomNavHidden(false);
    }
  }

  @override
  State<InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends State<InviteMemberSheet> {
  final _emailController = TextEditingController();
  InvitationRole? _role;
  bool _submitted = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool get _emailValid => RegExp(
    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
  ).hasMatch(_emailController.text.trim());

  void _clearActionError() {
    final cubit = context.read<TeamCubit>();
    if (cubit.state.actionError != null) cubit.acknowledgeActionResult();
  }

  Future<void> _submit(BuildContext context) async {
    setState(() => _submitted = true);
    if (!_emailValid || _role == null) return;
    final cubit = context.read<TeamCubit>();
    await cubit.invite(email: _emailController.text, roleId: _role!.id);
    if (context.mounted && cubit.state.actionError == null) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<TeamCubit, TeamState>(
      builder: (context, state) {
        final settingsState = context.watch<SettingsCubit>().state;
        if (_role == null && state.invitationRoles.isNotEmpty) {
          _role = state.invitationRoles.first;
        }
        final busy = state.busyAction == TeamAction.invite;
        final orgLoading =
            settingsState.orgStatus == SectionStatus.initial ||
            settingsState.orgStatus == SectionStatus.loading;
        if (orgLoading) {
          return _InviteSheetFrame(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InviteSheetTitle(label: l10n.teamInviteTitle),
                const SizedBox(height: AppSpacing.section),
                const SkeletonBox(height: 64),
              ],
            ),
          );
        }

        final org = settingsState.org;
        final noSeats =
            settingsState.orgStatus == SectionStatus.loaded &&
            org != null &&
            org.seatUsage >= org.seatLimit;
        if (noSeats) {
          return _InviteSheetFrame(
            content: _NoAvailableSeatsContent(
              seatUsage: org.seatUsage,
              seatLimit: org.seatLimit,
            ),
            footer: _PrimarySheetActionFooter(
              label: l10n.teamManageSeats,
              icon: Icons.event_seat_outlined,
              onPressed: () => Navigator.of(
                context,
              ).pop(InviteMemberSheetResult.manageSeats),
            ),
          );
        }

        return _InviteSheetFrame(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InviteSheetTitle(label: l10n.teamInviteTitle),
              const SizedBox(height: AppSpacing.section),
              _InviteSeatUsageCard(state: settingsState),
              const SizedBox(height: AppSpacing.section),
              OnboardingTextField(
                controller: _emailController,
                label: l10n.teamEmailLabel,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  _clearActionError();
                  setState(() {});
                },
                feedbackVisible: _submitted && !_emailValid,
                feedbackReserveSpace: false,
                feedbackChild: Text(
                  l10n.teamInvalidEmail,
                  style: const TextStyle(
                    color: AppColors.brandRed,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.fieldGap),
              AppDropdownField<InvitationRole>(
                label: l10n.teamRoleLabel,
                value: _role,
                items: [
                  for (final role in state.invitationRoles)
                    DropdownMenuItem(value: role, child: Text(role.name)),
                ],
                onChanged: busy
                    ? null
                    : (role) {
                        _clearActionError();
                        setState(() => _role = role);
                      },
                hint: Text(l10n.teamNoInvitationRoles),
                enabled: state.invitationRoles.isNotEmpty,
              ),
              if (state.actionError != null) ...[
                const SizedBox(height: AppSpacing.fieldGap),
                _InviteErrorBanner(
                  message: settingsErrorMessage(l10n, state.actionError!),
                ),
                if (state.actionError ==
                    SettingsErrorKind.seatLimitReached) ...[
                  const SizedBox(height: AppSpacing.innerGap),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(InviteMemberSheetResult.manageSeats),
                    icon: const Icon(Icons.event_seat_outlined, size: 17),
                    label: Text(l10n.teamManageSeats),
                  ),
                ],
              ],
            ],
          ),
          footer: SheetActionButtons(
            onCancel: busy ? null : () => Navigator.of(context).pop(),
            onConfirm: busy ? null : () => _submit(context),
            cancelLabel: l10n.teamCancel,
            confirmLabel: l10n.teamSendInvitation,
            confirmColor: AppColors.brandRed,
            busy: busy,
          ),
        );
      },
    );
  }
}

class _InviteSheetFrame extends StatelessWidget {
  const _InviteSheetFrame({required this.content, this.footer});

  final Widget content;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final safeBottom = footer == null
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.modalBackground(brightness),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.xl,
                AppSpacing.screenH,
                AppSpacing.section + safeBottom,
              ),
              child: content,
            ),
          ),
          ?footer,
        ],
      ),
    );
  }
}

class _InviteSheetTitle extends StatelessWidget {
  const _InviteSheetTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Text(
      label,
      style: TextStyle(
        color: AppColors.onSurface(brightness),
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _NoAvailableSeatsContent extends StatelessWidget {
  const _NoAvailableSeatsContent({
    required this.seatUsage,
    required this.seatLimit,
  });

  final int seatUsage;
  final int seatLimit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Column(
      key: const ValueKey('invite-no-seats-state'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InviteSheetTitle(label: l10n.teamNoSeatsTitle),
        const SizedBox(height: AppSpacing.section),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.brandRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.event_seat_outlined,
                size: 20,
                color: AppColors.brandRed,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                l10n.teamNoSeatsBody,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.section),
        _NoSeatsUsageSummary(seatUsage: seatUsage, seatLimit: seatLimit),
      ],
    );
  }
}

class _NoSeatsUsageSummary extends StatelessWidget {
  const _NoSeatsUsageSummary({
    required this.seatUsage,
    required this.seatLimit,
  });

  final int seatUsage;
  final int seatLimit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final progress = seatLimit == 0
        ? 0.0
        : (seatUsage / seatLimit).clamp(0.0, 1.0).toDouble();
    return Container(
      key: const ValueKey('no-seats-usage-summary'),
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardSurface(brightness),
        border: Border.all(color: AppColors.cardBorder(brightness)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.teamSeatUsageLabel,
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                l10n.teamSeatUsageValue(seatUsage, seatLimit),
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.innerGap),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: progress,
              color: AppColors.brandRed,
              backgroundColor: AppColors.cardFooterOverlay(brightness),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimarySheetActionFooter extends StatelessWidget {
  const _PrimarySheetActionFooter({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final safeBottom =
        MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.cardPadding,
        AppSpacing.screenH,
        AppSpacing.cardPadding + safeBottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardFooterOverlay(Theme.of(context).brightness),
        border: Border(
          top: BorderSide(
            color: AppColors.cardBorder(Theme.of(context).brightness),
          ),
        ),
      ),
      child: SizedBox(
        height: 44,
        child: FilledButton.icon(
          key: const ValueKey('manage-seats-primary-action'),
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandRed,
            foregroundColor: AppColors.onBrandRed,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: Icon(icon, size: 17),
          label: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _InviteSeatUsageCard extends StatelessWidget {
  const _InviteSeatUsageCard({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    if (state.orgStatus == SectionStatus.initial ||
        state.orgStatus == SectionStatus.loading) {
      return const SkeletonBox(height: 64);
    }

    final org = state.org;
    if (state.orgStatus == SectionStatus.error || org == null) {
      return _InviteSeatCardShell(
        child: Row(
          children: [
            Icon(
              Icons.event_seat_outlined,
              size: 18,
              color: AppColors.onSurfaceMuted(brightness),
            ),
            const SizedBox(width: AppSpacing.innerGap),
            Expanded(
              child: Text(
                l10n.teamSeatsUnavailable,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final available = (org.seatLimit - org.seatUsage)
        .clamp(0, org.seatLimit)
        .toInt();
    final progress = org.seatLimit == 0
        ? 0.0
        : (org.seatUsage / org.seatLimit).clamp(0.0, 1.0).toDouble();
    final accent = available == 0 ? AppColors.brandRed : AppColors.vaultBlue;
    return _InviteSeatCardShell(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.event_seat_outlined, size: 17, color: accent),
          ),
          const SizedBox(width: AppSpacing.innerGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.teamSeatUsage(org.seatUsage, org.seatLimit),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  l10n.teamSeatsAvailable(available),
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: progress,
                    color: accent,
                    backgroundColor: AppColors.cardSurface(brightness),
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

class _InviteSeatCardShell extends StatelessWidget {
  const _InviteSeatCardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      key: const ValueKey('invite-seat-usage'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: child,
    );
  }
}

class _InviteErrorBanner extends StatelessWidget {
  const _InviteErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('invite-action-error'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.brandRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.brandRed, size: 18),
          const SizedBox(width: AppSpacing.innerGap),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.brandRed,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
