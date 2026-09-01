import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../domain/entities/organization_management.dart';
import '../bloc/team_cubit.dart';
import '../widgets/settings_error_text.dart';
import '../widgets/system_role_badge.dart';

class TeamMemberPage extends StatelessWidget {
  const TeamMemberPage({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final permissions = auth is AuthAuthenticated ? auth.permissions : 0;
    return BlocProvider<TeamCubit>(
      create: (_) => getIt<TeamCubit>()
        ..load(
          canInvite: false,
          canManage: (permissions & Permissions.organizationManagement) != 0,
        ),
      child: _TeamMemberView(userId: userId, callerPermissions: permissions),
    );
  }
}

class _TeamMemberView extends StatefulWidget {
  const _TeamMemberView({
    required this.userId,
    required this.callerPermissions,
  });

  final String userId;
  final int callerPermissions;

  @override
  State<_TeamMemberView> createState() => _TeamMemberViewState();
}

class _TeamMemberViewState extends State<_TeamMemberView> {
  Set<String> _selectedRoles = {};
  String _syncedRoles = '';
  bool _attemptedEmpty = false;

  void _syncRoles(OrganizationMember member) {
    final signature = member.roles.map((role) => role.id).toList()..sort();
    final joined = signature.join('|');
    if (joined == _syncedRoles) return;
    _syncedRoles = joined;
    _selectedRoles = signature.toSet();
  }

  void _listen(BuildContext context, TeamState state) {
    if (state.actionError == null &&
        state.completedAction != TeamAction.updateMemberRoles) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final message = state.actionError == null
        ? l10n.teamMemberRolesUpdated
        : settingsErrorMessage(l10n, state.actionError!);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    context.read<TeamCubit>().acknowledgeActionResult();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return BlocConsumer<TeamCubit, TeamState>(
      listenWhen: (previous, current) =>
          previous.actionError != current.actionError ||
          previous.completedAction != current.completedAction,
      listener: _listen,
      builder: (context, state) {
        final member = state.members
            .where((item) => item.userId == widget.userId)
            .firstOrNull;
        final title = member == null
            ? l10n.teamMemberTitle
            : member.displayName.trim().isEmpty
            ? member.email
            : member.displayName;
        if (member != null) _syncRoles(member);
        return AppScreen.appBar(
          safeAreaBottom: false,
          floatingActionButton: const FabRegistrar(fab: null),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            titleSpacing: 0,
            centerTitle: false,
            iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
            title: AppBarTitle(title: title, subtitle: member?.email),
          ),
          body: switch (state.status) {
            TeamStatus.initial || TeamStatus.loading => const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: SkeletonBox(height: 280),
            ),
            TeamStatus.error => _DetailMessage(
              message: settingsErrorMessage(l10n, state.error!),
            ),
            TeamStatus.loaded when member == null => _DetailMessage(
              message: l10n.settingsErrorNotFound,
            ),
            TeamStatus.loaded => _buildLoaded(context, state, member!),
          },
        );
      },
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    TeamState state,
    OrganizationMember member,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final canEdit = canEditOrganizationMemberRoles(
      member: member,
      callerPermissions: widget.callerPermissions,
    );
    final catalog =
        <String, OrganizationRole>{
          for (final role in member.roles) role.id: role,
          for (final role in state.roles) role.id: role,
        }.values.toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    final currentIds = member.roles.map((role) => role.id).toSet();
    final dirty = !_setEquals(currentIds, _selectedRoles);
    final busy = state.busyAction == TeamAction.updateMemberRoles;
    final joined = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(member.joinedAt.toLocal());

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              0,
              AppSpacing.screenH,
              AppSpacing.section,
            ),
            children: [
              _DetailCard(
                children: [
                  _DetailRow(icon: Icons.email_outlined, value: member.email),
                  const SizedBox(height: AppSpacing.innerGap),
                  _DetailRow(
                    icon: Icons.calendar_today_outlined,
                    value: l10n.teamJoined(joined),
                  ),
                  if (member.isOwner) ...[
                    const SizedBox(height: AppSpacing.innerGap),
                    _DetailRow(
                      icon: Icons.workspace_premium_outlined,
                      value: l10n.teamOwner,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.section),
              Text(
                l10n.teamRolesTitle,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.teamRolesHint,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _DetailCard(
                padding: EdgeInsets.zero,
                children: [
                  for (var index = 0; index < catalog.length; index++) ...[
                    CheckboxListTile(
                      value: _selectedRoles.contains(catalog[index].id),
                      activeColor: AppColors.brandRed,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: RoleNameRow(
                        isSystem: catalog[index].isSystem,
                        name: Text(catalog[index].name),
                      ),
                      onChanged: canEdit && catalog[index].canAssign && !busy
                          ? (selected) {
                              setState(() {
                                _attemptedEmpty = false;
                                if (selected ?? false) {
                                  _selectedRoles.add(catalog[index].id);
                                } else {
                                  _selectedRoles.remove(catalog[index].id);
                                }
                              });
                            }
                          : null,
                    ),
                    if (index != catalog.length - 1)
                      Divider(
                        height: 1,
                        color: AppColors.cardBorder(brightness),
                      ),
                  ],
                ],
              ),
              if (_attemptedEmpty) ...[
                const SizedBox(height: AppSpacing.innerGap),
                Text(
                  l10n.teamAtLeastOneRole,
                  style: const TextStyle(
                    color: AppColors.brandRed,
                    fontSize: 11,
                  ),
                ),
              ],
              if (!canEdit) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.teamMemberReadOnly,
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (canEdit)
          _PinnedFooter(
            child: PrimaryButton(
              label: l10n.teamSaveRoles,
              isLoading: busy,
              onPressed: !dirty || busy
                  ? null
                  : () {
                      if (_selectedRoles.isEmpty) {
                        setState(() => _attemptedEmpty = true);
                        return;
                      }
                      context.read<TeamCubit>().updateMemberRoles(
                        member.userId,
                        _selectedRoles.toList(growable: false),
                      );
                    },
            ),
          ),
      ],
    );
  }
}

class TeamInvitationPage extends StatelessWidget {
  const TeamInvitationPage({super.key, required this.invitationId});

  final String invitationId;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final permissions = auth is AuthAuthenticated ? auth.permissions : 0;
    return BlocProvider<TeamCubit>(
      create: (_) => getIt<TeamCubit>()
        ..load(
          canInvite: (permissions & Permissions.addUser) != 0,
          canManage: false,
        ),
      child: _TeamInvitationView(invitationId: invitationId),
    );
  }
}

class _TeamInvitationView extends StatefulWidget {
  const _TeamInvitationView({required this.invitationId});

  final String invitationId;

  @override
  State<_TeamInvitationView> createState() => _TeamInvitationViewState();
}

class _TeamInvitationViewState extends State<_TeamInvitationView> {
  String? _selectedRoleId;
  String? _syncedRoleId;

  void _listen(BuildContext context, TeamState state) {
    if (state.actionError == null && state.completedAction == null) return;
    final l10n = AppLocalizations.of(context)!;
    final action = state.completedAction;
    final message = state.actionError != null
        ? settingsErrorMessage(l10n, state.actionError!)
        : switch (action) {
            TeamAction.cancelInvitation => l10n.teamInvitationCancelled,
            TeamAction.resendInvitation => l10n.teamInvitationResent,
            TeamAction.updateInvitationRole => l10n.teamInvitationRoleUpdated,
            _ => null,
          };
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
    context.read<TeamCubit>().acknowledgeActionResult();
    if (action == TeamAction.cancelInvitation && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return BlocConsumer<TeamCubit, TeamState>(
      listenWhen: (previous, current) =>
          previous.actionError != current.actionError ||
          previous.completedAction != current.completedAction,
      listener: _listen,
      builder: (context, state) {
        final invitation = state.invitations
            .where((item) => item.id == widget.invitationId)
            .firstOrNull;
        if (invitation != null && _syncedRoleId != invitation.roleId) {
          _syncedRoleId = invitation.roleId;
          _selectedRoleId = invitation.roleId;
        }
        return AppScreen.appBar(
          floatingActionButton: const FabRegistrar(fab: null),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            titleSpacing: 0,
            centerTitle: false,
            iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
            title: AppBarTitle(
              title: l10n.teamInvitationTitle,
              subtitle: invitation?.email,
            ),
          ),
          body: switch (state.status) {
            TeamStatus.initial || TeamStatus.loading => const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: SkeletonBox(height: 300),
            ),
            TeamStatus.error => _DetailMessage(
              message: settingsErrorMessage(l10n, state.error!),
            ),
            TeamStatus.loaded when invitation == null => _DetailMessage(
              message: l10n.settingsErrorNotFound,
            ),
            TeamStatus.loaded => _buildLoaded(context, state, invitation!),
          },
        );
      },
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    TeamState state,
    OrganizationInvitation invitation,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final format = DateFormat.yMMMd(locale).add_Hm();
    final busy = state.busyAction != null;
    final resendAvailable = !DateTime.now().isBefore(
      invitation.resendAvailableAt.toLocal(),
    );
    final roleValue = state.invitationRoles
        .where((role) => role.id == _selectedRoleId)
        .firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      children: [
        _DetailCard(
          children: [
            _DetailRow(
              icon: Icons.schedule_outlined,
              value: l10n.teamSentAt(
                format.format(invitation.sentAt.toLocal()),
              ),
            ),
            const SizedBox(height: AppSpacing.innerGap),
            _DetailRow(
              icon: Icons.event_busy_outlined,
              value: l10n.teamExpiresAt(
                format.format(invitation.expiresAt.toLocal()),
              ),
            ),
            if (invitation.invitedByName case final invitedBy?) ...[
              const SizedBox(height: AppSpacing.innerGap),
              _DetailRow(
                icon: Icons.person_outline,
                value: l10n.teamInvitedBy(invitedBy),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.section),
        AppDropdownField<InvitationRole>(
          label: l10n.teamRoleLabel,
          value: roleValue,
          items: [
            for (final role in state.invitationRoles)
              DropdownMenuItem(value: role, child: Text(role.name)),
          ],
          onChanged: busy
              ? null
              : (role) => setState(() => _selectedRoleId = role?.id),
          enabled: !busy,
        ),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          label: l10n.settingsSave,
          isLoading: state.busyAction == TeamAction.updateInvitationRole,
          onPressed:
              busy ||
                  _selectedRoleId == null ||
                  _selectedRoleId == invitation.roleId
              ? null
              : () => context.read<TeamCubit>().updateInvitationRole(
                  invitation.id,
                  _selectedRoleId!,
                ),
        ),
        const SizedBox(height: AppSpacing.section),
        OutlinedButton.icon(
          onPressed: busy || !resendAvailable
              ? null
              : () => context.read<TeamCubit>().resendInvitation(invitation.id),
          icon: const Icon(Icons.send_outlined, size: 18),
          label: Text(
            resendAvailable
                ? l10n.teamResend
                : l10n.teamResendAvailable(
                    format.format(invitation.resendAvailableAt.toLocal()),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: AppColors.brandRed),
          onPressed: busy ? null : () => _confirmCancel(context, invitation),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: Text(l10n.teamCancelInvitation),
        ),
      ],
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    OrganizationInvitation invitation,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.teamCancelInvitationTitle),
        content: Text(l10n.teamCancelInvitationBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.teamCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.brandRed),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.teamConfirmCancel),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<TeamCubit>().cancelInvitation(invitation.id);
    }
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.onSurfaceSubtle(brightness)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.onSurfaceMuted(brightness),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _PinnedFooter extends StatelessWidget {
  const _PinnedFooter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        border: Border(top: BorderSide(color: AppColors.navBorder(brightness))),
      ),
      child: child,
    );
  }
}

bool _setEquals(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

/// Conservative affordance guard; the backend revalidates the same operation.
bool canEditOrganizationMemberRoles({
  required OrganizationMember member,
  required int callerPermissions,
}) {
  final canManage =
      (callerPermissions & Permissions.organizationManagement) != 0;
  final targetExceedsCaller =
      (member.effectivePermissions & ~callerPermissions) != 0;
  return canManage && !member.isOwner && !targetExceedsCaller;
}
