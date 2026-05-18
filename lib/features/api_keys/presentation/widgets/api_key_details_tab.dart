import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../settings/domain/entities/api_key.dart';
import 'api_key_format.dart';
import 'api_key_status_badge.dart';

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
    final permissions =
        authState is AuthAuthenticated ? authState.permissions : 0;
    final canWrite = (permissions & Permissions.writeApiKey) != 0;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder(brightness)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      apiKey.name,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ApiKeyStatusBadge(status: apiKey.status),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(
                label: l10n.apiKeysDetailKey,
                value: maskedApiKey(apiKey.keySuffix),
                mono: true,
              ),
              const SizedBox(height: 8),
              _DetailRow(
                label: l10n.apiKeysDetailCreatedAt,
                value: formatApiKeyDate(apiKey.createdAt),
              ),
              if (apiKey.revokedAt != null) ...[
                const SizedBox(height: 8),
                _DetailRow(
                  label: l10n.apiKeysDetailRevokedAt,
                  value: formatApiKeyDate(apiKey.revokedAt!),
                ),
              ],
            ],
          ),
        ),
        if (apiKey.isActive && canWrite) ...[
          const SizedBox(height: 16),
          _DangerZone(
            label: l10n.vaultDangerZone,
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
                : const Icon(Icons.block, size: 14, color: AppColors.brandRed),
            onPressed: isRevoking ? null : onRevoke,
          ),
        ],
        if (!apiKey.isActive && canWrite) ...[
          const SizedBox(height: 16),
          // Activate section — green-accented card, mirrors the danger zone
          // structure but uses positiveAccent (#2EC4B6) instead of brandRed.
          // positiveAccent is the "approve/restore" semantic colour shared
          // with the web panel — visible on both dark and light backgrounds.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.positiveAccent.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.apiKeysActivateZone,
                  style: const TextStyle(
                    color: AppColors.positiveAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.apiKeysActivateHint,
                  style: const TextStyle(
                    color: AppColors.positiveAccent,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton.icon(
                    icon: isActivating
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.positiveAccent,
                            ),
                          )
                        : const Icon(
                            Icons.check_circle_outline,
                            size: 14,
                            color: AppColors.positiveAccent,
                          ),
                    label: Text(
                      isActivating
                          ? l10n.apiKeysActivating
                          : l10n.apiKeysActivate,
                      style: const TextStyle(
                        color: AppColors.positiveAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor:
                          AppColors.positiveAccent.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed:
                        (isActivating || isDeleting) ? null : onActivate,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Danger zone — delete permanently.
          _DangerZone(
            label: l10n.vaultDangerZone,
            actionLabel:
                isDeleting ? l10n.apiKeysDeleting : l10n.apiKeysDeletePermanently,
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
                    size: 14,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.brandRed,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton.icon(
              icon: icon,
              label: Text(
                actionLabel,
                style: const TextStyle(
                  color: AppColors.brandRed,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.brandRed.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single label / value row in the detail card.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;

  /// When true, renders [value] in a monospace font — used for the
  /// masked key representation.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: mono ? 'monospace' : null,
          ),
        ),
      ],
    );
  }
}
