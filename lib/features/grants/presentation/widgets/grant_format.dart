import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/grant.dart';
import '../../domain/exceptions/grants_exceptions.dart';

/// Resolves a localized message for a [GrantsErrorKind]. Keeps user-facing
/// text out of the data/domain layer.
String grantsErrorMessage(AppLocalizations l10n, GrantsErrorKind kind) {
  return switch (kind) {
    GrantsErrorKind.notFound => l10n.grantsErrorNotFound,
    GrantsErrorKind.forbidden => l10n.grantsErrorForbidden,
    GrantsErrorKind.validation => l10n.grantsErrorValidation,
    GrantsErrorKind.networkError => l10n.grantsErrorNetwork,
    GrantsErrorKind.cryptoFailure => l10n.grantsErrorCrypto,
    GrantsErrorKind.unknown => l10n.grantsErrorUnknown,
  };
}

/// Localized label for a grant [status].
String grantStatusLabel(AppLocalizations l10n, GrantStatus status) {
  return switch (status) {
    GrantStatus.pending => l10n.grantStatusPending,
    GrantStatus.active => l10n.grantStatusActive,
    GrantStatus.denied => l10n.grantStatusDenied,
    GrantStatus.revoked => l10n.grantStatusRevoked,
    GrantStatus.expired => l10n.grantStatusExpired,
    GrantStatus.consumed => l10n.grantStatusConsumed,
    GrantStatus.superseded => l10n.grantStatusSuperseded,
    GrantStatus.unknown => l10n.responseUnknownValue,
  };
}

/// Brand colour for a grant [status] — single source of truth shared by the
/// status chip, the org-grant pill, and the filter chips. Active=teal/green,
/// Pending=amber, Denied/Revoked=red, Expired/Consumed=grey.
Color grantStatusColor(GrantStatus status) {
  return switch (status) {
    GrantStatus.pending => AppColors.premiumAmber,
    GrantStatus.active => AppColors.positiveAccent,
    GrantStatus.denied || GrantStatus.revoked => AppColors.brandRed,
    GrantStatus.expired ||
    GrantStatus.consumed ||
    GrantStatus.superseded ||
    GrantStatus.unknown => AppColors.textTertiary,
  };
}

/// Localized label for a grant [scope].
String grantScopeLabel(AppLocalizations l10n, GrantScope scope) {
  return switch (scope) {
    GrantScope.full => l10n.grantScopeFull,
    GrantScope.granular => l10n.grantScopeGranular,
    GrantScope.scriptExecution => l10n.grantScopeScriptExecution,
    GrantScope.unknown => l10n.responseUnknownValue,
  };
}

/// Display name for the agent attached to a [grant], falling back to a
/// generic label when the agent is unnamed.
String grantAgentDisplayName(AppLocalizations l10n, Grant grant) {
  final name = grant.agentName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return l10n.grantUnnamedAgent;
}

// ── org-grant (Approvals history) helpers ──────────────────────────────────

/// The actor who last acted on the grant, by status: revoked → revokedByName,
/// denied → deniedByName, else createdByName. Falls back to "System" when the
/// actor is unknown (e.g. an automatic expiry). Mirrors the web `grantActorName`.
String orgGrantActorName(AppLocalizations l10n, Grant grant) {
  final name = switch (grant.status) {
    GrantStatus.revoked => grant.revokedByName,
    GrantStatus.denied => grant.deniedByName,
    GrantStatus.superseded => null,
    _ => grant.createdByName,
  };
  final trimmed = name?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  return l10n.orgGrantActorSystem;
}

/// One-line access-policy summary: remaining uses, expiry date, or unlimited.
String orgGrantAccessSummary(AppLocalizations l10n, Grant grant) {
  if (grant.queryLimit != null) {
    final left = (grant.queryLimit! - (grant.queryCount ?? 0)).clamp(
      0,
      grant.queryLimit!,
    );
    return l10n.orgGrantUsesLeft(left, grant.queryLimit!);
  }
  if (grant.expiresAt != null) {
    return l10n.orgGrantExpiresOn(_isoDate(grant.expiresAt!));
  }
  return l10n.orgGrantUnlimited;
}

/// The single contextual reason row shown on every card: denied → deny reason,
/// revoked → revoke reason, otherwise the agent's access (request) reason. Falls
/// back to the access-reason label with an em dash so the row always renders
/// (keeps cards equal height). Mirrors the web `contextualReason`.
({String label, String text}) orgGrantContextualReason(
  AppLocalizations l10n,
  Grant grant,
) {
  if (grant.status == GrantStatus.denied &&
      (grant.denyReason?.trim().isNotEmpty ?? false)) {
    return (label: l10n.orgGrantRowDenyReason, text: grant.denyReason!.trim());
  }
  if (grant.status == GrantStatus.superseded) {
    return (label: l10n.orgGrantRowReason, text: l10n.orgGrantSupersededReason);
  }
  final reason = grant.reason?.trim();
  return (
    label: l10n.orgGrantRowReason,
    text: reason != null && reason.isNotEmpty ? reason : '—',
  );
}

/// Localised "x ago" for the card header timestamp — reuses the vault
/// relative-time ARB keys, falling back to a numeric ISO date past 30 days.
String grantRelativeTime(AppLocalizations l10n, DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return l10n.vaultUpdatedNow;
  if (diff.inMinutes < 60) return l10n.vaultUpdatedMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.vaultUpdatedHoursAgo(diff.inHours);
  if (diff.inDays < 30) return l10n.vaultUpdatedDaysAgo(diff.inDays);
  return _isoDate(dt);
}

String _isoDate(DateTime dt) {
  final local = dt.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
