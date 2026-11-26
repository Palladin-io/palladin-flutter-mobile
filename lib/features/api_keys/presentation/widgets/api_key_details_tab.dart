import '../../../../core/widgets/action_zone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../settings/domain/entities/api_key.dart';
import 'api_key_format.dart';
import '../../../../core/widgets/approve_action_button.dart';
import '../../../vault/presentation/widgets/entry_field_row.dart';

/// Body of the "Details" tab on the API-key detail screen.
///
/// Shows the key's name, status badge, created date and — for revoked
/// keys — the revoke date. Active keys render the Revoke action; revoked
/// keys render Activate (re-enable) and Permanent delete actions.
class ApiKeyDetailsTab extends StatelessWidget {
  const ApiKeyDetailsTab({
    super.key,
    required this.apiKey,
    required this.isRevoking,
    required this.onRevoke,
    required this.isActivating,
    required this.isDeleting,
    required this.onActivate,
    required this.onDelete,
  });

  final ApiKey apiKey;

  /// True while a revoke for this key is in flight — disables the button
  /// and swaps its label for a spinner.
  final bool isRevoking;

  final VoidCallback onRevoke;

  /// True while an activate for this key is in flight.
  final bool isActivating;

  /// True while a permanent delete for this key is in flight.
  final bool isDeleting;

  final VoidCallback onActivate;

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final authState = context.watch<AuthBloc>().state;
    final permissions = authState is AuthAuthenticated
        ? authState.permissions
        : 0;
    final canWrite = (permissions & Permissions.writeApiKey) != 0;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.section,
        AppSpacing.screenH,
        AppSpacing.section,
      ),
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder(brightness)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DetailRow(
                label: l10n.apiKeysDetailKey,
                value: maskedApiKey(apiKey.keySuffix),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: AppColors.cardBorder(brightness),
              ),
              _DetailRow(
                label: l10n.apiKeysDetailCreatedAt,
                value: formatApiKeyDate(apiKey.createdAt),
              ),
              if (apiKey.revokedAt != null) ...[
                Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.cardBorder(brightness),
                ),
                _DetailRow(
                  label: l10n.apiKeysDetailRevokedAt,
                  value: formatApiKeyDate(apiKey.revokedAt!),
                ),
              ],
            ],
          ),
        ),
        if (apiKey.isActive && canWrite) ...[
          const SizedBox(height: AppSpacing.section),
          _DangerZone(
            label: l10n.entryDangerZone,
            actionLabel: isRevoking ? '…' : l10n.apiKeysRevoke,
            icon: isRevoking
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.brandRed,
                    ),
                  )
                : const Icon(
                    Icons.block_outlined,
                    size: 22,
                    color: AppColors.brandRed,
                  ),
            onPressed: isRevoking ? null : onRevoke,
          ),
        ],
        if (!apiKey.isActive && canWrite) ...[
          const SizedBox(height: AppSpacing.section),
          ActionZone(
            title: l10n.apiKeysActivate,
            semanticColor: AppColors.onSurface(brightness),
            borderColor: AppColors.cardBorder(brightness),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.apiKeysActivateHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceMuted(brightness),
                  ),
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                ApproveActionButton(
                  label: l10n.apiKeysActivate,
                  isLoading: isActivating,
                  onPressed: (isActivating || isDeleting) ? null : onActivate,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          // Danger zone — delete permanently.
          _DangerZone(
            label: l10n.entryDangerZone,
            actionLabel: isDeleting
                ? l10n.apiKeysDeleting
                : l10n.apiKeysDeletePermanently,
            icon: isDeleting
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.brandRed,
                    ),
                  )
                : const Icon(
                    Icons.delete_outline,
                    size: 22,
                    color: AppColors.brandRed,
                  ),
            onPressed: (isActivating || isDeleting) ? null : onDelete,
          ),
        ],
      ],
    );
  }
}

/// A red-bordered destructive-action card matching the vault settings
/// danger-zone pattern — a section label above a single full-width
/// tinted action button.
class _DangerZone extends StatelessWidget {
  const _DangerZone({
    required this.label,
    required this.actionLabel,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String actionLabel;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return CompactDangerZone(
      title: label,
      heading: actionLabel,
      actionIcon: icon,
      onPressed: onPressed,
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => EntryFieldRow(
    icon: Icons.key_outlined,
    value: value,
    isMasked: false,
    revealed: true,
    onToggleReveal: null,
    onCopy: null,
  ).labeled(label);
}
