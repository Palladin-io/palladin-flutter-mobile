import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/entities/audit_log_entry.dart';
import '../domain/exceptions/audit_exceptions.dart';

/// Localized label for an audit [eventType]. Unknown events fall back to
/// the raw wire string so a new backend event still reads sensibly.
String auditEventLabel(
  AppLocalizations l10n,
  AuditEventType eventType,
  String rawEventType,
) {
  return switch (eventType) {
    AuditEventType.grantCreated => l10n.auditEventGrantCreated,
    AuditEventType.grantRequested => l10n.auditEventGrantRequested,
    AuditEventType.grantApproved => l10n.auditEventGrantApproved,
    AuditEventType.grantDenied => l10n.auditEventGrantDenied,
    AuditEventType.grantRevoked => l10n.auditEventGrantRevoked,
    AuditEventType.grantConsumed => l10n.auditEventGrantConsumed,
    AuditEventType.grantExpired => l10n.auditEventGrantExpired,
    AuditEventType.credentialAccessed => l10n.auditEventCredentialAccessed,
    AuditEventType.credentialAccessDenied =>
      l10n.auditEventCredentialAccessDenied,
    AuditEventType.agentEnrolled => l10n.auditEventAgentEnrolled,
    AuditEventType.agentBlocked => l10n.auditEventAgentBlocked,
    AuditEventType.agentReactivated => l10n.auditEventAgentReactivated,
    AuditEventType.agentDeleted => l10n.auditEventAgentDeleted,
    AuditEventType.vaultCreated => l10n.auditEventVaultCreated,
    AuditEventType.vaultUpdated => l10n.auditEventVaultUpdated,
    AuditEventType.vaultDeleted => l10n.auditEventVaultDeleted,
    AuditEventType.entryCreated => l10n.auditEventEntryCreated,
    AuditEventType.entryUpdated => l10n.auditEventEntryUpdated,
    AuditEventType.entryDeleted => l10n.auditEventEntryDeleted,
    AuditEventType.unknown =>
      rawEventType.isEmpty ? l10n.auditEventUnknown : rawEventType,
  };
}

/// Brand color for an audit [eventType] — the dot/accent shown on each
/// row. Positive actions = teal, destructive/denied = red, neutral
/// lifecycle = blue, terminal/expired = grey. Single source of truth.
Color auditEventColor(AuditEventType eventType) {
  return switch (eventType) {
    AuditEventType.credentialAccessed ||
    AuditEventType.grantCreated ||
    AuditEventType.grantApproved ||
    AuditEventType.grantConsumed =>
      AppColors.positiveAccent,
    AuditEventType.credentialAccessDenied ||
    AuditEventType.grantDenied ||
    AuditEventType.grantRevoked ||
    AuditEventType.agentBlocked ||
    AuditEventType.agentDeleted ||
    AuditEventType.vaultDeleted ||
    AuditEventType.entryDeleted =>
      AppColors.brandRed,
    AuditEventType.grantRequested ||
    AuditEventType.agentEnrolled ||
    AuditEventType.agentReactivated ||
    AuditEventType.vaultCreated ||
    AuditEventType.vaultUpdated ||
    AuditEventType.entryCreated ||
    AuditEventType.entryUpdated =>
      AppColors.vaultBlue,
    AuditEventType.grantExpired || AuditEventType.unknown =>
      AppColors.textTertiary,
  };
}

/// Locale-aware date+time for an audit row — e.g. `27.06.2026 10:05` (pl)
/// or `6/27/2026 10:05` (en). Date symbols for the app locales are loaded
/// by `GlobalMaterialLocalizations`, so [localeName] is safe to pass.
String auditTimestamp(DateTime dt, String localeName) {
  return DateFormat.yMd(localeName).add_Hm().format(dt.toLocal());
}

/// Locale-aware date only — used by the filter date-range fields.
String auditDate(DateTime dt, String localeName) {
  return DateFormat.yMd(localeName).format(dt.toLocal());
}

/// Resolves the display name of the actor behind an audit [entry]:
/// the resolved agent name for agent actors, a generic owner label for
/// user actors, and a system label for automatic events.
String auditActorName(
  AppLocalizations l10n,
  AuditLogEntry entry,
  Map<String, String> agentNames,
) {
  return switch (entry.actorType) {
    AuditActorType.agent => _agentName(l10n, entry.agentId, agentNames),
    AuditActorType.user => l10n.auditActorOwner,
    AuditActorType.system => l10n.auditActorSystem,
  };
}

String _agentName(
  AppLocalizations l10n,
  String? agentId,
  Map<String, String> agentNames,
) {
  if (agentId == null) return l10n.auditActorAgent;
  final name = agentNames[agentId];
  if (name != null && name.isNotEmpty) return name;
  return agentId.length <= 8 ? agentId : '${agentId.substring(0, 8)}…';
}

/// Localized message for an [AuditErrorKind]. Keeps user-facing text out
/// of the data/domain layers.
String auditErrorMessage(AppLocalizations l10n, AuditErrorKind kind) {
  return switch (kind) {
    AuditErrorKind.forbidden => l10n.auditErrorForbidden,
    AuditErrorKind.notFound => l10n.auditErrorNotFound,
    AuditErrorKind.networkError => l10n.auditErrorNetwork,
    AuditErrorKind.unknown => l10n.auditErrorGeneric,
  };
}
