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
    AuditEventType.apikeyCreated => l10n.auditEventApiKeyCreated,
    AuditEventType.apikeyActivated => l10n.auditEventApiKeyActivated,
    AuditEventType.apikeyRevoked => l10n.auditEventApiKeyRevoked,
    AuditEventType.apikeyDeleted => l10n.auditEventApiKeyDeleted,
    AuditEventType.orgCreated => l10n.auditEventOrgCreated,
    AuditEventType.orgUpdated => l10n.auditEventOrgUpdated,
    AuditEventType.userSignedUp => l10n.auditEventUserSignedUp,
    AuditEventType.accountSetupCompleted =>
      l10n.auditEventAccountSetupCompleted,
    AuditEventType.accountRecoveryCompleted =>
      l10n.auditEventAccountRecoveryCompleted,
    AuditEventType.unknown =>
      rawEventType.isEmpty ? l10n.auditEventUnknown : rawEventType,
  };
}

/// Brand color for an audit [eventType] — the dot/accent shown on each row.
/// Positive/success = teal, destructive/denied = red, **pending = peach (only
/// an outstanding access request)**, neutral lifecycle/creation = blue,
/// terminal/inert (consumed/expired) = grey. Single source of truth, mirrored
/// by the legend.
Color auditEventColor(AuditEventType eventType) {
  return switch (eventType) {
    // Positive / success — teal.
    AuditEventType.credentialAccessed ||
    AuditEventType.grantCreated ||
    AuditEventType.grantApproved ||
    AuditEventType.agentReactivated ||
    AuditEventType.apikeyActivated ||
    AuditEventType.accountSetupCompleted ||
    AuditEventType.accountRecoveryCompleted => AppColors.positiveAccent,
    // Destructive / denied — red.
    AuditEventType.credentialAccessDenied ||
    AuditEventType.grantDenied ||
    AuditEventType.grantRevoked ||
    AuditEventType.agentBlocked ||
    AuditEventType.agentDeleted ||
    AuditEventType.vaultDeleted ||
    AuditEventType.entryDeleted ||
    AuditEventType.apikeyRevoked ||
    AuditEventType.apikeyDeleted => AppColors.brandRed,
    // Pending — peach. Only an outstanding access request is "pending".
    AuditEventType.grantRequested => AppColors.vaultPeach,
    // Neutral lifecycle / creation — blue.
    AuditEventType.agentEnrolled ||
    AuditEventType.vaultCreated ||
    AuditEventType.vaultUpdated ||
    AuditEventType.entryCreated ||
    AuditEventType.entryUpdated ||
    AuditEventType.apikeyCreated ||
    AuditEventType.orgCreated ||
    AuditEventType.orgUpdated ||
    AuditEventType.userSignedUp => AppColors.vaultBlue,
    // Terminal / inert — grey.
    AuditEventType.grantConsumed ||
    AuditEventType.grantExpired ||
    AuditEventType.unknown => AppColors.textTertiary,
  };
}

/// Representative color for an [AuditEventGroup] — drives the legend swatches
/// and the in-sheet group chips. Each is the color of the group's primary
/// (happy-path) event so the swatch reads consistently with the rows: access
/// success (teal), grant success (teal), creation/lifecycle (blue).
Color auditGroupColor(AuditEventGroup group) {
  return switch (group) {
    AuditEventGroup.credentialAccess => AppColors.positiveAccent,
    AuditEventGroup.grants => AppColors.positiveAccent,
    AuditEventGroup.vaultEntry => AppColors.vaultBlue,
    AuditEventGroup.agentLifecycle => AppColors.vaultBlue,
    AuditEventGroup.apiKeys => AppColors.vaultBlue,
    AuditEventGroup.orgAccount => AppColors.vaultBlue,
  };
}

/// Material icon for an [AuditEventGroup], used by the quick-filter chips and
/// the legend modal.
IconData auditGroupIcon(AuditEventGroup group) {
  return switch (group) {
    AuditEventGroup.credentialAccess => Icons.vpn_key_outlined,
    AuditEventGroup.grants => Icons.verified_user_outlined,
    AuditEventGroup.vaultEntry => Icons.shield_outlined,
    AuditEventGroup.agentLifecycle => Icons.smart_toy_outlined,
    AuditEventGroup.apiKeys => Icons.key_outlined,
    AuditEventGroup.orgAccount => Icons.corporate_fare,
  };
}

/// Localized label for an [AuditEventGroup] (chip + legend heading).
String auditGroupLabel(AppLocalizations l10n, AuditEventGroup group) {
  return switch (group) {
    AuditEventGroup.credentialAccess => l10n.auditGroupCredentialAccess,
    AuditEventGroup.grants => l10n.auditGroupGrants,
    AuditEventGroup.vaultEntry => l10n.auditGroupVaultEntry,
    AuditEventGroup.agentLifecycle => l10n.auditGroupAgentLifecycle,
    AuditEventGroup.apiKeys => l10n.auditGroupApiKeys,
    AuditEventGroup.orgAccount => l10n.auditGroupOrgAccount,
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

/// Resolves the display name of the actor behind an audit [entry].
///
/// Prefers the names the backend denormalizes server-side ([AuditLogEntry.actorName]
/// / [AuditLogEntry.agentName]); falls back to the client-side agent-name
/// cache and finally a shortened id. This keeps the UI correct even before
/// the agents cache resolves.
String auditActorName(
  AppLocalizations l10n,
  AuditLogEntry entry,
  Map<String, String> agentNames,
) {
  final serverName = entry.actorName?.trim();
  if (serverName != null && serverName.isNotEmpty) return serverName;

  return switch (entry.actorType) {
    AuditActorType.agent => _agentName(l10n, entry, agentNames),
    AuditActorType.user => l10n.auditActorOwner,
    AuditActorType.system => l10n.auditActorSystem,
  };
}

String _agentName(
  AppLocalizations l10n,
  AuditLogEntry entry,
  Map<String, String> agentNames,
) {
  final serverAgentName = entry.agentName?.trim();
  if (serverAgentName != null && serverAgentName.isNotEmpty) {
    return serverAgentName;
  }
  final agentId = entry.agentId;
  if (agentId == null) return l10n.auditActorAgent;
  final cached = agentNames[agentId];
  if (cached != null && cached.isNotEmpty) return cached;
  return agentId.length <= 8 ? agentId : '${agentId.substring(0, 8)}…';
}

/// A run of a composed audit sentence. [bold] marks a resolved name (actor
/// or object) so the row can emphasise it, matching the web panel.
class AuditSentenceSpan {
  const AuditSentenceSpan(this.text, {required this.bold});

  final String text;
  final bool bold;
}

// Private sentinel wrapping the bold (name) runs inside an ICU-substituted
// string so they can be recovered (via split) after interpolation. This keeps
// the full sentence as one translatable ICU template per event (clear word
// order per locale) instead of fragmenting it into prefix/verb/suffix keys.
//
// Robustness: `_splitSentence` could only mis-align if an interpolated value
// itself contained the sentinel, so [_mark] strips it from the value first.
// The sentinel is a NUL control char that never legitimately appears in a
// name/label — the strip is purely defensive against hostile backend input.
const String _boldMark = '\u0000';
String _mark(String value) =>
    '$_boldMark${value.replaceAll(_boldMark, '')}$_boldMark';

/// Composes a full "who did what to which object" sentence for an audit
/// [entry], with actor / object / agent names marked for bold rendering.
///
/// Returns `null` for the event types that keep the legacy label+actor
/// rendering (grant.* / credential.* / unknown) — the row falls back to those.
/// Every name resolves to a human-readable value (server-denormalized
/// `actorName` / `agentName` / `entryLabel`, or `metadata.name`/`keyName`),
/// with a localized generic fallback ("a vault", …) — never an id or a
/// placeholder.
List<AuditSentenceSpan>? auditEventSentence(
  AppLocalizations l10n,
  AuditLogEntry entry,
  Map<String, String> agentNames,
) {
  final actor = _mark(_sentenceActor(l10n, entry, agentNames));
  final objName = _objectName(entry);
  String obj(String Function(String) named, String fallback) =>
      (objName != null && objName.isNotEmpty)
      ? named(_mark(objName))
      : fallback;

  final agentName = _sentenceAgentName(entry, agentNames);
  final agentObj = agentName != null
      ? l10n.auditObjectAgentNamed(_mark(agentName))
      : l10n.auditObjectAgent;

  final vault = obj(l10n.auditObjectVaultNamed, l10n.auditObjectVault);
  final item = obj(l10n.auditObjectEntryNamed, l10n.auditObjectEntry);
  final org = obj(l10n.auditObjectOrgNamed, l10n.auditObjectOrg);
  final apiKey = obj(l10n.auditObjectApiKeyNamed, l10n.auditObjectApiKey);

  final raw = switch (entry.eventType) {
    AuditEventType.vaultCreated => l10n.auditSentenceCreated(actor, vault),
    AuditEventType.vaultUpdated => l10n.auditSentenceUpdated(actor, vault),
    AuditEventType.vaultDeleted => l10n.auditSentenceDeleted(actor, vault),
    AuditEventType.entryCreated => l10n.auditSentenceCreated(actor, item),
    AuditEventType.entryUpdated => l10n.auditSentenceUpdated(actor, item),
    AuditEventType.entryDeleted => l10n.auditSentenceDeleted(actor, item),
    AuditEventType.orgCreated => l10n.auditSentenceCreated(actor, org),
    AuditEventType.orgUpdated => l10n.auditSentenceUpdated(actor, org),
    AuditEventType.apikeyCreated => l10n.auditSentenceCreated(actor, apiKey),
    AuditEventType.apikeyActivated => l10n.auditSentenceActivated(
      actor,
      apiKey,
    ),
    AuditEventType.apikeyRevoked => l10n.auditSentenceRevoked(actor, apiKey),
    AuditEventType.apikeyDeleted => l10n.auditSentenceDeleted(actor, apiKey),
    AuditEventType.agentBlocked => l10n.auditSentenceBlocked(actor, agentObj),
    AuditEventType.agentReactivated => l10n.auditSentenceReactivated(
      actor,
      agentObj,
    ),
    AuditEventType.agentDeleted => l10n.auditSentenceDeleted(actor, agentObj),
    AuditEventType.agentEnrolled => l10n.auditSentenceAgentEnrolled(
      agentName != null ? _mark(agentName) : l10n.auditActorAgent,
    ),
    AuditEventType.userSignedUp => l10n.auditSentenceUserSignedUp(actor),
    AuditEventType.accountSetupCompleted =>
      l10n.auditSentenceAccountSetupCompleted(actor),
    AuditEventType.accountRecoveryCompleted =>
      l10n.auditSentenceAccountRecoveryCompleted(actor),
    _ => null,
  };
  if (raw == null) return null;
  return _splitSentence(raw);
}

List<AuditSentenceSpan> _splitSentence(String raw) {
  final parts = raw.split(_boldMark);
  final spans = <AuditSentenceSpan>[];
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    spans.add(AuditSentenceSpan(parts[i], bold: i.isOdd));
  }
  return spans;
}

/// The acting party for a sentence: server `actorName`, else the agent name,
/// else a localized "Unknown user" (never an id).
String _sentenceActor(
  AppLocalizations l10n,
  AuditLogEntry entry,
  Map<String, String> agentNames,
) {
  final actorName = entry.actorName?.trim();
  if (actorName != null && actorName.isNotEmpty) return actorName;
  final agent = _sentenceAgentName(entry, agentNames);
  if (agent != null) return agent;
  return l10n.auditUserUnknown;
}

/// The agent a sentence is about (server `agentName`, else cached name), or
/// `null` when unknown.
String? _sentenceAgentName(
  AuditLogEntry entry,
  Map<String, String> agentNames,
) {
  final name = entry.agentName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final id = entry.agentId;
  if (id != null) {
    final cached = agentNames[id]?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
  }
  return null;
}

/// The object name a sentence acts on — entry label, else `metadata.name`
/// (vault / org) or `metadata.keyName` (api key). `null` when none is known.
String? _objectName(AuditLogEntry entry) {
  final label = entry.entryLabel?.trim();
  if (label != null && label.isNotEmpty) return label;
  final name = entry.metadata['name']?.trim();
  if (name != null && name.isNotEmpty) return name;
  final keyName = entry.metadata['keyName']?.trim();
  if (keyName != null && keyName.isNotEmpty) return keyName;
  return null;
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
