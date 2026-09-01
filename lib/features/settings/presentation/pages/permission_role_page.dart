import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../domain/entities/organization_management.dart';
import '../bloc/permissions_cubit.dart';
import '../widgets/permission_fields.dart';
import '../widgets/settings_error_text.dart';
import '../widgets/system_role_badge.dart';

class PermissionRolePage extends StatelessWidget {
  const PermissionRolePage({super.key, required this.roleId});

  final String roleId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PermissionsCubit>(
      create: (_) => getIt<PermissionsCubit>()..load(),
      child: _PermissionRoleView(roleId: roleId),
    );
  }
}

class _PermissionRoleView extends StatefulWidget {
  const _PermissionRoleView({required this.roleId});

  final String roleId;

  @override
  State<_PermissionRoleView> createState() => _PermissionRoleViewState();
}

class _PermissionRoleViewState extends State<_PermissionRoleView> {
  final _nameController = TextEditingController();
  String _syncedSignature = '';
  int _mask = 0;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _sync(OrganizationRole role) {
    final signature = '${role.name}|${role.permissions}';
    if (_syncedSignature == signature) return;
    _syncedSignature = signature;
    _nameController.text = role.name;
    _mask = role.permissions;
  }

  void _listen(BuildContext context, PermissionsState state) {
    if (state.actionError == null && state.completedAction == null) return;
    final l10n = AppLocalizations.of(context)!;
    final action = state.completedAction;
    final message = state.actionError != null
        ? settingsErrorMessage(l10n, state.actionError!)
        : switch (action) {
            PermissionsAction.update => l10n.permissionsUpdated,
            PermissionsAction.delete => l10n.permissionsDeleted,
            _ => null,
          };
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
    context.read<PermissionsCubit>().acknowledgeActionResult();
    if (action == PermissionsAction.delete && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return BlocConsumer<PermissionsCubit, PermissionsState>(
      listenWhen: (previous, current) =>
          previous.actionError != current.actionError ||
          previous.completedAction != current.completedAction,
      listener: _listen,
      builder: (context, state) {
        final role = state.roles
            .where((item) => item.id == widget.roleId)
            .firstOrNull;
        if (role != null) _sync(role);
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
            title: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.screenH),
              child: RoleNameRow(
                isSystem: role?.isSystem ?? false,
                name: AppBarTitle(
                  title: role?.name ?? l10n.permissionsEditTitle,
                  subtitle: role == null
                      ? null
                      : l10n.permissionsAssignedMembers(
                          role.assignedMemberCount,
                        ),
                ),
              ),
            ),
          ),
          body: switch (state.status) {
            PermissionsStatus.initial ||
            PermissionsStatus.loading => const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: SkeletonBox(height: 360),
            ),
            PermissionsStatus.error => _RoleDetailMessage(
              message: settingsErrorMessage(l10n, state.error!),
            ),
            PermissionsStatus.loaded when role == null => _RoleDetailMessage(
              message: l10n.settingsErrorNotFound,
            ),
            PermissionsStatus.loaded => _buildLoaded(context, state, role!),
          },
        );
      },
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    PermissionsState state,
    OrganizationRole role,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final busy = state.busyAction != null;
    final editable = canEditOrganizationRole(role);
    final name = _nameController.text.trim();
    final dirty = name != role.name || _mask != role.permissions;
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
              OnboardingTextField(
                controller: _nameController,
                label: l10n.permissionsRoleName,
                enabled: editable && !busy,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.section),
              Text(
                l10n.permissionsPermissionTitle,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.permissionsPermissionHint,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PermissionFields(
                permissions: state.assignablePermissions,
                mask: _mask,
                enabled: editable && !busy,
                onChanged: (mask) => setState(() => _mask = mask),
              ),
              if (!editable) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  role.isSystem
                      ? l10n.permissionsSystemReadOnly
                      : l10n.permissionsRoleReadOnly,
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 12,
                  ),
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.section),
                Divider(color: AppColors.cardBorder(brightness)),
                const SizedBox(height: AppSpacing.innerGap),
                if (role.assignedMemberCount == 0)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandRed,
                    ),
                    onPressed: busy
                        ? null
                        : () => _confirmDelete(context, role),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(l10n.permissionsDelete),
                  )
                else
                  Text(
                    l10n.permissionsDeleteBlocked,
                    style: TextStyle(
                      color: AppColors.onSurfaceMuted(brightness),
                      fontSize: 12,
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (editable)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.md,
              AppSpacing.screenH,
              AppSpacing.screenBottom,
            ),
            decoration: BoxDecoration(
              color: AppColors.cardFill(brightness),
              border: Border(
                top: BorderSide(color: AppColors.navBorder(brightness)),
              ),
            ),
            child: PrimaryButton(
              label: l10n.permissionsSave,
              isLoading: state.busyAction == PermissionsAction.update,
              onPressed: busy || !dirty || name.isEmpty
                  ? null
                  : () => context.read<PermissionsCubit>().updateRole(
                      role.id,
                      name,
                      _mask,
                    ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    OrganizationRole role,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.permissionsDeleteTitle),
        content: Text(l10n.permissionsDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.teamCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.brandRed),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.permissionsDelete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<PermissionsCubit>().deleteRole(role.id);
    }
  }
}

class _RoleDetailMessage extends StatelessWidget {
  const _RoleDetailMessage({required this.message});

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

/// Conservative affordance guard; the backend remains authoritative.
bool canEditOrganizationRole(OrganizationRole role) {
  return !role.isSystem && role.canAssign;
}
