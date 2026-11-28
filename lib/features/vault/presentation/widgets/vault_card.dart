import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../public_asset_catalog/presentation/widgets/public_asset_image.dart';
import '../../domain/entities/vault_entity.dart';
import '../../data/services/encrypted_presentation_asset_service.dart';
import 'encrypted_asset_image.dart';
import 'vault_visuals.dart';

/// Shared Vault identity row for the library and Vault chooser.
class VaultCard extends StatelessWidget {
  const VaultCard({
    super.key,
    required this.vault,
    required this.onTap,
    this.compact = false,
  });

  final bool compact;

  final VaultEntity vault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final accent = VaultVisuals.colorFor(vault.color);
    final isUrl = VaultVisuals.isCustomUrl(vault.icon);
    final icon = isUrl ? Icons.shield : VaultVisuals.iconFor(vault.icon);

    final row = Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 0 : 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
            vertical: AppSpacing.lg,
          ),
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
    );
    if (compact) return row;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: row,
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
        const SizedBox(width: AppSpacing.fieldGap),
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
                  fontWeight: FontWeight.w600,
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
        const SizedBox(width: AppSpacing.innerGap),
        Icon(
          Icons.chevron_right,
          size: 18,
          color: AppColors.onSurfaceSubtle(brightness),
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
      child: iconUrl?.startsWith('public-asset:') ?? false
          ? ClipOval(
              child: PublicAssetImage(
                reference: iconUrl!,
                width: 40,
                height: 40,
                fallback: Icon(icon, color: accent, size: 20),
              ),
            )
          : iconUrl?.startsWith('asset:') ?? false
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
