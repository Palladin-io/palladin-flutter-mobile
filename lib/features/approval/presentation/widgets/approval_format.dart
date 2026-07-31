import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/pending_grant.dart';
import '../../domain/exceptions/approval_exceptions.dart';

/// Resolves a localized message for an [ApprovalErrorKind].
String approvalErrorMessage(AppLocalizations l10n, ApprovalErrorKind kind) {
  return switch (kind) {
    ApprovalErrorKind.notFound => l10n.approvalErrorNotFound,
    ApprovalErrorKind.forbidden => l10n.approvalErrorForbidden,
    ApprovalErrorKind.validation => l10n.approvalErrorValidation,
    ApprovalErrorKind.conflict => l10n.approvalErrorValidation,
    ApprovalErrorKind.networkError => l10n.approvalErrorNetwork,
    ApprovalErrorKind.cryptoFailure => l10n.approvalErrorCrypto,
    ApprovalErrorKind.vaultLocked => l10n.approvalErrorVaultLocked,
    ApprovalErrorKind.unknown => l10n.approvalErrorUnknown,
  };
}

/// Display name for the agent on a pending grant, with a fallback.
String pendingAgentDisplayName(AppLocalizations l10n, PendingGrant grant) {
  final name = grant.agentName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return l10n.approvalUnnamedAgent;
}

/// Display label for the requested entry, with a fallback.
String pendingEntryLabel(AppLocalizations l10n, PendingGrant grant) {
  final label = grant.entryLabel?.trim();
  if (label != null && label.isNotEmpty) return label;
  return l10n.approvalEntryUnknown;
}
