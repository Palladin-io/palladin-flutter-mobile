import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Agent type — drives the avatar circle color.
enum AgentType { claude, cursor, copilot, openclaw, generic }

/// Grant lifecycle state for the card UI.
enum GrantStatus { active, expired, revoked }

/// Grant access mode — full vault or per-entry list.
enum GrantUiMode { full, granular }

/// Compact agent reference shown inside [GrantCard].
class GrantAgent {
  const GrantAgent({
    required this.type,
    required this.name,
    required this.initials,
  });

  final AgentType type;
  final String name;
  final String initials;
}

/// One entry inside a granular grant — name + per-entry status.
class GrantEntry {
  const GrantEntry({required this.name, this.isActive = true});

  final String name;
  final bool isActive;
}

/// Static mock data for [GrantCard] — used by the Agents tab placeholder
/// until the real grant API ships.
class MockGrant {
  const MockGrant({
    required this.agent,
    required this.mode,
    required this.status,
    required this.expiresAbsolute,
    required this.expiresRelative,
    required this.grantedBy,
    this.entries = const <GrantEntry>[],
    this.revokedBy,
    this.revokedAbsolute,
    this.revokedRelative,
    this.revokedReason,
  });

  final GrantAgent agent;
  final GrantUiMode mode;
  final GrantStatus status;
  final String expiresAbsolute;
  final String expiresRelative;
  final String grantedBy;
  final List<GrantEntry> entries;
  final String? revokedBy;
  final String? revokedAbsolute;
  final String? revokedRelative;
  final String? revokedReason;
}

/// Two-zone grant card mirroring the web `GrantCard` and the Astro
/// mobile prototype `ui/GrantCard.astro`.
///
/// Top zone: agent avatar + name + mode + status pill (and entry chips
/// for granular grants).
/// Bottom zone: footer meta (granted/revoked-by line) + action button
/// (Revoke for active, Re-grant for revoked, Restore for expired).
class GrantCard extends StatelessWidget {
  const GrantCard({
    super.key,
    required this.grant,
    this.onRevoke,
    this.onRestore,
    this.onRegrant,
  });

  final MockGrant grant;
  final VoidCallback? onRevoke;
  final VoidCallback? onRestore;
  final VoidCallback? onRegrant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isRevoked = grant.status == GrantStatus.revoked;
    final isActive = grant.status == GrantStatus.active;
    final cardOpacity = isActive ? 1.0 : 0.72;

    return Opacity(
      opacity: cardOpacity,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.mobileSurface,
          borderRadius: BorderRadius.circular(12),
          border: isRevoked
              ? Border.all(
                  color: AppColors.brandRed.withValues(alpha: 0.18),
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IdentityZone(grant: grant, l10n: l10n),
            if (grant.mode == GrantUiMode.granular &&
                grant.entries.isNotEmpty)
              _EntryChipsRow(entries: grant.entries, l10n: l10n),
            if (isRevoked && grant.revokedReason != null)
              _RevokeReasonChip(reason: grant.revokedReason!),
            _Footer(
              grant: grant,
              l10n: l10n,
              onRevoke: onRevoke,
              onRestore: onRestore,
              onRegrant: onRegrant,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Identity zone ──────────────────────────────────────────────────

class _IdentityZone extends StatelessWidget {
  const _IdentityZone({required this.grant, required this.l10n});

  final MockGrant grant;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final modeLabel = grant.mode == GrantUiMode.full
        ? l10n.vaultGrantFull
        : l10n.vaultGrantGranular;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          _AgentAvatar(agent: grant.agent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  grant.agent.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  modeLabel,
                  style: const TextStyle(
                    color: AppColors.textTertiaryMobile,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusPill(status: grant.status, l10n: l10n),
        ],
      ),
    );
  }
}

class _AgentAvatar extends StatelessWidget {
  const _AgentAvatar({required this.agent});

  final GrantAgent agent;

  @override
  Widget build(BuildContext context) {
    final color = _agentColor(agent.type);
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        agent.initials,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _agentColor(AgentType type) => switch (type) {
        AgentType.claude => AppColors.positiveAccent,
        AgentType.cursor => AppColors.vaultBlue,
        AgentType.copilot => AppColors.vaultViolet,
        AgentType.openclaw => AppColors.brandRed,
        AgentType.generic => AppColors.vaultSlate,
      };
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.l10n});

  final GrantStatus status;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      GrantStatus.active => (AppColors.positiveAccent, l10n.vaultGrantActive),
      GrantStatus.expired => (AppColors.vaultSlate, l10n.vaultGrantExpired),
      GrantStatus.revoked => (AppColors.brandRed, l10n.vaultGrantRevoked),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Entry chips (granular grants only) ─────────────────────────────

class _EntryChipsRow extends StatelessWidget {
  const _EntryChipsRow({required this.entries, required this.l10n});

  static const int _maxVisible = 3;

  final List<GrantEntry> entries;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final visible = entries.take(_maxVisible).toList();
    final hiddenCount = entries.length - visible.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final entry in visible) _EntryChip(entry: entry),
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              child: Text(
                l10n.vaultGrantMoreEntries(hiddenCount),
                style: const TextStyle(
                  color: AppColors.vaultSlate,
                  fontSize: 10,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryChip extends StatelessWidget {
  const _EntryChip({required this.entry});

  final GrantEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.isActive ? AppColors.positiveAccent : AppColors.vaultSlate;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            entry.name,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              decoration: entry.isActive
                  ? TextDecoration.none
                  : TextDecoration.lineThrough,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Revoke reason chip ─────────────────────────────────────────────

class _RevokeReasonChip extends StatelessWidget {
  const _RevokeReasonChip({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.brandRed.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag, size: 11, color: AppColors.brandRed),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                reason,
                style: const TextStyle(
                  color: AppColors.brandRed,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Footer ─────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({
    required this.grant,
    required this.l10n,
    required this.onRevoke,
    required this.onRestore,
    required this.onRegrant,
  });

  final MockGrant grant;
  final AppLocalizations l10n;
  final VoidCallback? onRevoke;
  final VoidCallback? onRestore;
  final VoidCallback? onRegrant;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.hairline),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: _FooterMeta(grant: grant, l10n: l10n)),
          const SizedBox(width: 8),
          _ActionButton(
            grant: grant,
            l10n: l10n,
            onRevoke: onRevoke,
            onRestore: onRestore,
            onRegrant: onRegrant,
          ),
        ],
      ),
    );
  }
}

class _FooterMeta extends StatelessWidget {
  const _FooterMeta({required this.grant, required this.l10n});

  final MockGrant grant;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final isRevoked = grant.status == GrantStatus.revoked;
    final iconColor = isRevoked ? AppColors.brandRed : AppColors.textTertiaryMobile;
    final icon = isRevoked ? Icons.block : Icons.person;

    final person = isRevoked ? grant.revokedBy : grant.grantedBy;
    final String dateAbsolute =
        (isRevoked ? grant.revokedAbsolute : grant.expiresAbsolute) ?? '';
    final String dateRelative =
        (isRevoked ? grant.revokedRelative : grant.expiresRelative) ?? '';

    final dateLabel = dateRelative.isNotEmpty
        ? '$dateAbsolute ($dateRelative)'
        : dateAbsolute;

    final label = isRevoked
        ? l10n.vaultGrantRevokedBy(person ?? '—', dateLabel)
        : l10n.vaultGrantGrantedBy(person ?? '—', dateLabel);

    return Row(
      children: [
        Icon(icon, size: 13, color: iconColor),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textTertiaryMobile,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.grant,
    required this.l10n,
    required this.onRevoke,
    required this.onRestore,
    required this.onRegrant,
  });

  final MockGrant grant;
  final AppLocalizations l10n;
  final VoidCallback? onRevoke;
  final VoidCallback? onRestore;
  final VoidCallback? onRegrant;

  @override
  Widget build(BuildContext context) {
    return switch (grant.status) {
      GrantStatus.active => _PillButton(
          icon: Icons.cancel,
          label: l10n.vaultRevokeButton,
          color: AppColors.brandRed,
          onPressed: onRevoke,
        ),
      GrantStatus.expired => _PillButton(
          icon: Icons.refresh,
          label: l10n.vaultRestoreButton,
          color: AppColors.positiveAccent,
          onPressed: onRestore,
        ),
      GrantStatus.revoked => _PillButton(
          icon: Icons.replay,
          label: l10n.vaultRegrantButton,
          color: AppColors.positiveAccent,
          onPressed: onRegrant,
        ),
    };
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.30)),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
