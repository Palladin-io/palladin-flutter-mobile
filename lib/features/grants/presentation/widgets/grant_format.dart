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
  };
}

/// Localized label for a grant [scope].
String grantScopeLabel(AppLocalizations l10n, GrantScope scope) {
  return switch (scope) {
    GrantScope.full => l10n.grantScopeFull,
    GrantScope.granular => l10n.grantScopeGranular,
  };
}

/// Display name for the agent attached to a [grant], falling back to a
/// generic label when the agent is unnamed.
String grantAgentDisplayName(AppLocalizations l10n, Grant grant) {
  final name = grant.agentName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return l10n.grantUnnamedAgent;
}
