import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/grant.dart';
import 'grant_format.dart';
import 'grant_status_chip.dart';

/// List row for a single grant — agent name, target entry (or "all
/// entries" for FULL), status chip, and a one-line scope/expiry summary.
class GrantCard extends StatelessWidget {
  const GrantCard({super.key, required this.grant, required this.onTap});

  final Grant grant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    final target = grant.scope == GrantScope.full
        ? l10n.grantScopeFull
        : (grant.entryLabel ?? l10n.grantEntryUnknown);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder(brightness)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      grantAgentDisplayName(l10n, grant),
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
                  GrantStatusChip(status: grant.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.grantCardTarget(target),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
