import '../../../../core/widgets/app_record_row.dart';
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

    return AppRecordRow(
      title: apiKey.name,
      subtitle: maskedApiKey(apiKey.keySuffix),
      onTap: onTap,
      leading: Icon(
        Icons.key_outlined,
        size: 22,
        color: AppColors.onSurfaceMuted(brightness),
      ),
      trailing: ApiKeyStatusBadge(status: apiKey.status),
    );
  }
}
