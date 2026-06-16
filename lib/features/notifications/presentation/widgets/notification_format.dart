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
String notificationTitle(AppLocalizations l10n, InboxNotification n) {
  final agent = _name(n, 'agentName', l10n.notifUnnamedAgent);
  switch (n.type) {
    case 'grant_pending':
      return l10n.notifTitleGrantPending(agent);
    case 'agent_pending':
      return l10n.notifTitleAgentPending(agent);
    case 'agent_approved':
      return l10n.notifTitleAgentApproved(agent);
    case 'grant_revoked':
      return l10n.notifTitleGrantRevoked(agent);
    case 'grant_approved':
      return l10n.notifTitleGrantApproved(agent);
    case 'grant_denied':
      return l10n.notifTitleGrantDenied(agent);
    case 'credential_stale':
      return l10n.notifTitleCredentialStale;
    default:
      return _humanize(n.type);
  }
}

/// A short subtitle under the title (e.g. "requests access").
String notificationSubtitle(AppLocalizations l10n, InboxNotification n) {
  switch (n.type) {
    case 'grant_pending':
      return l10n.notifSubGrantPending;
    case 'agent_pending':
      return l10n.notifSubAgentPending;
    case 'agent_approved':
      return l10n.notifSubAgentApproved;
    case 'credential_stale':
      return l10n.notifSubCredentialStale(
        _name(n, 'agentName', l10n.notifUnnamedAgent),
      );
    case 'grant_revoked':
    case 'grant_approved':
    case 'grant_denied':
      return l10n.notifSubGrantUpdate;
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

/// Agent identity rows — agent id, host, IP, and the agent's public key. Each
/// renders only when the backend sent it (graceful degradation). The public
/// key surfaces under a "Public key" label, never a vague "key".
List<({String label, String value})> _agentRows(
  AppLocalizations l10n,
  InboxNotification n,
) {
  return [
    if (_has(n, 'agentId'))
      (label: l10n.notifRowAgentId, value: _str(n, 'agentId')!),
    if (_has(n, 'host'))
      (label: l10n.notifRowHost, value: _str(n, 'host')!),
    if (_has(n, 'ip')) (label: l10n.notifRowIp, value: _str(n, 'ip')!),
    if (_keyHint(n) != null)
      (label: l10n.notifRowPublicKey, value: _keyHint(n)!),
  ];
}

/// Short public-key hint — prefers an explicit `keyHint`, else truncates a
/// raw `agentPublicKey` so the full key never floods the card.
String? _keyHint(InboxNotification n) {
  final hint = _str(n, 'keyHint');
  if (hint != null) return hint;
  final key = _str(n, 'agentPublicKey');
  if (key == null) return null;
  return key.length <= 16 ? key : '${key.substring(0, 8)}…${key.substring(key.length - 6)}';
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

/// History status pill (label + color) for a resolved notification, derived
/// from its type. Returns null for types that carry no meaningful status.
/// [brightness] picks the on-palette amber (darker in light mode) for denied.
({String label, Color color})? notificationStatusPill(
  AppLocalizations l10n,
  InboxNotification n,
  Brightness brightness,
) {
  switch (n.type) {
    case 'grant_approved':
    case 'agent_approved':
      return (label: l10n.notifStatusActive, color: AppColors.positiveAccent);
    case 'grant_revoked':
      return (label: l10n.notifStatusRevoked, color: AppColors.brandRed);
    case 'grant_denied':
      return (label: l10n.notifStatusDenied, color: AppColors.premium(brightness));
    default:
      return null;
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
