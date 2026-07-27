import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/vault_entity.dart';
import '../../data/services/encrypted_presentation_asset_service.dart';
import 'encrypted_asset_image.dart';
import 'vault_visuals.dart';

/// A single row in the vault list. Identity zone (icon + name + counts) over
/// a distinct footer zone (last-updated), matching the AgentCard proportions.
///
/// Visual structure:
///
/// ```
/// ┌──────────────────────────────────────────────┐
/// │ [icon]  Vault name              N grants     │
/// │         N entries                            │
/// │ ── footer zone ──                            │
/// │ 🕘 Updated Xh ago                            │
/// └──────────────────────────────────────────────┘
/// ```
class VaultCard extends StatelessWidget {
  const VaultCard({super.key, required this.vault, required this.onTap});

  final VaultEntity vault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final accent = VaultVisuals.colorFor(vault.color);
    final isUrl = VaultVisuals.isCustomUrl(vault.icon);
    final icon = isUrl ? Icons.shield : VaultVisuals.iconFor(vault.icon);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Identification zone — tappable (mirrors AgentCard).
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  child: _CardHeader(
                    vaultName: vault.name,
                    entryCount: vault.entryCount,
                    icon: icon,
                    iconUrl: isUrl ? vault.icon : null,
                    vaultId: vault.id,
                    accent: accent,
                    l10n: l10n,
                  ),
                ),
              ),
            ),
            _CardFooter(lastUpdated: vault.updatedAt, l10n: l10n),
          ],
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.vaultName,
    required this.entryCount,
    required this.icon,
    required this.accent,
    required this.l10n,
    required this.vaultId,
    this.iconUrl,
  });

  final String vaultName;
  final int entryCount;
  final IconData icon;
  final String? iconUrl;
  final String vaultId;
  final Color accent;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _IconCircle(
          icon: icon,
          accent: accent,
          iconUrl: iconUrl,
          vaultId: vaultId,
        ),
        const SizedBox(width: AppSpacing.innerGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                vaultName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.vaultEntryCount(entryCount),
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({
    required this.icon,
    required this.accent,
    required this.vaultId,
    this.iconUrl,
  });

  final IconData icon;
  final Color accent;

  /// When non-null, renders a network image inside the circle. Falls
  /// back to [icon] on load error.
  final String? iconUrl;
  final String vaultId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.15),
      ),
      child: iconUrl?.startsWith('asset:') ?? false
          ? ClipOval(
              child: EncryptedAssetImage(
                reference: iconUrl!,
                target: PresentationAssetTarget.vault,
                vaultId: vaultId,
                width: 40,
                height: 40,
                fallback: Icon(icon, color: accent, size: 20),
              ),
            )
          : Icon(icon, color: accent, size: 20),
    );
  }
}

class _CardFooter extends StatelessWidget {
  const _CardFooter({required this.lastUpdated, required this.l10n});

  final DateTime lastUpdated;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final subtle = AppColors.onSurfaceSubtle(brightness);
    // Distinct footer zone with the same treatment as AgentCard's footer —
    // overlay fill, hairline top border, 12/8 padding.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardFooterOverlay(brightness),
        border: Border(
          top: BorderSide(color: AppColors.cardBorder(brightness), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.innerGap,
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 12, color: subtle),
          const SizedBox(width: AppSpacing.chipGap),
          Expanded(
            child: Text(
              l10n.vaultUpdatedAt(_formatRelative(l10n, lastUpdated)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: subtle, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  /// Localised relative timestamp ("teraz" / "now", "3 min temu" /
  /// "3m ago", …) — delegates to the ARB plural keys
  /// `vaultUpdatedNow` / `vaultUpdatedMinutesAgo` /
  /// `vaultUpdatedHoursAgo` / `vaultUpdatedDaysAgo`. Falls back to an
  /// ISO date when older than 30 days (no localisation needed there —
  /// the format is purely numeric).
  String _formatRelative(AppLocalizations l10n, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return l10n.vaultUpdatedNow;
    if (diff.inMinutes < 60) return l10n.vaultUpdatedMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.vaultUpdatedHoursAgo(diff.inHours);
    if (diff.inDays < 30) return l10n.vaultUpdatedDaysAgo(diff.inDays);
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
