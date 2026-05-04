import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/vault_entity.dart';
import 'vault_visuals.dart';

/// A single row in the vault list — mirrors the Astro
/// `ui/VaultCard.astro` prototype exactly.
///
/// Visual structure:
///
/// ```
/// ┌──────────────────────────────────────────────┐
/// │ [icon]  Vault name              N grants     │
/// │         N entries                            │
/// │ ── divider ──                                │
/// │ 🔒 N active grants    Updated Xh ago         │
/// └──────────────────────────────────────────────┘
/// ```
class VaultCard extends StatelessWidget {
  const VaultCard({
    super.key,
    required this.vault,
    required this.onTap,
  });

  final VaultEntity vault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final accent = VaultVisuals.colorFor(vault.color);
    final isUrl = VaultVisuals.isCustomUrl(vault.icon);
    final icon = isUrl ? Icons.shield : VaultVisuals.iconFor(vault.icon);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.cardBorder(brightness),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                vaultName: vault.name,
                entryCount: vault.entryCount,
                grantCount: vault.activeGrantCount,
                icon: icon,
                iconUrl: isUrl ? vault.icon : null,
                accent: accent,
                l10n: l10n,
              ),
              const SizedBox(height: 8),
              const _Divider(),
              const SizedBox(height: 8),
              _CardFooter(
                grantCount: vault.activeGrantCount,
                lastUpdated: vault.updatedAt,
                l10n: l10n,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.vaultName,
    required this.entryCount,
    required this.grantCount,
    required this.icon,
    required this.accent,
    required this.l10n,
    this.iconUrl,
  });

  final String vaultName;
  final int entryCount;
  final int grantCount;
  final IconData icon;
  final String? iconUrl;
  final Color accent;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _IconCircle(icon: icon, accent: accent, iconUrl: iconUrl),
        const SizedBox(width: 10),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.vaultEntryCount(entryCount),
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          l10n.vaultGrantCount(grantCount),
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, required this.accent, this.iconUrl});

  final IconData icon;
  final Color accent;

  /// When non-null, renders a network image inside the circle. Falls
  /// back to [icon] on load error.
  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.15),
      ),
      child: iconUrl != null
          ? ClipOval(
              child: Image.network(
                iconUrl!,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    Icon(icon, color: accent, size: 16),
              ),
            )
          : Icon(icon, color: accent, size: 16),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      height: 1,
      color: AppColors.cardBorder(brightness),
    );
  }
}

class _CardFooter extends StatelessWidget {
  const _CardFooter({
    required this.grantCount,
    required this.lastUpdated,
    required this.l10n,
  });

  final int grantCount;
  final DateTime lastUpdated;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final subtle = AppColors.onSurfaceSubtle(brightness);
    return Row(
      children: [
        Icon(
          Icons.lock,
          size: 12,
          color: subtle,
        ),
        const SizedBox(width: 4),
        Text(
          l10n.vaultActiveGrantCount(grantCount),
          style: TextStyle(
            color: subtle,
            fontSize: 11,
          ),
        ),
        const Spacer(),
        Text(
          l10n.vaultUpdatedAt(_formatRelative(lastUpdated)),
          style: TextStyle(
            color: subtle,
            fontSize: 11,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// Approximate relative timestamp ("3m ago", "2h ago", "5d ago").
  /// Falls back to an ISO date when older than 30 days.
  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
