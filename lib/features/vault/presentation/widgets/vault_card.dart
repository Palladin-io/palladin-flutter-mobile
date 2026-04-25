import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/vault_entity.dart';

/// A single row in the vault list.
///
/// Visual structure:
///
///   [icon chip] [name + meta]                 [grant-mode badge]
///                [entries · updated relative]
///
/// The icon chip uses the vault's color (or `AppColors.tealAccent` as
/// a fallback) at 20% opacity for the background. The mode badge is
/// teal for FULL and amber for GRANULAR.
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
    final accent = _resolveAccentColor();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.textPrimary.withValues(alpha: 0.04),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconChip(emoji: vault.icon ?? '🔒', color: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vault.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (vault.description != null &&
                            vault.description!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            vault.description!,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                              height: 1.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ModeBadge(mode: vault.grantMode, l10n: l10n),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 12,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.vaultEntryCount(vault.entryCount),
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.access_time,
                    size: 12,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      l10n.vaultUpdatedAt(_formatDate(vault.updatedAt)),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
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

  /// Parses the vault's `#RRGGBB` color hint, falling back to teal
  /// when missing or malformed. Mobile cards never show a "no color"
  /// state — every vault renders a tinted icon chip.
  Color _resolveAccentColor() {
    final raw = vault.color;
    if (raw == null || raw.isEmpty) return AppColors.tealAccent;
    final cleaned = raw.startsWith('#') ? raw.substring(1) : raw;
    if (cleaned.length != 6) return AppColors.tealAccent;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return AppColors.tealAccent;
    return Color(0xFF000000 | value);
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.emoji, required this.color});

  final String emoji;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        emoji,
        style: const TextStyle(fontSize: 18),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode, required this.l10n});

  final GrantMode mode;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final isFull = mode == GrantMode.full;
    final color = isFull ? AppColors.tealAccent : AppColors.strengthFair;
    final label =
        isFull ? l10n.vaultModeFull.toUpperCase() : l10n.vaultModeGranular.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
