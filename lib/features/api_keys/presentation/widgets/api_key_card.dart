import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../settings/domain/entities/api_key.dart';
import 'api_key_format.dart';
import 'api_key_status_badge.dart';

/// A single tappable API-key row on the list screen — name, status
/// badge, masked representation and created date.
///
/// Tapping the card navigates to [ApiKeyDetailPage]; the revoke action
/// lives on the detail screen, so the card itself carries no buttons.
class ApiKeyCard extends StatelessWidget {
  const ApiKeyCard({super.key, required this.apiKey, required this.onTap});

  final ApiKey apiKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder(brightness)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            apiKey.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.onSurface(brightness),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ApiKeyStatusBadge(status: apiKey.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'cv_••••${apiKey.keySuffix}',
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.apiKeysCreated(formatApiKeyDate(apiKey.createdAt)),
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.onSurfaceSubtle(brightness),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
