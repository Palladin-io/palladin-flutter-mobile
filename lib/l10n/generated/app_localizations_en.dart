// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Claw Vault';

  @override
  String get welcomeMessage => 'Welcome to Claw Vault';

  @override
  String get taglineZeroKnowledge => 'Zero-Knowledge';

  @override
  String get taglinePasswordManager => 'Password Manager';

  @override
  String get taglineForAiAgents => 'For AI Agents';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get continueWithX => 'Continue with X';

  @override
  String get legalFooter =>
      'By continuing, you agree to our Terms & Privacy Policy';

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
  String get unlockBiometricHint => 'Unlock with biometrics';

  @override
  String get unlockBiometricPrompt => 'Authenticate to unlock your vault';

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
  String get recoveryShareSubject => 'Claw Vault Recovery Key';

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
  String get apiKeysSecretTitle => 'API key created';

  @override
  String get apiKeysSecretWarning =>
      'Save this key now — it will never be shown again.';

  @override
  String get apiKeysCopyKey => 'Copy key';

  @override
  String get apiKeysKeyCopied => 'API key copied to clipboard.';

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
  String get agentsApproveHint => 'Grant this agent access to the organization';

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
    return 'Allow \"$name\" to access organization vaults?';
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
  String get approvalMethodsHelp =>
      'Choose how this credential can be used. Restricting to Exec/Inject keeps the secret out of the agent\'s LLM context.';

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
}
