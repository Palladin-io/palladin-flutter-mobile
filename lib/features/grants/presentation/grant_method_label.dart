import '../../../l10n/generated/app_localizations.dart';
import '../domain/entities/grant_method.dart';

/// Localized label for a [GrantMethod] — shared by the methods picker and the org
/// grant card so the user never sees raw enum identifiers (`GET` / `EXEC` / `INJECT`).
String grantMethodLabel(AppLocalizations l10n, GrantMethod m) => switch (m) {
  GrantMethod.get => l10n.approvalMethodGetLabel,
  GrantMethod.exec => l10n.approvalMethodExecLabel,
  GrantMethod.inject => l10n.approvalMethodInjectLabel,
};
