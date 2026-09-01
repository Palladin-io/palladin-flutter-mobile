import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../core/widgets/sheet_drag_handle.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../shell/presentation/pages/app_shell.dart';
import '../../domain/entities/organization_management.dart';
import '../bloc/permissions_cubit.dart';
import '../widgets/permission_fields.dart';
import '../widgets/settings_error_text.dart';
import '../widgets/system_role_badge.dart';

class PermissionsPage extends StatelessWidget {
  const PermissionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PermissionsCubit>(
      create: (_) => getIt<PermissionsCubit>()..load(),
      child: const _PermissionsView(),
    );
  }
}

class _PermissionsView extends StatefulWidget {
  const _PermissionsView();

  @override
  State<_PermissionsView> createState() => _PermissionsViewState();
}

class _PermissionsViewState extends State<_PermissionsView> {
  Widget? _cachedFab;

  Future<void> _openRole(String roleId) async {
    await context.push(AppRoutes.settingsPermissionRole(roleId));
    if (mounted) await context.read<PermissionsCubit>().load();
  }

  void _listen(BuildContext context, PermissionsState state) {
    if (state.actionError == null && state.completedAction == null) return;
    final l10n = AppLocalizations.of(context)!;
    final message = state.actionError != null
        ? settingsErrorMessage(l10n, state.actionError!)
        : switch (state.completedAction) {
            PermissionsAction.create => l10n.permissionsCreated,
            PermissionsAction.update => l10n.permissionsUpdated,
            PermissionsAction.delete => l10n.permissionsDeleted,
            null => null,
          };
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
    context.read<PermissionsCubit>().acknowledgeActionResult();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final fab = _cachedFab ??= Padding(
      padding: const EdgeInsets.only(
        bottom: AppSpacing.innerGap,
        right: AppSpacing.xs,
      ),
      child: AppFab(
        tooltip: l10n.permissionsCreate,
        onPressed: () => CreateRoleSheet.show(context),
      ),
    );
    return BlocListener<PermissionsCubit, PermissionsState>(
      listenWhen: (previous, current) =>
          previous.actionError != current.actionError ||
          previous.completedAction != current.completedAction,
      listener: _listen,
      child: AppScreen.appBar(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
          title: AppBarTitle(
            title: l10n.permissionsScreenTitle,
            subtitle: l10n.permissionsScreenSubtitle,
          ),
        ),
        body: Stack(
          children: [
            BlocBuilder<PermissionsCubit, PermissionsState>(
              builder: (context, state) => RefreshIndicator(
                color: AppColors.brandRed,
                backgroundColor: AppColors.cardSurface(brightness),
                onRefresh: () => context.read<PermissionsCubit>().load(),
                child: switch (state.status) {
                  PermissionsStatus.initial ||
                  PermissionsStatus.loading => const _RoleSkeleton(),
                  PermissionsStatus.error => _RoleMessage(
                    message: settingsErrorMessage(l10n, state.error!),
                  ),
                  PermissionsStatus.loaded when state.roles.isEmpty =>
                    _RoleMessage(message: l10n.permissionsEmpty),
                  PermissionsStatus.loaded => _RoleList(
                    roles: state.roles,
                    onOpen: _openRole,
                  ),
                },
              ),
            ),
            Positioned(width: 0, height: 0, child: FabRegistrar(fab: fab)),
          ],
        ),
      ),
    );
  }
}

class _RoleList extends StatelessWidget {
  const _RoleList({required this.roles, required this.onOpen});

  final List<OrganizationRole> roles;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.listBottom,
      ),
      itemCount: roles.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.cardGap),
      itemBuilder: (context, index) =>
          _RoleCard(role: roles[index], onTap: () => onOpen(roles[index].id)),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.onTap});

  final OrganizationRole role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final accent = role.isSystem ? AppColors.vaultBlue : AppColors.brandRed;
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.12),
              ),
              child: Icon(
                role.isSystem
                    ? Icons.verified_user_outlined
                    : Icons.shield_outlined,
                color: accent,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RoleNameRow(
                    isSystem: role.isSystem,
                    name: Text(
                      role.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.permissionsAssignedMembers(role.assignedMemberCount),
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
              color: AppColors.onSurfaceSubtle(brightness),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleSkeleton extends StatelessWidget {
  const _RoleSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      children: [
        for (var index = 0; index < 4; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
            child: SkeletonBox(
              height: 72,
              delay: Duration(milliseconds: index * 80),
            ),
          ),
      ],
    );
  }
}

class _RoleMessage extends StatelessWidget {
  const _RoleMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.onSurfaceMuted(brightness),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class CreateRoleSheet extends StatefulWidget {
  const CreateRoleSheet({super.key});

  static Future<void> show(BuildContext context) async {
    final cubit = context.read<PermissionsCubit>();
    final shell = AppShellScope.of(context);
    shell.setBottomNavHidden(true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            BlocProvider.value(value: cubit, child: const CreateRoleSheet()),
      );
    } finally {
      shell.setBottomNavHidden(false);
    }
  }

  @override
  State<CreateRoleSheet> createState() => _CreateRoleSheetState();
}

class _CreateRoleSheetState extends State<CreateRoleSheet> {
  final _nameController = TextEditingController();
  int _mask = 0;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit(BuildContext context) async {
    if (_nameController.text.trim().isEmpty) return;
    final cubit = context.read<PermissionsCubit>();
    await cubit.createRole(_nameController.text, _mask);
    if (context.mounted && cubit.state.actionError == null) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return BlocBuilder<PermissionsCubit, PermissionsState>(
      builder: (context, state) {
        final busy = state.busyAction == PermissionsAction.create;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          decoration: BoxDecoration(
            color: AppColors.modalBackground(brightness),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.md),
                  child: SheetDragHandle(),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.screenH),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.permissionsCreateTitle,
                          style: TextStyle(
                            color: AppColors.onSurface(brightness),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.section),
                        OnboardingTextField(
                          controller: _nameController,
                          label: l10n.permissionsRoleName,
                          hintText: l10n.permissionsRoleNameHint,
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
                          enabled: !busy,
                          onChanged: (mask) => setState(() => _mask = mask),
                        ),
                      ],
                    ),
                  ),
                ),
                SheetActionButtons(
                  onCancel: busy ? null : () => Navigator.of(context).pop(),
                  onConfirm: busy || _nameController.text.trim().isEmpty
                      ? null
                      : () => _submit(context),
                  confirmLabel: l10n.permissionsCreate,
                  confirmColor: AppColors.brandRed,
                  cancelLabel: l10n.teamCancel,
                  busy: busy,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
