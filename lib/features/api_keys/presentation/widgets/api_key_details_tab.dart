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
                value:
                    'cv_••••${apiKey.keySuffix.isEmpty ? '••••' : apiKey.keySuffix}',
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
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: isRevoking ? null : onRevoke,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandRed,
                side: BorderSide(
                  color: AppColors.brandRed.withValues(alpha: 0.5),
                ),
                disabledForegroundColor:
                    AppColors.brandRed.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: isRevoking
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.brandRed,
                      ),
                    )
                  : const Icon(Icons.block, size: 18),
              label: Text(
                l10n.apiKeysRevoke,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
        if (!apiKey.isActive && canWrite) ...[
          const SizedBox(height: 16),
          // Activate button — primary action.
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: (isActivating || isDeleting) ? null : onActivate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandRed,
                foregroundColor: AppColors.onBrandRed,
                disabledBackgroundColor:
                    AppColors.brandRed.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: isActivating
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onBrandRed,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                isActivating ? l10n.apiKeysActivating : l10n.apiKeysActivate,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Permanent delete — destructive outlined action.
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: (isActivating || isDeleting) ? null : onDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandRed,
                side: BorderSide(
                  color: AppColors.brandRed.withValues(alpha: 0.5),
                ),
                disabledForegroundColor:
                    AppColors.brandRed.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: isDeleting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.brandRed,
                      ),
                    )
                  : const Icon(Icons.delete_outline, size: 18),
              label: Text(
                isDeleting
                    ? l10n.apiKeysDeleting
                    : l10n.apiKeysDeletePermanently,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
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
