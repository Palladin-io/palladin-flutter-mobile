import 'package:flutter/material.dart';

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
List<({String label, String value})> notificationRows(
  AppLocalizations l10n,
  InboxNotification n,
) {
  final entry = _entryLabel(l10n, n);
  switch (n.type) {
    case 'grant_pending':
      return [
        (label: l10n.notifRowEntry, value: entry),
        if (_has(n, 'methods'))
          (label: l10n.notifRowMethods, value: _str(n, 'methods')!),
        if (_has(n, 'reason'))
          (label: l10n.notifRowReason, value: _str(n, 'reason')!),
      ];
    case 'agent_pending':
      return _agentRows(l10n, n);
    case 'agent_approved':
      return [
        ..._agentRows(l10n, n),
        if (_has(n, 'actorName'))
          (label: l10n.notifRowBy, value: _str(n, 'actorName')!),
      ];
    case 'credential_stale':
      return [
        (label: l10n.notifRowEntry, value: entry),
        if (_has(n, 'error'))
          (label: l10n.notifRowError, value: _str(n, 'error')!),
      ];
    case 'grant_revoked':
    case 'grant_denied':
      return [
        (label: l10n.notifRowEntry, value: entry),
        if (_has(n, 'reason'))
          (label: l10n.notifRowReason, value: _str(n, 'reason')!),
        if (_has(n, 'actorName'))
          (label: l10n.notifRowBy, value: _str(n, 'actorName')!),
      ];
    case 'grant_approved':
      return [
        (label: l10n.notifRowEntry, value: entry),
      ];
    default:
      return [
        if (entry.isNotEmpty) (label: l10n.notifRowEntry, value: entry),
      ];
  }
}

/// Agent identity rows — capped at 3 so the card stays compact. Order:
/// Public key → Agent Id → Host / Ip. Host and IP are merged into a single
/// "Host / Ip" row (host shortened) to save a row. Each renders only when the
/// backend sent it (graceful degradation). The public key surfaces under a
/// "Public key" label, never a vague "key".
List<({String label, String value})> _agentRows(
  AppLocalizations l10n,
  InboxNotification n,
) {
  final hostIp = _hostIp(n);
  return [
    if (_keyHint(n) != null)
      (label: l10n.notifRowPublicKey, value: _keyHint(n)!),
    if (_has(n, 'agentId'))
      (label: l10n.notifRowAgentId, value: _str(n, 'agentId')!),
    if (hostIp != null) (label: l10n.notifRowHostIp, value: hostIp),
  ];
}

/// Combines host + IP into one "host / ip" value (host shortened so a long
/// FQDN never floods the row). Returns just whichever part is present, or null
/// when neither is.
String? _hostIp(InboxNotification n) {
  final host = _str(n, 'host');
  final ip = _str(n, 'ip');
  final shortHost = host == null
      ? null
      : (host.length <= 28 ? host : '${host.substring(0, 27)}…');
  if (shortHost != null && ip != null) return '$shortHost / $ip';
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

/// Status pill (label + color) shown under the date on **every** card.
/// Open action-required items (agent_pending / grant_pending / credential_stale)
/// read "Pending"; terminal items read Active / Denied / Revoked.
/// [brightness] picks the on-palette amber (darker in light mode) for
/// pending / denied.
({String label, Color color}) notificationStatusPill(
  AppLocalizations l10n,
  InboxNotification n,
  Brightness brightness,
) {
  if (n.isOpenAction) {
    return (label: l10n.notifStatusPending, color: AppColors.premium(brightness));
  }
  switch (n.type) {
    case 'grant_approved':
    case 'agent_approved':
      return (label: l10n.notifStatusActive, color: AppColors.positiveAccent);
    case 'grant_revoked':
      return (label: l10n.notifStatusRevoked, color: AppColors.brandRed);
    case 'grant_denied':
      return (label: l10n.notifStatusDenied, color: AppColors.premium(brightness));
    default:
      // Resolved/informational with no specific terminal status — show
      // "Active" as a neutral positive marker so the layout stays consistent.
      return (label: l10n.notifStatusActive, color: AppColors.positiveAccent);
  }
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

bool _has(InboxNotification n, String key) => _str(n, key) != null;

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
