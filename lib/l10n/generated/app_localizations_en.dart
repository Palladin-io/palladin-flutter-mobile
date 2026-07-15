// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Palladin';

  @override
  String get welcomeMessage => 'Welcome to Palladin';

  @override
  String get loginRotatingZeroKnowledge => 'Zero-knowledge by design.';

  @override
  String get loginRotatingForAgents => 'Built for AI agents.';

  @override
  String get loginRotatingYourKeys => 'Your keys, your rules.';

  @override
  String get loginRotatingEncrypted => 'Always encrypted.';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get continueWithX => 'Sign in with X';

  @override
  String get continueWithEmail => 'Continue with Email';

  @override
  String get authOtherSignInOptions => 'Other sign-in options';

  @override
  String get legalFooterPrefix => 'By continuing, you agree to our ';

  @override
  String get legalTermsLink => 'Terms';

  @override
  String get legalFooterSeparator => ' & ';

  @override
  String get legalPrivacyLink => 'Privacy Policy';

  @override
  String get legalLinkOpenError => 'Unable to open this link.';

  @override
  String providerComingSoon(String provider) {
    return '$provider sign-in coming soon';
  }

  @override
  String get errorServerNotResponding =>
      'Server not responding. Please try again.';

  @override
  String get errorCannotConnectToServer =>
      'Cannot connect to server. Check your connection and try again.';

  @override
  String get errorConnectionFailed => 'Connection error. Please try again.';

  @override
  String get errorInvalidServerResponse =>
      'Invalid server response. Please try again.';

  @override
  String get onboardingMasterPasswordTitle => 'Set Your Master Password';

  @override
  String get onboardingMasterPasswordSubtitle =>
      'This password encrypts your vault locally. We never see it.';

  @override
  String get onboardingMasterPasswordLabel => 'Master Password';

  @override
  String get onboardingConfirmPasswordLabel => 'Confirm Password';

  @override
  String get onboardingPasswordRequirementsTitle => 'Requirements';

  @override
  String get onboardingPasswordReqLength => 'At least 12 characters';

  @override
  String get onboardingPasswordReqCase => 'Uppercase & lowercase';

  @override
  String get onboardingPasswordReqNumber => 'At least one number';

  @override
  String get onboardingPasswordReqSymbol => 'At least one symbol';

  @override
  String get onboardingPasswordStrengthTooShort => 'Too short';

  @override
  String get onboardingPasswordStrengthWeak => 'Weak password';

  @override
  String get onboardingPasswordStrengthFair => 'Fair password';

  @override
  String get onboardingPasswordStrengthStrong => 'Strong password';

  @override
  String get onboardingPasswordStrengthVeryStrong => 'Very strong password';

  @override
  String get onboardingPasswordsMatch => 'Passwords match';

  @override
  String get onboardingPasswordsDoNotMatch => 'Passwords do not match';

  @override
  String get onboardingContinue => 'Continue';

  @override
  String get onboardingRecoveryTitle => 'Save Your Recovery Key';

  @override
  String get onboardingRecoverySubtitle =>
      'Write this down and store it safely offline. Without it, a forgotten master password means permanent data loss.';

  @override
  String get onboardingRecoveryWarning =>
      'You cannot recover your vault without this key.';

  @override
  String get onboardingRecoveryCopy => 'Copy to Clipboard';

  @override
  String get onboardingRecoveryCopied => 'Recovery key copied to clipboard';

  @override
  String get onboardingRecoveryExport => 'Export as File (.txt)';

  @override
  String get onboardingRecoverySaved => 'I\'ve Saved My Recovery Key';

  @override
  String get onboardingConfirmTitle => 'Confirm Recovery Key';

  @override
  String get onboardingConfirmSubtitle =>
      'Enter the following words from your recovery key to verify you saved it.';

  @override
  String onboardingConfirmWordLabel(int index) {
    return 'Word #$index';
  }

  @override
  String onboardingConfirmWordHint(int index) {
    return 'Enter word #$index';
  }

  @override
  String get onboardingConfirmCorrect => 'Correct';

  @override
  String get onboardingConfirmIncorrect => 'Incorrect';

  @override
  String get onboardingConfirmVerify => 'Verify & Complete Setup';

  @override
  String get onboardingAlreadyCompleted =>
      'This account has already been set up. Please sign in again.';

  @override
  String get unlockTitle => 'Enter your master password';

  @override
  String get unlockPasswordLabel => 'Master Password';

  @override
  String get unlockButton => 'Unlock';

  @override
  String get unlockForgotPassword => 'Forgot password?';

  @override
  String get unlockForgotPasswordComingSoon => 'Recovery flow coming soon';

  @override
  String get unlockWrongPassword =>
      'Incorrect master password. Please try again.';

  @override
  String get unlockSessionExpired =>
      'Your session expired. Please sign in again.';

  @override
  String get unlockBiometricHint => 'Unlock with biometrics';

  @override
  String get unlockBiometricPrompt => 'Authenticate to unlock your vault';

  @override
  String get unlockBiometricPromptTitle => 'Unlock Palladin';

  @override
  String get unlockBiometricEnrollPrompt =>
      'Confirm to enable biometric unlock';

  @override
  String get unlockBiometricUnavailable =>
      'Biometric unlock is not set up on this device. Enter your master password.';

  @override
  String get unlockBiometricFailed =>
      'Biometric authentication failed. Please try again or use your password.';

  @override
  String get unlockLockVault => 'Lock Vault';

  @override
  String get recoveryTitle => 'Recover Your Account';

  @override
  String get recoverySubtitle =>
      'Enter your 24-word recovery key. We\'ll use it to unwrap your vault locally — nothing is sent to our servers unencrypted.';

  @override
  String get recoveryEnterKeyLabel =>
      'Type or paste your 24 recovery words, separated by spaces';

  @override
  String get recoveryPasteButton => 'Paste from Clipboard';

  @override
  String get recoveryShareSubject => 'Palladin Recovery Key';

  @override
  String get recoveryImportButton => 'Import from .txt File';

  @override
  String get recoveryImportComingSoon =>
      'File import coming soon — paste from clipboard instead';

  @override
  String get recoveryNewPasswordTitle => 'Set a New Master Password';

  @override
  String get recoveryNewPasswordSubtitle =>
      'Choose a new master password. It will replace the one you forgot.';

  @override
  String get recoveryNewPasswordLabel => 'New Master Password';

  @override
  String get recoveryConfirmPasswordLabel => 'Confirm New Password';

  @override
  String get recoveryRecoverButton => 'Recover Account';

  @override
  String get recoverySaveKeyTitle => 'Save Your New Recovery Key';

  @override
  String get recoverySaveKeyCheckbox =>
      'I\'ve saved my new recovery key in a safe place';

  @override
  String get recoveryFinishButton => 'Finish';

  @override
  String get recoveryCopyButton => 'Copy to Clipboard';

  @override
  String get recoveryWrongKey =>
      'This recovery key doesn\'t match our records. Double-check your 24 words and try again.';

  @override
  String get recoveryPasswordMismatch => 'Passwords do not match';

  @override
  String get recoveryMaterialMissing =>
      'This account cannot be recovered — no recovery key was set up. Please contact support.';

  @override
  String get recoveryServerError => 'Recovery failed. Please try again.';

  @override
  String get vaultTitle => 'Vaults';

  @override
  String get vaultNewVault => 'New Vault';

  @override
  String get vaultNoVaults => 'No vaults yet';

  @override
  String get vaultCreateFirst =>
      'Create your first vault to organize credentials and grant access to your AI agents.';

  @override
  String get vaultRetry => 'Retry';

  @override
  String get vaultCancel => 'Cancel';

  @override
  String get vaultModeFull => 'Full';

  @override
  String get vaultModeGranular => 'Granular';

  @override
  String get vaultModeFullDescription =>
      'One approval grants access to every entry.';

  @override
  String get vaultModeGranularDescription =>
      'Each entry needs its own approval.';

  @override
  String get vaultModeLabel => 'Grant mode';

  @override
  String get vaultNameLabel => 'Vault Name';

  @override
  String get vaultDescriptionLabel => 'Description';

  @override
  String get vaultIconLabel => 'Icon';

  @override
  String get vaultColorLabel => 'Color';

  @override
  String get vaultCreating => 'Creating...';

  @override
  String get vaultSaving => 'Saving...';

  @override
  String get vaultSavedSnackbar => 'Vault updated';

  @override
  String get vaultDeleteTitle => 'Delete Vault?';

  @override
  String vaultDeleteConfirmWithName(String name) {
    return 'This will permanently delete \"$name\" and all its entries. This cannot be undone.';
  }

  @override
  String get vaultSettings => 'Vault Settings';

  @override
  String get vaultSaveChanges => 'Save Changes';

  @override
  String get vaultDangerZone => 'DANGER ZONE';

  @override
  String get vaultDangerZoneSubtitle =>
      'Deleting a vault is permanent — entries and grants are removed too.';

  @override
  String get vaultDeleteVault => 'Delete Vault';

  @override
  String vaultEntryCount(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString entries',
      one: '1 entry',
      zero: 'No entries',
    );
    return '$_temp0';
  }

  @override
  String vaultUpdatedAt(String date) {
    return 'Updated $date';
  }

  @override
  String get vaultUpdatedNow => 'now';

  @override
  String vaultUpdatedMinutesAgo(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${countString}m ago',
      one: '1m ago',
    );
    return '$_temp0';
  }

  @override
  String vaultUpdatedHoursAgo(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${countString}h ago',
      one: '1h ago',
    );
    return '$_temp0';
  }

  @override
  String vaultUpdatedDaysAgo(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${countString}d ago',
      one: '1d ago',
    );
    return '$_temp0';
  }

  @override
  String get vaultStatEntries => 'Entries';

  @override
  String get vaultStatActiveGrants => 'Active grants';

  @override
  String get vaultStatMembers => 'Members';

  @override
  String get vaultSectionEntries => 'Entries';

  @override
  String get vaultSectionAgents => 'Agents';

  @override
  String get vaultEntriesPlaceholderTitle => 'Entries coming soon';

  @override
  String get vaultEntriesPlaceholderSubtitle =>
      'Add and manage credentials from the web panel for now — mobile entry management lands in the next phase.';

  @override
  String get vaultAgentsPlaceholderTitle => 'Agents coming soon';

  @override
  String get vaultAgentsPlaceholderSubtitle =>
      'Approve agent grants from the home screen — per-vault agent management is on the roadmap.';

  @override
  String get vaultErrorNotFound => 'This vault no longer exists.';

  @override
  String get vaultErrorForbidden =>
      'You don\'t have permission to perform this action.';

  @override
  String get vaultErrorPlanLimitReached =>
      'You\'ve reached the vault limit for your plan. Upgrade to create more.';

  @override
  String get vaultErrorFullModeNotAllowed =>
      'Your plan doesn\'t allow Full-mode vaults. Choose Granular or upgrade.';

  @override
  String get vaultErrorUnknown => 'Something went wrong. Please try again.';

  @override
  String vaultGrantCount(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString grants',
      one: '1 grant',
      zero: 'No grants',
    );
    return '$_temp0';
  }

  @override
  String vaultActiveGrantCount(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString active grants',
      one: '1 active grant',
      zero: 'No active grants',
    );
    return '$_temp0';
  }

  @override
  String get vaultTabEntries => 'Entries';

  @override
  String get vaultTabAgents => 'Agents';

  @override
  String get vaultTabLogs => 'Logs';

  @override
  String get vaultTabMembers => 'Members';

  @override
  String get vaultTabSettings => 'Settings';

  @override
  String get vaultSearchEntries => 'Search entries…';

  @override
  String get vaultSearchAgents => 'Search agents…';

  @override
  String get vaultGrantFull => 'Full access';

  @override
  String get vaultGrantGranular => 'Granular';

  @override
  String get vaultGrantActive => 'active';

  @override
  String get vaultGrantExpired => 'expired';

  @override
  String get vaultGrantRevoked => 'revoked';

  @override
  String vaultGrantGrantedBy(String person, String date) {
    return 'Granted by $person at $date';
  }

  @override
  String vaultGrantRevokedBy(String person, String date) {
    return 'Revoked by $person at $date';
  }

  @override
  String vaultGrantMoreEntries(int count) {
    return '+$count more';
  }

  @override
  String get vaultRevokeButton => 'Revoke';

  @override
  String get vaultRegrantButton => 'Re-grant';

  @override
  String get vaultRestoreButton => 'Restore';

  @override
  String get vaultEntriesEmpty => 'No entries yet';

  @override
  String get vaultAgentsEmpty => 'No agents granted access';

  @override
  String get entryAgentsEmptyTitle => 'No agents have access';

  @override
  String get entryAgentsEmptyHint =>
      'No agent has been granted access to this entry yet.';

  @override
  String get vaultAgentsEmptyTitle => 'No agents have access';

  @override
  String get vaultAgentsEmptyHint =>
      'No agent has been granted access to this vault yet.';

  @override
  String get vaultLogsEmpty => 'Activity log coming soon';

  @override
  String get vaultMembersEmpty => 'Member management coming soon';

  @override
  String get vaultRevealEntry => 'Reveal entry data';

  @override
  String get vaultViewEntry => 'View entry details';

  @override
  String get vaultCopyValue => 'Copy';

  @override
  String get vaultOpenLink => 'Open in browser';

  @override
  String get vaultRevealValue => 'Reveal value';

  @override
  String get vaultSaveAction => 'Save';

  @override
  String get vaultAddEntryFab => 'Add entry';

  @override
  String get vaultAddGrantFab => 'Add grant';

  @override
  String get vaultIconUpload => 'Upload custom icon';

  @override
  String get vaultIconUploadError => 'Upload failed. Please try again.';

  @override
  String get vaultIconUploadSizeError => 'File exceeds 2 MB limit.';

  @override
  String get vaultIconUploadFormatError =>
      'Unsupported format. Use PNG, JPEG or WebP.';

  @override
  String get vaultUpgradeToPro => 'Upgrade to Pro';

  @override
  String get vaultUpgradeComingSoon =>
      'Upgrade flow coming soon — you\'ve reached the Basic plan\'s single-vault limit.';

  @override
  String get navHome => 'Home';

  @override
  String get navVaults => 'Vaults';

  @override
  String get navAgents => 'Agents';

  @override
  String get navAudit => 'Audit';

  @override
  String get navApprovals => 'Approvals';

  @override
  String get navInbox => 'Inbox';

  @override
  String get navSettings => 'Settings';

  @override
  String get vaultListTitle => 'My Vaults';

  @override
  String vaultListSummary(int vaultCount, int entryCount) {
    String _temp0 = intl.Intl.pluralLogic(
      vaultCount,
      locale: localeName,
      other: '$vaultCount vaults',
      one: '1 vault',
    );
    String _temp1 = intl.Intl.pluralLogic(
      entryCount,
      locale: localeName,
      other: '$entryCount entries',
      one: '1 entry',
      zero: 'no entries',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get vaultSearchHint => 'Search vaults…';

  @override
  String get vaultSearchEmpty => 'No vaults match your search';

  @override
  String get settingsAccountTitle => 'Account';

  @override
  String get settingsLockVault => 'Lock Vault';

  @override
  String get settingsLogout => 'Log out';

  @override
  String settingsAppVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsTooltip => 'Open settings';

  @override
  String get premiumGateTitle => 'Unlock unlimited vaults';

  @override
  String get premiumGateSubtitle =>
      'You\'ve reached the 1-vault limit on the free plan.';

  @override
  String get premiumGateCta => 'Upgrade to Pro';

  @override
  String get premiumGateDismiss => 'Maybe later';

  @override
  String get settingsThemeToggle => 'Dark mode';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsPlanPro => 'Pro';

  @override
  String get settingsPlanFree => 'Free';

  @override
  String get settingsDefaultDisplayName => 'User';

  @override
  String get placeholderComingSoon => 'Coming soon';

  @override
  String get placeholderAuditTitle => 'Audit Log';

  @override
  String get entryAddTitle => 'Add Entry';

  @override
  String get entryDetailTitle => 'Entry Details';

  @override
  String get entryTabDetails => 'Details';

  @override
  String get entryRevealingForEdit => 'Loading entry data…';

  @override
  String get entryDangerZone => 'Danger Zone';

  @override
  String get entryDeleteTitle => 'Delete Entry?';

  @override
  String get entryDeleteConfirm =>
      'This will permanently delete this entry and its encrypted data. This cannot be undone.';

  @override
  String get entryDeleteAction => 'Delete Entry';

  @override
  String get entryDeleting => 'Deleting…';

  @override
  String get entryTypeLabel => 'Entry type';

  @override
  String get entryTypeKey => 'Key';

  @override
  String get entryTypeCredential => 'Credential';

  @override
  String get entryLabelLabel => 'Label';

  @override
  String get entryLabelHint => 'e.g. Stripe API Key';

  @override
  String get entryDescriptionLabel => 'Description';

  @override
  String get entryValueLabel => 'Value';

  @override
  String get entryUsernameLabel => 'Username';

  @override
  String get entryPasswordLabel => 'Password';

  @override
  String get entryUrlLabel => 'URL';

  @override
  String get entryUrlInvalid =>
      'Enter a valid URL (e.g. stripe.com or https://stripe.com)';

  @override
  String get entryNotesLabel => 'Notes';

  @override
  String get entryEncryptionNotice =>
      'Encrypted on-device with XSalsa20-Poly1305 before upload';

  @override
  String get entrySearchHint => 'Search entries…';

  @override
  String get entryEmpty => 'No entries yet';

  @override
  String get entryEmptyAdd => 'Add your first credential to get started.';

  @override
  String get entrySaveAction => 'Save';

  @override
  String get entrySaving => 'Saving…';

  @override
  String get entryErrorNotFound => 'This entry no longer exists.';

  @override
  String get entryErrorForbidden =>
      'You don\'t have permission to perform this action.';

  @override
  String get entryErrorValidation =>
      'Some fields are invalid. Please review and try again.';

  @override
  String get entryErrorCrypto =>
      'We couldn\'t decrypt this entry. Lock and unlock your vault, then try again.';

  @override
  String get entryErrorUnknown => 'Something went wrong. Please try again.';

  @override
  String get entryEditAction => 'Edit';

  @override
  String entryCopiedField(String field) {
    return '$field copied to clipboard';
  }

  @override
  String get entryCopied => 'Copied to clipboard';

  @override
  String get entryTypeScript => 'Script';

  @override
  String get entryCustomFieldsLabel => 'Custom fields';

  @override
  String get entryAddFieldAction => 'Add field';

  @override
  String get entryFieldNameLabel => 'Field name';

  @override
  String get entryFieldNameHint => 'e.g. Recovery email';

  @override
  String get entryFieldValueLabel => 'Value';

  @override
  String get entryFieldTypeLabel => 'Type';

  @override
  String get entryFieldTypeText => 'Text';

  @override
  String get entryFieldTypeConcealed => 'Hidden';

  @override
  String get entryFieldTypeTotp => 'One-time code';

  @override
  String get entryFieldRemove => 'Remove field';

  @override
  String get entryFieldReorder => 'Drag to reorder';

  @override
  String get entryFieldNameRequired => 'Add a name for this field';

  @override
  String get totpSetupTitle => 'One-time code';

  @override
  String get totpScanQr => 'Scan QR code';

  @override
  String get totpOr => 'or';

  @override
  String get totpSetupKeyLabel => 'Setup key';

  @override
  String get totpSetupKeyHint => 'otpauth://… or base32 secret';

  @override
  String get totpIssuerLabel => 'Issuer (optional)';

  @override
  String get totpAccountLabel => 'Account (optional)';

  @override
  String get totpInvalidKey => 'Enter a valid otpauth:// key or base32 secret';

  @override
  String get totpScanInstruction =>
      'Point the camera at the authenticator QR code';

  @override
  String get totpScannerTitle => 'Scan QR code';

  @override
  String get totpCameraDenied =>
      'Camera access is off. Enable it in Settings, or paste the setup key instead.';

  @override
  String get totpCameraOpenSettings => 'Open settings';

  @override
  String get totpConfigured => 'One-time code configured';

  @override
  String get totpReplaceSecret => 'Replace';

  @override
  String get totpCodeCopied => 'One-time code copied';

  @override
  String get totpInvalidConfigured => 'Invalid code secret';

  @override
  String get entryScriptLabel => 'Script';

  @override
  String get entryScriptHint => '#!/usr/bin/env bash\\n…';

  @override
  String get entryInterpreterLabel => 'Interpreter';

  @override
  String get entryScriptRefsLabel => 'Credential references';

  @override
  String get entryInjectedDataLabel => 'Injected vault data';

  @override
  String get entryScriptRefsHint =>
      'Map an environment variable to a field on another entry.';

  @override
  String get entryAddRefAction => 'Add reference';

  @override
  String get entryRefEnvLabel => 'Environment variable';

  @override
  String get entryRefEnvHint => 'e.g. GITHUB_TOKEN';

  @override
  String get entryRefEntryLabel => 'Entry';

  @override
  String get entryRefFieldLabel => 'Field';

  @override
  String get entryRefEntryHint => 'Select an entry';

  @override
  String get entryRefRemove => 'Remove reference';

  @override
  String get entryScriptEmpty => 'No script yet';

  @override
  String get entryRefsEmpty => 'No credential references';

  @override
  String get entryTooLarge =>
      'This entry is too large. Shorten the script or remove some fields.';

  @override
  String get entryScriptExecOnlyTitle => 'EXEC-ONLY DELIVERY';

  @override
  String get entryScriptExecOnlyNotice =>
      'Runs on the agent via palladin exec — agents execute it, never read it.';

  @override
  String entryScriptFooter(String interpreter, int lines) {
    String _temp0 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$lines lines',
      one: '1 line',
    );
    return '$interpreter · $_temp0';
  }

  @override
  String get entryFieldTypeMultiline => 'Multiline';

  @override
  String get entryFieldTypeTextHint => 'single line';

  @override
  String get entryFieldTypeMultilineHint => 'notes, config';

  @override
  String get entryFieldTypeConcealedHint => 'masked';

  @override
  String get entryFieldAgentVisible => 'Visible to agents';

  @override
  String get entryFieldAgentVisibleTip =>
      'Visible to agents in your organization — shown in agent discovery without a grant. Only for non-secret helper info.';

  @override
  String get entryFieldOn => 'On';

  @override
  String get entryFieldOff => 'Off';

  @override
  String get entryFieldMoveUp => 'Move up';

  @override
  String get entryFieldMoveDown => 'Move down';

  @override
  String get entryFieldMenu => 'Field options';

  @override
  String get entryVisibleToAgents => 'visible to agents';

  @override
  String get totpSectionTitle => 'Two-factor authentication';

  @override
  String get totpEmptyHint =>
      'Add a time-based code (TOTP) to autofill 2FA for this login.';

  @override
  String get totpAdd => 'Add 2FA';

  @override
  String get totpRotates => 'rotates every 30 s';

  @override
  String get totpCopyCode => 'Copy code';

  @override
  String get totpRemove => 'Remove 2FA';

  @override
  String get entryAddNotes => 'Add notes';

  @override
  String get settingsScreenTitle => 'Settings';

  @override
  String get settingsOrganization => 'Organization';

  @override
  String get settingsManageOrganization => 'Organization';

  @override
  String get settingsOrgNameLabel => 'Organization name';

  @override
  String get settingsOrgNameHint => 'Enter organization name';

  @override
  String settingsOrgMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get settingsSave => 'Save';

  @override
  String get settingsOrgSaved => 'Organization name updated.';

  @override
  String get settingsApiKeys => 'API keys';

  @override
  String get settingsRetry => 'Retry';

  @override
  String get settingsErrorNotFound => 'We couldn\'t find this resource.';

  @override
  String get settingsErrorForbidden =>
      'You don\'t have permission to perform this action.';

  @override
  String get settingsErrorValidation => 'Please check the form and try again.';

  @override
  String get settingsErrorUnknown => 'Something went wrong. Please try again.';

  @override
  String get apiKeysScreenTitle => 'API keys';

  @override
  String get apiKeysEmpty => 'No API keys yet';

  @override
  String get apiKeysEmptyHint => 'Generate a key to connect your first agent.';

  @override
  String get apiKeysStatusActive => 'Active';

  @override
  String get apiKeysStatusRevoked => 'Revoked';

  @override
  String get apiKeysRetry => 'Retry';

  @override
  String get apiKeysGenerate => 'Generate API key';

  @override
  String get apiKeysGenerateAction => 'Generate';

  @override
  String get apiKeysGenerating => 'Generating…';

  @override
  String get apiKeysNameLabel => 'Key name';

  @override
  String get apiKeysNameHint => 'e.g. Production agent';

  @override
  String get apiKeysSecretTitle => 'API Key Created';

  @override
  String get apiKeysSecretWarning =>
      'Save this key now — it will never be shown again.';

  @override
  String get apiKeysCopyKey => 'Copy key';

  @override
  String get apiKeysKeyCopied => 'API key copied to clipboard.';

  @override
  String get apiKeysCopied => 'Copied to clipboard.';

  @override
  String get apiKeysConnectTitle => 'Connect your agent';

  @override
  String get apiKeysAgentNameLabel => 'Agent name';

  @override
  String get apiKeysConnectInstall => 'Don\'t have the CLI? Install it:';

  @override
  String get apiKeysConnectDocs => 'Copy docs link';

  @override
  String get apiKeysAgentMessageTitle => 'Message for your agent';

  @override
  String apiKeysAgentMessageBody(String name, String docs, String market) {
    return '$name, I\'ve connected you to Palladin for secure access to my credentials. Learn how to create and use your Palladin skill here: $docs — or browse ready-made skills in the marketplace: $market.';
  }

  @override
  String get apiKeysDone => 'Done';

  @override
  String get apiKeysCancel => 'Cancel';

  @override
  String get apiKeysRevoke => 'Revoke';

  @override
  String get apiKeysRevokeConfirmTitle => 'Revoke API key?';

  @override
  String apiKeysRevokeConfirmBody(String name) {
    return 'Agents using \"$name\" will lose access immediately. This cannot be undone.';
  }

  @override
  String get apiKeysDetailTitle => 'API key';

  @override
  String get apiKeysDetailNotFound => 'This API key no longer exists.';

  @override
  String get apiKeysTabDetails => 'Details';

  @override
  String get apiKeysTabAgents => 'Agents';

  @override
  String get apiKeysDetailKey => 'Key';

  @override
  String get apiKeysDetailCreatedAt => 'Created';

  @override
  String get apiKeysDetailRevokedAt => 'Revoked';

  @override
  String get apiKeysActivate => 'Activate';

  @override
  String get apiKeysActivating => 'Activating…';

  @override
  String get apiKeysDeletePermanently => 'Delete permanently';

  @override
  String get apiKeysDeleting => 'Deleting…';

  @override
  String get apiKeysDeleteConfirmTitle => 'Delete API key?';

  @override
  String apiKeysDeleteConfirmBody(String name) {
    return 'This will permanently delete \"$name\". This cannot be undone.';
  }

  @override
  String get apiKeysActivateZone => 'ACTIVATE KEY';

  @override
  String get apiKeysActivateHint =>
      'Re-enable this key — agents using it will regain access immediately.';

  @override
  String apiKeysListSummary(int total, int active) {
    return '$total keys · $active active';
  }

  @override
  String get agentsScreenTitle => 'Agents';

  @override
  String agentsListSummary(int total, int active) {
    return '$total agents, $active active';
  }

  @override
  String get agentsEmpty => 'No agents yet';

  @override
  String get agentsEmptyHint =>
      'Connect your first agent using the CLI to get started';

  @override
  String get agentsSearchHint => 'Search agents…';

  @override
  String get agentsSearchEmpty => 'No agents match your search';

  @override
  String get agentsUnnamed => 'Unnamed agent';

  @override
  String get agentsSplitPrompt => 'Select an agent to see its details';

  @override
  String get agentsStatusActive => 'Active';

  @override
  String get agentsStatusPending => 'Pending';

  @override
  String get agentsStatusDeactivated => 'Deactivated';

  @override
  String get agentsEnrolled => 'Enrolled';

  @override
  String get agentsDeactivated => 'Deactivated';

  @override
  String get agentsDeactivatedOn => 'Deactivated on';

  @override
  String get agentsConnectedOn => 'Connected on';

  @override
  String get agentsLastAccess => 'Last access';

  @override
  String get agentsPendingApproval => 'Pending approval';

  @override
  String get agentsDetailTitle => 'Agent';

  @override
  String get agentsDetailNotFound => 'Agent not found';

  @override
  String get agentsDetailId => 'Id';

  @override
  String get agentsDetailPublicKey => 'Public Key';

  @override
  String get agentsDetailCreatedAt => 'Connected';

  @override
  String get agentsDetailEnrolledAt => 'Enrolled';

  @override
  String get agentsDetailEnrolledBy => 'Enrolled by';

  @override
  String get agentsDetailDeactivatedAt => 'Deactivated';

  @override
  String get agentsApproveZone => 'APPROVE AGENT';

  @override
  String get agentsApproveHint =>
      'Lets this agent browse vault and entry listings only — secret contents stay locked until you approve a request or grant access in advance.';

  @override
  String get agentsApprove => 'Approve Agent';

  @override
  String get agentsApproving => 'Approving…';

  @override
  String get agentsDeactivateZone => 'DANGER ZONE';

  @override
  String get agentsDeactivateHint =>
      'This agent will immediately lose access to all vaults';

  @override
  String get agentsDeactivate => 'Deactivate Agent';

  @override
  String get agentsDeactivating => 'Deactivating…';

  @override
  String get agentsReactivateZone => 'REACTIVATE';

  @override
  String get agentsReactivateHint => 'Re-enable access for this agent';

  @override
  String get agentsReactivate => 'Reactivate Agent';

  @override
  String get agentsReactivating => 'Reactivating…';

  @override
  String get agentsApproveConfirmTitle => 'Approve Agent';

  @override
  String agentsApproveConfirmBody(String name) {
    return 'Allow \"$name\" to browse vault and entry listings? It still can\'t read any secret without your approval or a pre-granted access.';
  }

  @override
  String get agentsDeactivateConfirmTitle => 'Deactivate Agent';

  @override
  String agentsDeactivateConfirmBody(String name) {
    return 'Deactivate \"$name\"? It will immediately lose access.';
  }

  @override
  String get agentsEditTitle => 'Edit Agent';

  @override
  String get agentsEditName => 'Display Name';

  @override
  String get agentsEditDescription => 'Description';

  @override
  String get agentsEditSave => 'Save';

  @override
  String get agentsRetry => 'Retry';

  @override
  String get agentsEditIcon => 'Edit';

  @override
  String get agentApproveTitle => 'Approve Agent';

  @override
  String get agentNameLabel => 'Name (optional)';

  @override
  String get agentTypeLabel => 'Agent type';

  @override
  String get agentIconLabel => 'Icon';

  @override
  String get agentTypeOpenClaw => 'Open Claw';

  @override
  String get agentTypeClaudeCode => 'Claude Code';

  @override
  String get agentTypeHermes => 'Hermes';

  @override
  String get agentTypeCursor => 'Cursor';

  @override
  String get agentTypeCopilot => 'GitHub Copilot';

  @override
  String get agentTypeGemini => 'Gemini';

  @override
  String get agentTypeCodex => 'OpenAI Codex';

  @override
  String get agentTypeKimiCode => 'Kimi Code';

  @override
  String get agentTypeDevin => 'Devin';

  @override
  String get agentTypeAider => 'Aider';

  @override
  String get agentTypeCline => 'Cline';

  @override
  String get agentTypeRoo => 'Roo Code';

  @override
  String get agentTypeOther => 'Other';

  @override
  String get agentApproveSetupHint =>
      'Optionally set a name, type, and icon before activating.';

  @override
  String get agentNamePlaceholder => 'e.g. Claude Code, Cursor';

  @override
  String get agentsTabDetails => 'Details';

  @override
  String get agentsTabGrants => 'Grants';

  @override
  String get agentGrantsEmptyTitle => 'No grants yet';

  @override
  String get agentGrantsEmptyHint =>
      'This agent has no grants. Add one to give it access to a vault or entry.';

  @override
  String get agentsTabLogs => 'Logs';

  @override
  String get agentsGrantsEmpty => 'No active grants';

  @override
  String get agentsGrantsEmptyHint =>
      'This agent has not been granted access to any vault entries yet';

  @override
  String get agentsLogsFirstConnected => 'First connected';

  @override
  String get agentsLogsEnrolled => 'Enrolled';

  @override
  String get agentsLogsDeactivated => 'Deactivated';

  @override
  String get agentsEditSaved => 'Agent saved';

  @override
  String get agentTypePlaceholder => 'Pick a preset or type a custom value';

  @override
  String get agentIconMore => 'More icons';

  @override
  String get agentIconBrowserTitle => 'Browse icons';

  @override
  String get agentIconColorLabel => 'Color';

  @override
  String get agentIconChoose => 'Choose';

  @override
  String get agentsTypeUnknown => 'Unknown';

  @override
  String get agentsDetailLastIp => 'Last IP';

  @override
  String get agentsDetailLastHostname => 'Last Hostname';

  @override
  String get grantsScreenTitle => 'Grants';

  @override
  String get grantsFilterAll => 'All';

  @override
  String get grantsRetry => 'Retry';

  @override
  String get grantsEmpty => 'No grants yet';

  @override
  String get grantsEmptyHint =>
      'Grants appear here when an agent requests access to this vault.';

  @override
  String get grantsRevoke => 'Revoke grant';

  @override
  String get grantsRevokeConfirmTitle => 'Revoke grant?';

  @override
  String grantsRevokeConfirmBody(String agentName) {
    return '$agentName will immediately lose access. This cannot be undone.';
  }

  @override
  String get grantsRevokeReasonLabel => 'Reason (optional)';

  @override
  String get grantsRevokeReasonHint => 'Why are you revoking this grant?';

  @override
  String grantCardTarget(String target) {
    return 'Access to $target';
  }

  @override
  String get grantEntryUnknown => 'Unknown entry';

  @override
  String get grantUnnamedAgent => 'Unnamed agent';

  @override
  String get grantStatusPending => 'Pending';

  @override
  String get grantStatusActive => 'Active';

  @override
  String get grantStatusDenied => 'Denied';

  @override
  String get grantStatusRevoked => 'Revoked';

  @override
  String get grantStatusExpired => 'Expired';

  @override
  String get grantStatusConsumed => 'Consumed';

  @override
  String get grantScopeFull => 'All entries';

  @override
  String get grantScopeGranular => 'Single entry';

  @override
  String get approvalSegmentPending => 'Pending';

  @override
  String get approvalSegmentHistory => 'History';

  @override
  String get approvalHistorySearchHint => 'Search grants…';

  @override
  String get approvalHistoryEmpty => 'No grants yet';

  @override
  String get approvalHistoryEmptyHint =>
      'Granted, expired and revoked access will appear here.';

  @override
  String get approvalHistoryFilterClear => 'Clear';

  @override
  String get approvalPendingRequestsAccess => 'requests access';

  @override
  String get approvalPendingRowRequested => 'Requested';

  @override
  String get orgGrantRowVault => 'Vault';

  @override
  String get orgGrantRowEntry => 'Entry';

  @override
  String get orgGrantRowActor => 'By';

  @override
  String get orgGrantRowAccess => 'Access';

  @override
  String get orgGrantRowMethods => 'Methods';

  @override
  String get orgGrantRowReason => 'Reason';

  @override
  String get orgGrantRowDenyReason => 'Deny reason';

  @override
  String get orgGrantRowRevokeReason => 'Revoke reason';

  @override
  String get orgGrantActorSystem => 'System';

  @override
  String get orgGrantUnlimited => 'Unlimited';

  @override
  String orgGrantUsesLeft(int left, int limit) {
    return '$left of $limit uses left';
  }

  @override
  String orgGrantExpiresOn(String date) {
    return 'Until $date';
  }

  @override
  String get orgGrantAlreadyActive => 'Already active';

  @override
  String get grantDetailTitle => 'Grant';

  @override
  String get grantDetailScope => 'Scope';

  @override
  String get grantDetailEntry => 'Entry';

  @override
  String get grantDetailExpiry => 'Expiry';

  @override
  String get grantDetailReason => 'Agent\'s reason';

  @override
  String get grantDetailRequested => 'Requested';

  @override
  String get grantDetailApproved => 'Approved';

  @override
  String grantDetailApprovedBy(String date, String name) {
    return '$date by $name';
  }

  @override
  String get grantDetailRevoked => 'Revoked';

  @override
  String grantDetailExpiresAt(String date) {
    return 'Expires $date';
  }

  @override
  String grantDetailUsesLimit(int used, int limit) {
    return '$used of $limit uses';
  }

  @override
  String get grantDetailNoExpiry => 'No expiry';

  @override
  String get grantsErrorNotFound => 'This grant no longer exists.';

  @override
  String get grantsErrorForbidden =>
      'You do not have permission to manage grants.';

  @override
  String get grantsErrorValidation =>
      'The request was rejected. Please check and try again.';

  @override
  String get grantsErrorNetwork =>
      'Cannot reach the server. Check your connection.';

  @override
  String get grantsErrorCrypto =>
      'Could not securely prepare the credential. Please try again.';

  @override
  String get grantsErrorUnknown => 'Something went wrong. Please try again.';

  @override
  String get approvalInboxTitle => 'Approvals';

  @override
  String get approvalInboxEmpty => 'Nothing to approve';

  @override
  String get approvalInboxEmptyHint =>
      'When an agent requests access to a credential, the request shows up here for you to approve or deny.';

  @override
  String get approvalRetry => 'Retry';

  @override
  String approvalCardRequest(String entry, String vault) {
    return 'Wants $entry in $vault';
  }

  @override
  String get approvalScreenTitle => 'Review request';

  @override
  String get approvalSummaryEntry => 'Entry';

  @override
  String get approvalSummaryVault => 'Vault';

  @override
  String get approvalSummaryReason => 'Agent\'s reason';

  @override
  String get approvalUnnamedAgent => 'Unnamed agent';

  @override
  String get approvalEntryUnknown => 'this credential';

  @override
  String get approvalVaultUnknown => 'a vault';

  @override
  String get approvalLimitSectionTitle => 'Access limit';

  @override
  String get approvalLimitSectionHint =>
      'Choose how long this access lasts — by time or by number of uses.';

  @override
  String get approvalLimitExpiry => 'Expires after';

  @override
  String get approvalLimitUses => 'Number of uses';

  @override
  String get approvalLimitUsesLabel => 'Max uses';

  @override
  String get approvalApprove => 'Approve';

  @override
  String get approvalDenySectionTitle => 'Deny instead';

  @override
  String get approvalDenyReasonLabel => 'Reason (optional)';

  @override
  String get approvalDenyReasonHint => 'Why are you denying this request?';

  @override
  String get approvalDeny => 'Deny';

  @override
  String get approvalCancel => 'Cancel';

  @override
  String get approvalApproveTitle => 'Approve request';

  @override
  String get approvalApproveSubGrant => 'Grant';

  @override
  String get approvalApproveSubAccessTo => 'access to';

  @override
  String get approvalApproveSubIn => 'in';

  @override
  String get approvalAccessType => 'Access type';

  @override
  String get approvalMethodsLegend => 'How the agent may use it';

  @override
  String get approvalMethodWarningZone => 'Warning Zone';

  @override
  String get approvalMethodNoneSelected => 'Select at least one method.';

  @override
  String get approvalMethodGetLabel => 'Get (plaintext)';

  @override
  String get approvalMethodGetWarning =>
      'The secret enters the agent\'s context — on a hosted LLM it may leave the device.';

  @override
  String get approvalMethodExecLabel => 'Exec';

  @override
  String get approvalMethodInjectLabel => 'Inject';

  @override
  String get approvalApproving => 'Approving…';

  @override
  String get approvalPolicyTime => 'Time';

  @override
  String get approvalPolicyUses => 'Uses';

  @override
  String get approvalPolicyLifetime => 'Lifetime';

  @override
  String get approvalLifetimeHint =>
      'The agent keeps access until you revoke it.';

  @override
  String get approvalExpiresOnLabel => 'Expires on';

  @override
  String approvalQuickMinutes(int count) {
    return '${count}m';
  }

  @override
  String approvalQuickHours(int count) {
    return '${count}h';
  }

  @override
  String get approvalQuickCustom => 'Custom';

  @override
  String approvalExpiresInMinutes(int count) {
    return 'Expires in ${count}m';
  }

  @override
  String approvalExpiresInHours(int count) {
    return 'Expires in ${count}h';
  }

  @override
  String approvalExpiresInDays(int count) {
    return 'Expires in ${count}d';
  }

  @override
  String approvalExpiresInMonths(int count) {
    return 'Expires in ${count}mo';
  }

  @override
  String get approvalExpiredAlready => 'Expired';

  @override
  String approvalDenyTitle(String name) {
    return 'Deny $name?';
  }

  @override
  String get approvalDenyText => 'The agent won\'t get access to this entry.';

  @override
  String get approvalDenying => 'Denying…';

  @override
  String get approvalRegrantTitle => 'Grant again';

  @override
  String get approvalRegrant => 'Grant again';

  @override
  String get approvalRegranting => 'Granting…';

  @override
  String get approvalErrorNotFound => 'This request no longer exists.';

  @override
  String get approvalErrorForbidden =>
      'You do not have permission to manage grants.';

  @override
  String get approvalErrorValidation =>
      'The request was rejected. Please check and try again.';

  @override
  String get approvalErrorNetwork =>
      'Cannot reach the server. Check your connection.';

  @override
  String get approvalErrorCrypto =>
      'Could not securely prepare the credential. Please try again.';

  @override
  String get approvalErrorVaultLocked =>
      'Unlock your vault first to approve this request.';

  @override
  String get approvalErrorUnknown => 'Something went wrong. Please try again.';

  @override
  String get grantAccessTitleAgent => 'Add agent';

  @override
  String get grantAccessTitleVault => 'Grant access';

  @override
  String get grantAccessPickAgent => 'Agent';

  @override
  String get grantAccessPickVault => 'Vault';

  @override
  String get grantAccessNoAgents => 'No active agents to grant';

  @override
  String get grantAccessNoVaults => 'No vaults available';

  @override
  String get grantAccessSelectAgent => 'Select an agent';

  @override
  String get grantAccessSelectVault => 'Select a vault';

  @override
  String get grantAccessConfirm => 'Grant access';

  @override
  String get grantAccessGranting => 'Granting…';

  @override
  String get grantAccessError =>
      'Could not create the grant. Please try again.';

  @override
  String get grantAddGrant => 'Add grant';

  @override
  String get approvalMethodGetDesc =>
      'Returns the secret as plaintext to the agent.';

  @override
  String get approvalMethodExecDesc =>
      'Runs a command with the secret in its environment — never enters the agent\'s context.';

  @override
  String get approvalMethodInjectDesc =>
      'Fills a login form in the agent\'s browser — never enters the agent\'s context.';

  @override
  String get approvalMethodsSelect => 'Select methods';

  @override
  String get approvalMethodsDone => 'Done';

  @override
  String get approvalMethodRequested => 'requested';

  @override
  String get inboxTitle => 'Inbox';

  @override
  String get inboxSegAll => 'All';

  @override
  String get inboxTodo => 'To-do';

  @override
  String get inboxHistory => 'History';

  @override
  String get inboxSearchHint => 'Search by agent, entry or vault…';

  @override
  String get inboxMarkAllRead => 'Mark all read';

  @override
  String get inboxMoreActions => 'More';

  @override
  String get inboxGrantsMenu => 'Grants';

  @override
  String get inboxPreferencesMenu => 'Notification preferences';

  @override
  String get inboxAcceptAction => 'Accept';

  @override
  String get inboxViewAgent => 'View Agent';

  @override
  String get inboxViewAccess => 'View Access';

  @override
  String get inboxViewEntry => 'View Entry';

  @override
  String get inboxGrantsEmpty => 'No grants yet';

  @override
  String get inboxGrantsEmptyHint =>
      'Access you grant to your agents will appear here.';

  @override
  String get inboxActionGone => 'This action is no longer available.';

  @override
  String get inboxAllEmpty => 'Your inbox is empty';

  @override
  String get inboxAllEmptyHint =>
      'Requests, approvals and other agent activity will appear here.';

  @override
  String get inboxTodoEmpty => 'Nothing needs your attention';

  @override
  String get inboxTodoEmptyHint =>
      'Access requests and other actions from your agents will show up here.';

  @override
  String get inboxUpdatesEmpty => 'No history yet';

  @override
  String get inboxUpdatesEmptyHint =>
      'Approved, revoked and other resolved items will appear here.';

  @override
  String get inboxErrorForbidden =>
      'You do not have permission to view notifications.';

  @override
  String get inboxErrorNetwork =>
      'Cannot reach the server. Check your connection.';

  @override
  String get inboxErrorUnknown =>
      'Could not load notifications. Please try again.';

  @override
  String get notifUnnamedAgent => 'An agent';

  @override
  String get notifUnknownAgent => 'Unknown agent';

  @override
  String get notifTitleGrantPending => 'Access request';

  @override
  String get notifTitleAgentPending => 'New agent';

  @override
  String get notifTitleAgentApproved => 'Agent approved';

  @override
  String get notifTitleGrantRevoked => 'Access revoked';

  @override
  String get notifTitleGrantApproved => 'Access approved';

  @override
  String get notifTitleGrantDenied => 'Access denied';

  @override
  String get notifTitleCredentialStale => 'Credential not working';

  @override
  String notifSubGrantPending(String agent) {
    return '$agent';
  }

  @override
  String notifSubAgentPending(String agent) {
    return '$agent';
  }

  @override
  String notifSubAgentApproved(String agent) {
    return '$agent';
  }

  @override
  String notifSubCredentialStale(String agent) {
    return 'reported by $agent';
  }

  @override
  String notifSubGrantUpdate(String agent) {
    return '$agent';
  }

  @override
  String get notifRowEntry => 'Entry';

  @override
  String get notifRowMethods => 'Methods';

  @override
  String get notifRowReason => 'Reason';

  @override
  String get notifRowHostIp => 'Host · Ip';

  @override
  String get notifRowError => 'Error';

  @override
  String get notifRowAttempts => 'Attempts';

  @override
  String get notifRowNote => 'Note';

  @override
  String get notifRowAccess => 'Access';

  @override
  String get notifRowBy => 'By';

  @override
  String get notifRowAgentId => 'Agent Id';

  @override
  String get notifRowPublicKey => 'Public key';

  @override
  String get notifRowType => 'Type';

  @override
  String get notifAccessUnlimited => 'Unlimited';

  @override
  String get notifPlaceholder => '—';

  @override
  String get notifFilterTitle => 'Filter by type';

  @override
  String get notifFilterClear => 'Clear';

  @override
  String get notifPrefsTitle => 'Notification settings';

  @override
  String get notifPrefsHint =>
      'Choose how you want to be notified for each type. Some critical types stay on in your inbox.';

  @override
  String get notifPrefsEmpty => 'No preferences available.';

  @override
  String get notifPrefsSaveError =>
      'Could not save your preference. Please try again.';

  @override
  String get notifPrefsMandatory => 'Always on';

  @override
  String get notifPrefsChannelInbox => 'Inbox';

  @override
  String get notifPrefsChannelRealtime => 'Live';

  @override
  String get notifPrefsChannelPush => 'Push';

  @override
  String get notifPrefsTypeAgentPending => 'New agent to accept';

  @override
  String get notifPrefsTypeGrantPending => 'Access requests';

  @override
  String get notifPrefsTypeGrantRevoked => 'Access revoked';

  @override
  String get notifPrefsTypeGrantApproved => 'Access approved';

  @override
  String get notifPrefsTypeGrantDenied => 'Access denied';

  @override
  String get notifPrefsTypeCredentialStale => 'Credential stale';

  @override
  String get auditSearchHint => 'Search audit log…';

  @override
  String get auditLoadMore => 'Load more';

  @override
  String get auditLoadMoreError => 'Couldn\'t load more logs.';

  @override
  String get auditEmptyTitle => 'No activity yet';

  @override
  String get auditEmptyHint =>
      'Access and grant events for this entry will appear here.';

  @override
  String get auditEmptyFilteredTitle => 'No matching events';

  @override
  String get auditEmptyFilteredHint => 'Try adjusting your filters or search.';

  @override
  String get auditFilterTitle => 'Filter logs';

  @override
  String get auditFilterEventTypes => 'Event types';

  @override
  String get auditFilterAllEventTypes => 'All event types';

  @override
  String get auditFilterAgent => 'Agent';

  @override
  String get auditFilterAllAgents => 'All agents';

  @override
  String multiSelectNSelected(int count) {
    return '$count selected';
  }

  @override
  String get multiSelectSearchHint => 'Search…';

  @override
  String get multiSelectNoResults => 'No results';

  @override
  String get auditFilterDateRange => 'Date range';

  @override
  String get auditFilterFrom => 'From';

  @override
  String get auditFilterTo => 'To';

  @override
  String get auditFilterReset => 'Reset';

  @override
  String get auditFilterApply => 'Apply';

  @override
  String get auditDetailEntry => 'Entry';

  @override
  String get auditDetailReason => 'Reason';

  @override
  String get auditDetailNone => 'No additional details.';

  @override
  String get auditActorOwner => 'Owner';

  @override
  String get auditActorSystem => 'System';

  @override
  String get auditActorAgent => 'Agent';

  @override
  String get auditErrorForbidden =>
      'You don\'t have permission to view audit logs.';

  @override
  String get auditErrorNotFound => 'Audit logs are unavailable for this vault.';

  @override
  String get auditErrorNetwork =>
      'Network error. Check your connection and try again.';

  @override
  String get auditErrorGeneric =>
      'Couldn\'t load the audit log. Please try again.';

  @override
  String get auditEventGrantCreated => 'Access granted';

  @override
  String get auditEventGrantRequested => 'Access requested';

  @override
  String get auditEventGrantApproved => 'Access approved';

  @override
  String get auditEventGrantDenied => 'Access denied';

  @override
  String get auditEventGrantRevoked => 'Access revoked';

  @override
  String get auditEventGrantConsumed => 'Grant consumed';

  @override
  String get auditEventGrantExpired => 'Grant expired';

  @override
  String get auditEventCredentialAccessed => 'Credential accessed';

  @override
  String get auditEventCredentialAccessDenied => 'Access denied';

  @override
  String get auditEventAgentEnrolled => 'Agent enrolled';

  @override
  String get auditEventAgentBlocked => 'Agent blocked';

  @override
  String get auditEventAgentReactivated => 'Agent reactivated';

  @override
  String get auditEventAgentDeleted => 'Agent deleted';

  @override
  String get auditEventVaultCreated => 'Vault created';

  @override
  String get auditEventVaultUpdated => 'Vault updated';

  @override
  String get auditEventVaultDeleted => 'Vault deleted';

  @override
  String get auditEventVaultExported => 'Vault exported';

  @override
  String get auditEventEntryCreated => 'Entry created';

  @override
  String get auditEventEntryUpdated => 'Entry updated';

  @override
  String get auditEventEntryDeleted => 'Entry deleted';

  @override
  String get auditEventApiKeyCreated => 'API key created';

  @override
  String get auditEventApiKeyActivated => 'API key activated';

  @override
  String get auditEventApiKeyRevoked => 'API key revoked';

  @override
  String get auditEventApiKeyDeleted => 'API key deleted';

  @override
  String get auditEventOrgCreated => 'Organization created';

  @override
  String get auditEventOrgUpdated => 'Organization updated';

  @override
  String get auditEventUserSignedUp => 'User signed up';

  @override
  String get auditEventAccountSetupCompleted => 'Account setup completed';

  @override
  String get auditEventAccountRecoveryCompleted => 'Account recovery completed';

  @override
  String get auditEventUnknown => 'Activity';

  @override
  String get auditScreenTitle => 'Audit Log';

  @override
  String get auditFilterVault => 'Vault';

  @override
  String get auditFilterAllVaults => 'All vaults';

  @override
  String get auditFilterUser => 'Performed by';

  @override
  String get auditFilterAllUsers => 'Anyone';

  @override
  String get auditUserUnknown => 'Unknown user';

  @override
  String auditUserUnknownShort(String id) {
    return 'Unknown user ($id)';
  }

  @override
  String get auditGroupCredentialAccess => 'Accessed';

  @override
  String get auditGroupGrants => 'Grants';

  @override
  String get auditGroupVaultEntry => 'Vault & entries';

  @override
  String get auditGroupAgentLifecycle => 'Agents';

  @override
  String get auditGroupApiKeys => 'API keys';

  @override
  String get auditGroupOrgAccount => 'Org & account';

  @override
  String get auditLegendTitle => 'Event legend';

  @override
  String get auditLegendSubtitle => 'What the colours on each log entry mean.';

  @override
  String auditSentenceCreated(String actor, String object) {
    return '$actor created $object';
  }

  @override
  String auditSentenceUpdated(String actor, String object) {
    return '$actor updated $object';
  }

  @override
  String auditSentenceDeleted(String actor, String object) {
    return '$actor deleted $object';
  }

  @override
  String auditSentenceExported(String actor, String object) {
    return '$actor exported $object';
  }

  @override
  String auditSentenceActivated(String actor, String object) {
    return '$actor activated $object';
  }

  @override
  String auditSentenceRevoked(String actor, String object) {
    return '$actor revoked $object';
  }

  @override
  String auditSentenceBlocked(String actor, String object) {
    return '$actor blocked $object';
  }

  @override
  String auditSentenceReactivated(String actor, String object) {
    return '$actor reactivated $object';
  }

  @override
  String auditSentenceUserSignedUp(String actor) {
    return '$actor signed up';
  }

  @override
  String auditSentenceAccountSetupCompleted(String actor) {
    return '$actor completed account setup';
  }

  @override
  String auditSentenceAccountRecoveryCompleted(String actor) {
    return '$actor completed account recovery';
  }

  @override
  String auditSentenceAgentEnrolled(String agent) {
    return '$agent enrolled in the system';
  }

  @override
  String auditObjectVaultNamed(String name) {
    return 'vault $name';
  }

  @override
  String auditObjectEntryNamed(String name) {
    return 'entry $name';
  }

  @override
  String auditObjectOrgNamed(String name) {
    return 'organization $name';
  }

  @override
  String auditObjectApiKeyNamed(String name) {
    return 'API key $name';
  }

  @override
  String auditObjectAgentNamed(String name) {
    return 'agent $name';
  }

  @override
  String get auditObjectVault => 'a vault';

  @override
  String get auditObjectEntry => 'an entry';

  @override
  String get auditObjectOrg => 'the organization';

  @override
  String get auditObjectApiKey => 'an API key';

  @override
  String get auditObjectAgent => 'an agent';

  @override
  String get dashboardGoodMorning => 'Good morning';

  @override
  String get dashboardSearchHint => 'Agents, vaults, entries…';

  @override
  String get defaultVaultName => 'Personal';

  @override
  String get dashboardOnboardingTitle => 'Set up Palladin';

  @override
  String get dashboardOnboardingSubtitle =>
      'Complete these steps to start managing access securely';

  @override
  String dashboardOnboardingProgress(int completed) {
    return '$completed of 4 completed';
  }

  @override
  String get dashboardOnboardingSkipSetup => 'Skip setup';

  @override
  String get dashboardOnboardingStep1Title => 'Enable notifications';

  @override
  String get dashboardOnboardingStep1Description =>
      'Respond in seconds — agents wait for your approval. Faster responses mean smoother AI workflows.';

  @override
  String get dashboardOnboardingStep1Enable => 'Enable';

  @override
  String get dashboardOnboardingStep1Skip => 'Skip';

  @override
  String get dashboardOnboardingStep1OpenSettings => 'Open Settings';

  @override
  String get dashboardOnboardingStep2Title =>
      'Add your first entry or import passwords';

  @override
  String get dashboardOnboardingStep2Description =>
      'Your Personal vault is ready — add a password entry manually or import your existing credentials.';

  @override
  String get dashboardOnboardingStep2Cta => 'Go to Vaults';

  @override
  String get dashboardOnboardingStep3Title => 'Add an API Key';

  @override
  String get dashboardOnboardingStep3Description =>
      'Connect Palladin to external services';

  @override
  String get dashboardOnboardingStep3Cta => 'Add API Key';

  @override
  String get dashboardOnboardingStep4Title => 'Register an Agent';

  @override
  String get dashboardOnboardingStep4Description =>
      'Add your first AI agent that can request access';

  @override
  String get dashboardOnboardingStep4Cta => 'Register Agent';

  @override
  String dashboardOnboardingStep(int n) {
    return 'Step $n';
  }

  @override
  String get dashboardUnknownAgentWarning => 'Unregistered agent';

  @override
  String get dashboardUnknownAgentDescription =>
      'This agent is not yet in the system. You can register it and approve access at the same time.';

  @override
  String get dashboardUnknownAgentRegisterAndApprove => 'Register & Approve';

  @override
  String get dashboardUnknownAgentReject => 'Reject';

  @override
  String get dashboardRequestRejected => 'Request rejected';

  @override
  String get dashboardPendingApprovals => 'Pending Approvals';

  @override
  String get dashboardRecentActivity => 'Recent Activity';

  @override
  String get dashboardNoActivity => 'No activity yet';

  @override
  String get dashboardRecentlyModified => 'Recently added / modified';

  @override
  String get dashboardSeeAll => 'See all';

  @override
  String get dashboardSearchRecent => 'Recent';

  @override
  String get searchResultsEmpty => 'No results for this search';

  @override
  String get searchResultsError => 'Search failed. Please try again.';

  @override
  String get searchTypeBadgeAgent => 'Agent';

  @override
  String get searchTypeBadgeVault => 'Vault';

  @override
  String get searchTypeBadgeEntry => 'Entry';

  @override
  String get importTitle => 'Import';

  @override
  String get importChooseFile => 'Choose file';

  @override
  String get importIntroTitle => 'Import from another password manager';

  @override
  String get importIntroBody =>
      'Pick an export file from Chrome, Bitwarden, 1Password, LastPass, and more. Everything is parsed and encrypted on your device.';

  @override
  String get importSupportedFormats =>
      'Supported: CSV, JSON, XML, and ZIP (.1pux) exports';

  @override
  String get importParsing => 'Reading file…';

  @override
  String get importSelectVaultSubtitle =>
      'Choose where the imported entries go';

  @override
  String get importNoVaults =>
      'No vaults yet. Create a vault first, then import into it.';

  @override
  String importEntriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return '$_temp0';
  }

  @override
  String importSkippedNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count non-login items skipped',
      one: '1 non-login item skipped',
    );
    return '$_temp0';
  }

  @override
  String get importConflictStrategyLabel => 'For entries that already exist';

  @override
  String get importStrategySkip => 'Skip';

  @override
  String get importStrategyOverwrite => 'Overwrite';

  @override
  String get importStrategyRename => 'Keep both';

  @override
  String get importConflictBadge => 'Exists';

  @override
  String get importTotpBadge => '2FA';

  @override
  String get importNotesBadge => 'Notes';

  @override
  String importAction(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return 'Import $_temp0';
  }

  @override
  String importImporting(int done, int total) {
    return 'Importing… $done of $total';
  }

  @override
  String get importSuccessTitle => 'Import complete';

  @override
  String importSuccessBody(int created, int updated) {
    String _temp0 = intl.Intl.pluralLogic(
      created,
      locale: localeName,
      other: '$created added',
      one: '1 added',
    );
    String _temp1 = intl.Intl.pluralLogic(
      updated,
      locale: localeName,
      other: '$updated updated',
      one: '1 updated',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String importSuccessSkipped(int count) {
    return '$count skipped';
  }

  @override
  String get importDone => 'Done';

  @override
  String get importFailedTitle => 'Import failed';

  @override
  String get importTryAnother => 'Choose another file';

  @override
  String get importErrorEmpty => 'That file is empty.';

  @override
  String get importErrorEncrypted =>
      'This export is encrypted and can\'t be read. Export an unencrypted file (e.g. KeePass XML) and try again.';

  @override
  String get importErrorUnrecognised =>
      'We couldn\'t recognise this file. Try a CSV, JSON, or XML export.';

  @override
  String get importErrorNoEntries =>
      'No login entries were found in this file.';

  @override
  String get importErrorCrypto =>
      'We couldn\'t encrypt the entries. Lock and unlock your vault, then try again.';

  @override
  String get importErrorNetwork =>
      'Couldn\'t reach the server. Check your connection and try again.';

  @override
  String get importErrorFullGrants =>
      'This vault has agents with full access. Importing to it isn\'t supported on mobile yet — revoke the full-access grants first, or import from the web panel.';

  @override
  String get importErrorUnknown => 'Something went wrong. Please try again.';

  @override
  String get importColumnMapTitle => 'Map columns';

  @override
  String get importColumnMapSubtitle =>
      'We couldn\'t detect this format. Tell us which column is which.';

  @override
  String get importColumnName => 'Name column';

  @override
  String get importColumnUsername => 'Username column';

  @override
  String get importColumnPassword => 'Password column';

  @override
  String get importColumnUrl => 'URL column';

  @override
  String get importColumnNotes => 'Notes column';

  @override
  String get importColumnTotp => 'TOTP column';

  @override
  String get importColumnNone => '— None —';

  @override
  String importColumnFallback(int number) {
    return 'Column $number';
  }

  @override
  String get importUntitledFallback => 'Untitled';

  @override
  String get importColumnMapContinue => 'Continue';

  @override
  String get importColumnMapNeedPassword =>
      'Choose at least a password column.';

  @override
  String get importFormatGeneric => 'CSV';

  @override
  String get importFormatManual => 'Custom CSV';

  @override
  String get settingsImport => 'Import';

  @override
  String get vaultActionImport => 'Import entries';

  @override
  String get vaultActionExport => 'Export vault';

  @override
  String get exportTitle => 'Export vault';

  @override
  String get exportFormatCsv => 'CSV';

  @override
  String get exportFormatJson => 'JSON';

  @override
  String get exportCsvHint =>
      'Compatible with Chrome, Bitwarden, and most managers.';

  @override
  String get exportJsonHint => 'Full Palladin format — re-imports losslessly.';

  @override
  String get exportWarningTitle => 'PLAINTEXT EXPORT';

  @override
  String get exportWarningBody =>
      'The file contains your passwords and TOTP secrets in plaintext. Anyone with the file can read them. Store it securely and delete it when you\'re done.';

  @override
  String get exportConfirm => 'Export';

  @override
  String exportSuccess(int count) {
    return 'Exported $count entries';
  }

  @override
  String get exportEmpty => 'This vault has no entries to export.';

  @override
  String get exportErrorCrypto =>
      'We couldn\'t decrypt the vault. Lock and unlock, then try again.';

  @override
  String get exportErrorNetwork =>
      'Couldn\'t reach the server. Check your connection and try again.';

  @override
  String get exportErrorUnknown => 'Something went wrong. Please try again.';

  @override
  String get authLoginSubtitle =>
      'Sign in with your email and master password.';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authEmailHint => 'you@example.com';

  @override
  String get authEmailInvalid => 'Enter a valid email address.';

  @override
  String get authPasswordLabel => 'Master Password';

  @override
  String get authLoginButton => 'Sign In';

  @override
  String get authInvalidCredentials => 'Incorrect email or password.';

  @override
  String get authRateLimited => 'Too many attempts. Please try again later.';

  @override
  String get authNoAccountPrompt => 'Don\'t have an account?';

  @override
  String get authSignUpLink => 'Sign up';

  @override
  String get authRegisterButton => 'Sign Up';

  @override
  String get authOrDivider => 'or';

  @override
  String get authRegisterTitle => 'Create your account';

  @override
  String get authRegisterSubtitle =>
      'Your master password encrypts everything on-device. We never see it.';

  @override
  String get authRegisterConfirmLabel => 'Confirm Password';

  @override
  String get authRegisterHaveAccount => 'Already have an account?';

  @override
  String get authRegisterSignIn => 'Sign in';

  @override
  String get authRegisterEmailTaken =>
      'An account with this email already exists.';

  @override
  String get authPasswordChecking => 'Checking your password...';

  @override
  String get authPasswordSecure => 'Secure!';

  @override
  String get authPasswordImprove =>
      'Use a longer password with mixed characters.';

  @override
  String get authPasswordCheckUnavailable =>
      'Couldn\'t check breaches - use a unique password.';

  @override
  String get authPasswordBreached =>
      'Found in a data breach - choose another password.';

  @override
  String get authRecoveryWarningTitle => 'SAVE YOUR RECOVERY KEY';

  @override
  String authVerifyGateSubtitle(String email) {
    return 'We sent a verification link to $email.';
  }

  @override
  String get authVerifyGateSubtitleNoEmail =>
      'We sent you a verification link.';

  @override
  String get authVerifyGateInstruction => 'Open it to activate your account.';

  @override
  String get authVerifyResendButton => 'Resend email';

  @override
  String get authVerifyCheckAgain => 'I\'ve verified my email';

  @override
  String get authVerifyStillPending =>
      'We couldn\'t confirm it yet. Open the verification link and try again.';

  @override
  String get authVerifyCheckError =>
      'We couldn\'t finish setting up your account. Try again.';

  @override
  String get authVerifyResendSent => 'Verification email sent.';

  @override
  String get authVerifyResendError => 'Couldn\'t resend. Please try again.';

  @override
  String get authVerifyLogout => 'Sign out';

  @override
  String get authVerifyingTitle => 'Verifying…';

  @override
  String get authVerifiedTitle => 'Email verified';

  @override
  String get authVerifiedSubtitle => 'Your account is now active.';

  @override
  String get authVerifyContinue => 'Continue';

  @override
  String get authVerifyGoToLogin => 'Go to sign in';

  @override
  String get authVerifyExpiredTitle => 'Link expired';

  @override
  String get authVerifyExpiredSubtitle =>
      'This verification link has expired. Request a new one.';

  @override
  String get authVerifyInvalidTitle => 'Invalid link';

  @override
  String get authVerifyInvalidSubtitle =>
      'This verification link is invalid or has already been used.';

  @override
  String get authTotpChallengeTitle => 'Two-factor authentication';

  @override
  String get authTotpChallengeSubtitle =>
      'Enter the 6-digit code from your authenticator app.';

  @override
  String get authTotpRecoverySubtitle => 'Enter one of your recovery codes.';

  @override
  String get authTotpCodeLabel => 'Authentication code';

  @override
  String get authTotpRecoveryLabel => 'Recovery code';

  @override
  String get authTotpVerifyButton => 'Verify';

  @override
  String get authTotpUseRecovery => 'Use a recovery code instead';

  @override
  String get authTotpUseCode => 'Use an authenticator code instead';

  @override
  String get authTotpInvalid => 'Invalid code. Please try again.';

  @override
  String get authTotpEnrollTitle => 'Set up two-factor authentication';

  @override
  String get authTotpEnrollSubtitle =>
      'Scan the QR code with your authenticator app, or enter the setup key manually.';

  @override
  String get authTotpEnrollSecretLabel => 'Setup key';

  @override
  String get authTotpEnrollCopyKey => 'Copy setup key';

  @override
  String get authTotpEnrollKeyCopied => 'Setup key copied.';

  @override
  String get authTotpEnrollCodeLabel => 'Enter the 6-digit code';

  @override
  String get authTotpEnrollConfirmButton => 'Enable';

  @override
  String get authTotpEnrollRetry => 'Retry';

  @override
  String get authTotpEnrollRecoveryTitle => 'Save your recovery codes';

  @override
  String get authTotpEnrollRecoverySubtitle =>
      'Store these somewhere safe. Each code can be used once if you lose your authenticator.';

  @override
  String get authTotpEnrollRecoveryWarningTitle => 'SHOWN ONLY ONCE';

  @override
  String get authTotpEnrollRecoveryWarning =>
      'These codes won\'t be shown again. Save them before you continue.';

  @override
  String get authTotpEnrollNoCodes => 'No recovery codes were returned.';

  @override
  String get authTotpEnrollCopyCodes => 'Copy codes';

  @override
  String get authTotpEnrollCodesCopied => 'Recovery codes copied.';

  @override
  String get authTotpEnrollDone => 'Done';

  @override
  String get authChangePwTitle => 'Change master password';

  @override
  String get authChangePwSubtitle =>
      'This re-encrypts your vault key on-device. Your recovery key stays the same.';

  @override
  String get authChangePwCurrentLabel => 'Current master password';

  @override
  String get authChangePwNewLabel => 'New master password';

  @override
  String get authChangePwConfirmLabel => 'Confirm new password';

  @override
  String get authChangePwWrongCurrent => 'Current password is incorrect.';

  @override
  String get authChangePwSameAsCurrent =>
      'Choose a password different from your current one.';

  @override
  String get authChangePwWarningTitle => 'BIOMETRIC UNLOCK';

  @override
  String get authChangePwWarning =>
      'You\'ll need to re-enable biometric unlock after changing your password.';

  @override
  String get authChangePwButton => 'Change Password';

  @override
  String get authChangePwSuccess => 'Master password changed.';

  @override
  String get settingsChangePassword => 'Change master password';

  @override
  String get settingsTwoFactor => 'Two-factor authentication';
}
