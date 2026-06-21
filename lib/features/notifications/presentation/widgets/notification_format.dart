import 'package:flutter/material.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../grants/presentation/widgets/grant_format.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/inbox_notification.dart';
import '../../domain/exceptions/notification_center_exceptions.dart';

/// Presentation-layer i18n + formatting for inbox notifications.
///
/// The backend sends a `titleKey` + `metadata` (names + ids, no secrets); the
/// client renders the localized copy here. New/unknown types fall back to a
/// generic title so a future backend type never breaks the list.

/// Resolves the localized title for a notification from its [titleKey],
/// substituting names from [metadata]. Falls back to a humanized type.
/// The notification types offered in the multi-select filter, in display order.
const notificationFilterTypes = <String>[
  'grant_pending',
  'agent_pending',
  'credential_stale',
  'grant_approved',
  'grant_denied',
  'grant_revoked',
  'agent_approved',
];

/// Localized type name for a raw type string — used by the filter chips so
/// they share the exact capitalized type titles used on the cards.
String notificationTypeName(AppLocalizations l10n, String type) {
  switch (type) {
    case 'grant_pending':
      return l10n.notifTitleGrantPending;
    case 'agent_pending':
      return l10n.notifTitleAgentPending;
    case 'agent_approved':
      return l10n.notifTitleAgentApproved;
    case 'grant_revoked':
      return l10n.notifTitleGrantRevoked;
    case 'grant_approved':
      return l10n.notifTitleGrantApproved;
    case 'grant_denied':
      return l10n.notifTitleGrantDenied;
    case 'credential_stale':
      return l10n.notifTitleCredentialStale;
    default:
      return _humanize(type);
  }
}

/// Card title — a capitalized, sentence-case **type name** (e.g. "New agent",
/// "Access request"). The agent name moves to the subtitle.
String notificationTitle(AppLocalizations l10n, InboxNotification n) =>
    notificationTypeName(l10n, n.type);

/// Subtitle under the type title — carries the agent name / context. Agent-
/// centric cards fall back to "Unknown agent" when the name is empty (e.g.
/// agent registered via `search`); grant cards use the softer "An agent".
String notificationSubtitle(AppLocalizations l10n, InboxNotification n) {
  final agent = _name(n, 'agentName', l10n.notifUnnamedAgent);
  final agentOrUnknown = _name(n, 'agentName', l10n.notifUnknownAgent);
  switch (n.type) {
    case 'grant_pending':
      return l10n.notifSubGrantPending(agent);
    case 'agent_pending':
      return l10n.notifSubAgentPending(agentOrUnknown);
    case 'agent_approved':
      return l10n.notifSubAgentApproved(agentOrUnknown);
    case 'credential_stale':
      return l10n.notifSubCredentialStale(agent);
    case 'grant_revoked':
    case 'grant_approved':
    case 'grant_denied':
      return l10n.notifSubGrantUpdate(agent);
    default:
      return '';
  }
}

/// Detail rows shown inside the card body, label → value, value names bold.
///
/// Every card renders EXACTLY 3 rows with a fixed label set per type, so all
/// cards line up at the same height. A missing value shows the "—" placeholder
/// rather than dropping the row.
List<({String label, String value})> notificationRows(
  AppLocalizations l10n,
  InboxNotification n,
) {
  final dash = l10n.notifPlaceholder;
  String row(String key) => _str(n, key) ?? dash;
  final entry = _entryLabel(l10n, n);

  switch (n.type) {
    case 'grant_pending':
      return [
        (label: l10n.notifRowEntry, value: entry.isEmpty ? dash : entry),
        (label: l10n.notifRowMethods, value: row('methods')),
        (label: l10n.notifRowReason, value: row('reason')),
      ];
    case 'agent_pending':
      return _agentRows(l10n, n);
    case 'agent_approved':
      // Same identity rows as agent_pending — no "By" row (per CVT-165).
      return _agentRows(l10n, n);
    case 'credential_stale':
      return [
        (label: l10n.notifRowEntry, value: entry.isEmpty ? dash : entry),
        (label: l10n.notifRowError, value: row('error')),
        (label: l10n.notifRowAttempts, value: row('attempts')),
      ];
    case 'grant_approved':
      return [
        (label: l10n.notifRowEntry, value: entry.isEmpty ? dash : entry),
        (label: l10n.notifRowAccess, value: _accessSummary(l10n, n)),
        (label: l10n.notifRowBy, value: row('actorName')),
      ];
    case 'grant_revoked':
    case 'grant_denied':
      return [
        (label: l10n.notifRowEntry, value: entry.isEmpty ? dash : entry),
        (label: l10n.notifRowReason, value: row('reason')),
        (label: l10n.notifRowBy, value: row('actorName')),
      ];
    default:
      return [
        (label: l10n.notifRowEntry, value: entry.isEmpty ? dash : entry),
        (label: l10n.notifRowReason, value: row('reason')),
        (label: l10n.notifRowBy, value: row('actorName')),
      ];
  }
}

/// Agent identity rows — always 3: Public key → Agent Id → Host · Ip. Missing
/// values fall back to the "—" placeholder so the card stays a fixed height.
/// The public key surfaces under a "Public key" label, never a vague "key".
List<({String label, String value})> _agentRows(
  AppLocalizations l10n,
  InboxNotification n,
) {
  final dash = l10n.notifPlaceholder;
  return [
    (label: l10n.notifRowPublicKey, value: _keyHint(n) ?? dash),
    (label: l10n.notifRowAgentId, value: _str(n, 'agentId') ?? dash),
    (label: l10n.notifRowHostIp, value: _hostIp(n) ?? dash),
  ];
}

/// Access-policy summary for an approved grant, mirroring what the grants list
/// shows: remaining uses, expiry date, or "Unlimited". Reads `queryLimit` /
/// `queryCount` / `expiresAt` from the notification metadata (strings).
String _accessSummary(AppLocalizations l10n, InboxNotification n) {
  final limit = _int(n, 'queryLimit');
  if (limit != null) {
    final used = _int(n, 'queryCount') ?? 0;
    final left = (limit - used).clamp(0, limit);
    return l10n.orgGrantUsesLeft(left, limit);
  }
  final expires = _str(n, 'expiresAt');
  if (expires != null) {
    final dt = DateTime.tryParse(expires);
    if (dt != null) {
      final iso = dt.toIso8601String();
      return l10n.orgGrantExpiresOn(iso.substring(0, 10));
    }
  }
  return l10n.notifAccessUnlimited;
}

int? _int(InboxNotification n, String key) {
  final raw = n.metadata[key];
  if (raw is int) return raw;
  if (raw is String) return int.tryParse(raw.trim());
  if (raw is num) return raw.toInt();
  return null;
}

/// Combines host + IP into one "host · ip" value (host shortened so a long
/// FQDN never floods the row). Returns just whichever part is present, or null
/// when neither is. Uses the "·" separator (same idiom as entry rows).
String? _hostIp(InboxNotification n) {
  final host = _str(n, 'host');
  final ip = _str(n, 'ip');
  final shortHost = host == null
      ? null
      : (host.length <= 28 ? host : '${host.substring(0, 27)}…');
  if (shortHost != null && ip != null) return '$shortHost · $ip';
  return shortHost ?? ip;
}

/// Public-key hint for display. The backend sends `keyHint` already shortened
/// to the `prefix…suffix` form (root CLAUDE.md key-shortening standard), so it
/// is rendered as-is. Falls back to shortening a raw `agentPublicKey` only if
/// the backend ever sends the full key.
String? _keyHint(InboxNotification n) {
  final hint = _str(n, 'keyHint');
  if (hint != null) return hint;
  final key = _str(n, 'agentPublicKey');
  if (key == null) return null;
  return key.length <= 16
      ? key
      : '${key.substring(0, 8)}…${key.substring(key.length - 6)}';
}

/// Relative "5 min" style timestamp — reuses the grants formatter.
String notificationRelativeTime(AppLocalizations l10n, InboxNotification n) =>
    grantRelativeTime(l10n, n.occurredAt);

/// Leading glyph for a notification type.
IconData notificationIcon(InboxNotification n) {
  switch (n.type) {
    case 'grant_pending':
    case 'grant_approved':
    case 'grant_revoked':
    case 'grant_denied':
      return Icons.vpn_key_outlined;
    case 'agent_pending':
    case 'agent_approved':
      return Icons.smart_toy_outlined;
    case 'credential_stale':
      return Icons.error_outline;
    default:
      return Icons.notifications_outlined;
  }
}

/// Tint color for the leading glyph chip only (NOT a card accent border —
/// cards share a uniform border/background). Security-critical stale = red,
/// agents = teal, grants = blue.
Color notificationGlyphTint(InboxNotification n) {
  if (n.type == 'credential_stale') return AppColors.brandRed;
  if (n.type == 'agent_pending' || n.type == 'agent_approved') {
    return AppColors.positiveAccent;
  }
  return AppColors.vaultBlue;
}

/// True when the card's header should render the real agent avatar (matching
/// the Agents list) instead of a generic glyph chip. Every agent-bearing type
/// qualifies; only `credential_stale` and unknown types keep the glyph.
bool notificationUsesAgentAvatar(InboxNotification n) {
  switch (n.type) {
    case 'grant_pending':
    case 'grant_approved':
    case 'grant_revoked':
    case 'grant_denied':
    case 'agent_pending':
    case 'agent_approved':
      return true;
    default:
      return false;
  }
}

/// The agent's icon key from metadata (`agentIconKey`) — a Material icon name
/// or an uploaded image URL — used to render [AgentAvatar] exactly like the
/// Agents list. Null when the backend sent none.
String? notificationAgentIconKey(InboxNotification n) => _str(n, 'agentIconKey');

/// The agent's display name from metadata, or null.
String? notificationAgentName(InboxNotification n) => _str(n, 'agentName');

/// The agent's id from metadata — seeds [AgentAvatar]'s deterministic tint so
/// the color matches the Agents list. Falls back to an empty string.
String notificationAgentId(InboxNotification n) => _str(n, 'agentId') ?? '';

/// The agent's custom icon color from metadata (`agentIconColor`, hex string)
/// — passed straight to [AgentAvatar] so a custom-colored agent looks 1:1 with
/// the Agents list. Null when the backend sent none; the avatar then degrades
/// to its deterministic per-icon / per-id tint.
String? notificationAgentIconColor(InboxNotification n) =>
    _str(n, 'agentIconColor');

/// Resolves the in-app navigation target for a notification's `actionDeepLink`
/// metadata (sent by the backend, e.g. `/agents/{id}`,
/// `/vaults/{vaultId}/grants/{grantId}`, `/vaults/{vaultId}/entries/{entryId}`).
///
/// Mobile only has agent- and vault-detail screens, so grant/entry deep-links
/// collapse to their owning vault. Returns null when there is no usable target
/// — the card then renders without a footer.
String? notificationDeepLink(InboxNotification n) {
  final raw = _str(n, 'actionDeepLink');
  if (raw != null) {
    final segments =
        raw.split('/').where((part) => part.isNotEmpty).toList(growable: false);
    if (segments.length >= 2) {
      switch (segments[0]) {
        case 'agents':
          return AppRoutes.agentDetail(segments[1]);
        case 'vaults':
          // Any vault sub-resource (grant/entry) collapses to vault detail.
          return AppRoutes.vaultDetail(segments[1]);
      }
    }
  }
  // Fallback to ids in metadata when the backend sent no deep-link.
  final agentId = _str(n, 'agentId');
  if (agentId != null) return AppRoutes.agentDetail(agentId);
  final vaultId = _str(n, 'vaultId');
  if (vaultId != null) return AppRoutes.vaultDetail(vaultId);
  return null;
}

/// The kind of surface a notification's "View" link points at — drives the
/// contextual footer label (View Agent / View Access / View Entry).
enum NotificationViewTarget { agent, access, entry }

/// Classifies a notification's deep-link target so the "View" footer can carry
/// a contextual label instead of a generic "View". Derives the target from the
/// `actionDeepLink` prefix first (authoritative), then falls back to the
/// notification [type]. Returns null when the type/link is unknown — the caller
/// then shows no footer.
NotificationViewTarget? notificationViewTarget(InboxNotification n) {
  final raw = _str(n, 'actionDeepLink');
  if (raw != null) {
    final segments =
        raw.split('/').where((part) => part.isNotEmpty).toList(growable: false);
    if (segments.isNotEmpty) {
      switch (segments[0]) {
        case 'agents':
          return NotificationViewTarget.agent;
        case 'vaults':
          // /vaults/{id}/entries/... → entry, /vaults/{id}/grants/... → access,
          // bare /vaults/{id} → access (grant context).
          if (segments.length >= 3 && segments[2] == 'entries') {
            return NotificationViewTarget.entry;
          }
          return NotificationViewTarget.access;
      }
    }
  }
  switch (n.type) {
    case 'agent_pending':
    case 'agent_approved':
      return NotificationViewTarget.agent;
    case 'grant_pending':
    case 'grant_approved':
    case 'grant_denied':
    case 'grant_revoked':
      return NotificationViewTarget.access;
    case 'credential_stale':
      return NotificationViewTarget.entry;
    default:
      return null;
  }
}

/// Localized contextual "View" label for a notification's footer link.
String notificationViewLabel(AppLocalizations l10n, NotificationViewTarget t) {
  return switch (t) {
    NotificationViewTarget.agent => l10n.inboxViewAgent,
    NotificationViewTarget.access => l10n.inboxViewAccess,
    NotificationViewTarget.entry => l10n.inboxViewEntry,
  };
}

/// Localized error copy for the inbox.
String notificationErrorMessage(
  AppLocalizations l10n,
  NotificationCenterErrorKind kind,
) {
  return switch (kind) {
    NotificationCenterErrorKind.forbidden => l10n.inboxErrorForbidden,
    NotificationCenterErrorKind.networkError => l10n.inboxErrorNetwork,
    NotificationCenterErrorKind.serverError ||
    NotificationCenterErrorKind.unknown => l10n.inboxErrorUnknown,
  };
}

// ── helpers ─────────────────────────────────────────────────────────────

String _entryLabel(AppLocalizations l10n, InboxNotification n) {
  final entry = _str(n, 'entryLabel');
  final vault = _str(n, 'vaultName');
  if (entry == null) return '';
  return vault == null ? entry : '$entry · $vault';
}

String? _str(InboxNotification n, String key) {
  final value = n.metadata[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

String _name(InboxNotification n, String key, String fallback) =>
    _str(n, key) ?? fallback;

String _humanize(String type) {
  return type
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
