import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
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
    final brightness = Theme.of(context).brightness;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder(brightness)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      apiKey.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      maskedApiKey(apiKey.keySuffix),
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ApiKeyStatusBadge(status: apiKey.status),
                  const SizedBox(height: 4),
                  Text(
                    formatApiKeyDate(apiKey.createdAt),
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
