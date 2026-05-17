import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../settings/domain/entities/api_key.dart';
import 'api_key_format.dart';
import 'api_key_status_badge.dart';

/// Body of the "Details" tab on the API-key detail screen.
///
/// Shows the key's name, status badge, created date and — for revoked
/// keys — the revoke date. Active keys also render the Revoke action;
/// revoked keys do not (the operation is irreversible and idempotent,
/// so there is nothing left to do).
class ApiKeyDetailsTab extends StatelessWidget {
  const ApiKeyDetailsTab({
    super.key,
    required this.apiKey,
    required this.isRevoking,
    required this.onRevoke,
  });

  final ApiKey apiKey;

  /// True while a revoke for this key is in flight — disables the button
  /// and swaps its label for a spinner.
  final bool isRevoking;

  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

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
              const SizedBox(height: 4),
              // Masked representation — the real secret is never
              // available client-side after creation.
              Text(
                'cv_••••••••',
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 16),
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
        if (apiKey.isActive) ...[
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
      ],
    );
  }
}

/// A single label / value row in the detail card.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

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
          ),
        ),
      ],
    );
  }
}
