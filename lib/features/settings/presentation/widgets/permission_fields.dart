import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/organization_management.dart';

/// Caller-aware permission checklist used by role create and edit surfaces.
///
/// Toggling changes only bits present in the backend catalogue, so permission
/// bits introduced by a newer backend remain preserved in an existing role.
class PermissionFields extends StatelessWidget {
  const PermissionFields({
    super.key,
    required this.permissions,
    required this.mask,
    required this.onChanged,
    this.enabled = true,
  });

  final List<AssignablePermission> permissions;
  final int mask;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < permissions.length; index++) ...[
            CheckboxListTile(
              value: (mask & permissions[index].value) != 0,
              activeColor: AppColors.brandRed,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(_label(l10n, permissions[index].key)),
              onChanged: enabled && permissions[index].canAssign
                  ? (selected) {
                      final value = permissions[index].value;
                      onChanged(
                        selected ?? false ? mask | value : mask & ~value,
                      );
                    }
                  : null,
            ),
            if (index != permissions.length - 1)
              Divider(
                height: 1,
                color: AppColors.cardBorder(brightness),
                indent: AppSpacing.screenH,
                endIndent: AppSpacing.screenH,
              ),
          ],
        ],
      ),
    );
  }

  String _label(AppLocalizations l10n, String key) {
    return switch (key.toLowerCase()) {
      'adduser' => l10n.permissionAddUser,
      'organizationmanagement' => l10n.permissionOrganizationManagement,
      'vaultcreate' => l10n.permissionVaultCreate,
      'vaultmanage' => l10n.permissionVaultManage,
      'agentmanage' => l10n.permissionAgentManage,
      'grantmanage' => l10n.permissionGrantManage,
      'auditview' => l10n.permissionAuditView,
      'multiplevaults' || 'premiumplan' => l10n.permissionMultipleVaults,
      'readapikey' => l10n.permissionReadApiKey,
      'writeapikey' => l10n.permissionWriteApiKey,
      _ => key,
    };
  }
}
