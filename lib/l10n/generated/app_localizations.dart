import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pl'),
  ];

  /// The application title shown in the app bar and OS task switcher
  ///
  /// In en, this message translates to:
  /// **'Claw Vault'**
  String get appTitle;

  /// Greeting shown on the home/dashboard placeholder page
  ///
  /// In en, this message translates to:
  /// **'Welcome to Claw Vault'**
  String get welcomeMessage;

  /// First line of the stacked tagline on the login screen
  ///
  /// In en, this message translates to:
  /// **'Zero-Knowledge'**
  String get taglineZeroKnowledge;

  /// Second line of the stacked tagline on the login screen
  ///
  /// In en, this message translates to:
  /// **'Password Manager'**
  String get taglinePasswordManager;

  /// Third line of the stacked tagline on the login screen
  ///
  /// In en, this message translates to:
  /// **'For AI Agents'**
  String get taglineForAiAgents;

  /// Label for the Google OAuth sign-in button
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// Label for the Apple OAuth sign-in button
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get continueWithApple;

  /// Label for the X (formerly Twitter) OAuth sign-in button
  ///
  /// In en, this message translates to:
  /// **'Continue with X'**
  String get continueWithX;

  /// Legal consent text shown at the bottom of the login page
  ///
  /// In en, this message translates to:
  /// **'By continuing, you agree to our Terms & Privacy Policy'**
  String get legalFooter;

  /// Snackbar message when a disabled OAuth provider is tapped
  ///
  /// In en, this message translates to:
  /// **'{provider} sign-in coming soon'**
  String providerComingSoon(String provider);

  /// Error shown when the backend request times out
  ///
  /// In en, this message translates to:
  /// **'Server not responding. Please try again.'**
  String get errorServerNotResponding;

  /// Error shown when a network/socket connection fails
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to server. Check your connection and try again.'**
  String get errorCannotConnectToServer;

  /// Generic fallback error for other Dio/connection failures
  ///
  /// In en, this message translates to:
  /// **'Connection error. Please try again.'**
  String get errorConnectionFailed;

  /// Error shown when the backend returns unparseable data
  ///
  /// In en, this message translates to:
  /// **'Invalid server response. Please try again.'**
  String get errorInvalidServerResponse;

  /// Headline on the master password setup screen
  ///
  /// In en, this message translates to:
  /// **'Set Your Master Password'**
  String get onboardingMasterPasswordTitle;

  /// Supporting copy below the master password headline
  ///
  /// In en, this message translates to:
  /// **'This password encrypts your vault locally. We never see it.'**
  String get onboardingMasterPasswordSubtitle;

  /// Label for the master password input field
  ///
  /// In en, this message translates to:
  /// **'Master Password'**
  String get onboardingMasterPasswordLabel;

  /// Label for the password confirmation input field
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get onboardingConfirmPasswordLabel;

  /// Title for the password requirements checklist
  ///
  /// In en, this message translates to:
  /// **'Requirements'**
  String get onboardingPasswordRequirementsTitle;

  /// Requirement: password length
  ///
  /// In en, this message translates to:
  /// **'At least 12 characters'**
  String get onboardingPasswordReqLength;

  /// Requirement: mixed case
  ///
  /// In en, this message translates to:
  /// **'Uppercase & lowercase'**
  String get onboardingPasswordReqCase;

  /// Requirement: digit
  ///
  /// In en, this message translates to:
  /// **'At least one number'**
  String get onboardingPasswordReqNumber;

  /// Requirement: symbol
  ///
  /// In en, this message translates to:
  /// **'At least one symbol'**
  String get onboardingPasswordReqSymbol;

  /// Strength label when the password is under 8 characters
  ///
  /// In en, this message translates to:
  /// **'Too short'**
  String get onboardingPasswordStrengthTooShort;

  /// Strength label for a weak password
  ///
  /// In en, this message translates to:
  /// **'Weak password'**
  String get onboardingPasswordStrengthWeak;

  /// Strength label for a fair password
  ///
  /// In en, this message translates to:
  /// **'Fair password'**
  String get onboardingPasswordStrengthFair;

  /// Strength label for a strong password
  ///
  /// In en, this message translates to:
  /// **'Strong password'**
  String get onboardingPasswordStrengthStrong;

  /// Strength label for a very strong password
  ///
  /// In en, this message translates to:
  /// **'Very strong password'**
  String get onboardingPasswordStrengthVeryStrong;

  /// Inline confirmation when both password fields match
  ///
  /// In en, this message translates to:
  /// **'Passwords match'**
  String get onboardingPasswordsMatch;

  /// Inline error when the two password fields disagree
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get onboardingPasswordsDoNotMatch;

  /// Primary button on screen 1
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// Headline on the recovery key backup screen
  ///
  /// In en, this message translates to:
  /// **'Save Your Recovery Key'**
  String get onboardingRecoveryTitle;

  /// Supporting copy on the recovery key backup screen
  ///
  /// In en, this message translates to:
  /// **'Write this down and store it safely offline. Without it, a forgotten master password means permanent data loss.'**
  String get onboardingRecoverySubtitle;

  /// Warning banner reminding the user to store the recovery key safely
  ///
  /// In en, this message translates to:
  /// **'You cannot recover your vault without this key.'**
  String get onboardingRecoveryWarning;

  /// Button that copies the recovery mnemonic to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get onboardingRecoveryCopy;

  /// Snackbar confirmation after copying the recovery mnemonic
  ///
  /// In en, this message translates to:
  /// **'Recovery key copied to clipboard'**
  String get onboardingRecoveryCopied;

  /// Button that exports the recovery mnemonic as a .txt file via the platform share sheet
  ///
  /// In en, this message translates to:
  /// **'Export as File (.txt)'**
  String get onboardingRecoveryExport;

  /// Primary button on screen 2 to proceed to confirmation
  ///
  /// In en, this message translates to:
  /// **'I\'ve Saved My Recovery Key'**
  String get onboardingRecoverySaved;

  /// Headline on the recovery key confirmation screen
  ///
  /// In en, this message translates to:
  /// **'Confirm Recovery Key'**
  String get onboardingConfirmTitle;

  /// Supporting copy on the recovery key confirmation screen
  ///
  /// In en, this message translates to:
  /// **'Enter the following words from your recovery key to verify you saved it.'**
  String get onboardingConfirmSubtitle;

  /// Label for a single recovery-word input on the confirmation screen
  ///
  /// In en, this message translates to:
  /// **'Word #{index}'**
  String onboardingConfirmWordLabel(int index);

  /// Placeholder text for a recovery-word input
  ///
  /// In en, this message translates to:
  /// **'Enter word #{index}'**
  String onboardingConfirmWordHint(int index);

  /// Inline confirmation shown when a recovery word matches
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get onboardingConfirmCorrect;

  /// Inline error shown when a recovery word does not match
  ///
  /// In en, this message translates to:
  /// **'Incorrect'**
  String get onboardingConfirmIncorrect;

  /// Primary button on screen 3 that runs the crypto pipeline
  ///
  /// In en, this message translates to:
  /// **'Verify & Complete Setup'**
  String get onboardingConfirmVerify;

  /// Error shown when the backend returns 409 during setup
  ///
  /// In en, this message translates to:
  /// **'This account has already been set up. Please sign in again.'**
  String get onboardingAlreadyCompleted;

  /// Subtitle on the master-password unlock screen
  ///
  /// In en, this message translates to:
  /// **'Enter your master password'**
  String get unlockTitle;

  /// Label for the password field on the unlock screen
  ///
  /// In en, this message translates to:
  /// **'Master Password'**
  String get unlockPasswordLabel;

  /// Primary action label on the unlock screen
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockButton;

  /// Text button that starts the recovery-key flow
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get unlockForgotPassword;

  /// Snackbar shown until the recovery-key flow is implemented
  ///
  /// In en, this message translates to:
  /// **'Recovery flow coming soon'**
  String get unlockForgotPasswordComingSoon;

  /// Error shown when password-based decryption fails
  ///
  /// In en, this message translates to:
  /// **'Incorrect master password. Please try again.'**
  String get unlockWrongPassword;

  /// Tooltip and caption for the biometric unlock button
  ///
  /// In en, this message translates to:
  /// **'Unlock with biometrics'**
  String get unlockBiometricHint;

  /// Localized reason passed to the OS biometric prompt
  ///
  /// In en, this message translates to:
  /// **'Authenticate to unlock your vault'**
  String get unlockBiometricPrompt;

  /// Error when no MK has been stashed yet for biometric unlock
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock is not set up on this device. Enter your master password.'**
  String get unlockBiometricUnavailable;

  /// Error when the OS biometric prompt is cancelled or fails
  ///
  /// In en, this message translates to:
  /// **'Biometric authentication failed. Please try again or use your password.'**
  String get unlockBiometricFailed;

  /// Tooltip on the lock-vault action in the home app bar
  ///
  /// In en, this message translates to:
  /// **'Lock Vault'**
  String get unlockLockVault;

  /// Headline on the first recovery step where the user enters their 24-word key
  ///
  /// In en, this message translates to:
  /// **'Recover Your Account'**
  String get recoveryTitle;

  /// Supporting copy explaining what recovery does on the enter-key step
  ///
  /// In en, this message translates to:
  /// **'Enter your 24-word recovery key. We\'ll use it to unwrap your vault locally — nothing is sent to our servers unencrypted.'**
  String get recoverySubtitle;

  /// Hint text shown inside the mnemonic text area
  ///
  /// In en, this message translates to:
  /// **'Type or paste your 24 recovery words, separated by spaces'**
  String get recoveryEnterKeyLabel;

  /// Secondary button that pastes the mnemonic from the clipboard
  ///
  /// In en, this message translates to:
  /// **'Paste from Clipboard'**
  String get recoveryPasteButton;

  /// Subject line used when sharing the recovery key file via the platform share sheet
  ///
  /// In en, this message translates to:
  /// **'Claw Vault Recovery Key'**
  String get recoveryShareSubject;

  /// Secondary button that imports the mnemonic from a file
  ///
  /// In en, this message translates to:
  /// **'Import from .txt File'**
  String get recoveryImportButton;

  /// Snackbar shown when the user taps import before the file picker is wired up
  ///
  /// In en, this message translates to:
  /// **'File import coming soon — paste from clipboard instead'**
  String get recoveryImportComingSoon;

  /// Headline on the second recovery step
  ///
  /// In en, this message translates to:
  /// **'Set a New Master Password'**
  String get recoveryNewPasswordTitle;

  /// Supporting copy on the new-password recovery step
  ///
  /// In en, this message translates to:
  /// **'Choose a new master password. It will replace the one you forgot.'**
  String get recoveryNewPasswordSubtitle;

  /// Label for the new password input
  ///
  /// In en, this message translates to:
  /// **'New Master Password'**
  String get recoveryNewPasswordLabel;

  /// Label for the password confirmation input
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get recoveryConfirmPasswordLabel;

  /// Primary button that triggers the full recovery pipeline
  ///
  /// In en, this message translates to:
  /// **'Recover Account'**
  String get recoveryRecoverButton;

  /// Headline on the final recovery step where the freshly generated mnemonic is displayed
  ///
  /// In en, this message translates to:
  /// **'Save Your New Recovery Key'**
  String get recoverySaveKeyTitle;

  /// Checkbox the user must tick before finishing recovery
  ///
  /// In en, this message translates to:
  /// **'I\'ve saved my new recovery key in a safe place'**
  String get recoverySaveKeyCheckbox;

  /// Primary button that closes the recovery flow
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get recoveryFinishButton;

  /// Button that copies the new recovery mnemonic to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get recoveryCopyButton;

  /// Error shown when the supplied mnemonic fails to decrypt the wrapped private key
  ///
  /// In en, this message translates to:
  /// **'This recovery key doesn\'t match our records. Double-check your 24 words and try again.'**
  String get recoveryWrongKey;

  /// Inline error when the new password and its confirmation disagree
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get recoveryPasswordMismatch;

  /// Error when the backend returns an account without recovery salt/ciphertext
  ///
  /// In en, this message translates to:
  /// **'This account cannot be recovered — no recovery key was set up. Please contact support.'**
  String get recoveryMaterialMissing;

  /// Generic fallback error for the recovery flow
  ///
  /// In en, this message translates to:
  /// **'Recovery failed. Please try again.'**
  String get recoveryServerError;

  /// Vaults section title shown in the app bar of the vault list
  ///
  /// In en, this message translates to:
  /// **'Vaults'**
  String get vaultTitle;

  /// Label of the button / FAB that opens the create-vault sheet
  ///
  /// In en, this message translates to:
  /// **'New Vault'**
  String get vaultNewVault;

  /// Empty-state title when the user has no vaults
  ///
  /// In en, this message translates to:
  /// **'No vaults yet'**
  String get vaultNoVaults;

  /// Empty-state subtitle shown alongside the create-vault CTA
  ///
  /// In en, this message translates to:
  /// **'Create your first vault to organize credentials and grant access to your AI agents.'**
  String get vaultCreateFirst;

  /// Retry button label on the vault list error state
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get vaultRetry;

  /// Generic cancel button label used in vault dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get vaultCancel;

  /// Label for the Full grant mode (one approval covers the whole vault)
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get vaultModeFull;

  /// Label for the Granular grant mode (per-entry approvals)
  ///
  /// In en, this message translates to:
  /// **'Granular'**
  String get vaultModeGranular;

  /// Subtitle for the Full mode option in the vault form
  ///
  /// In en, this message translates to:
  /// **'One approval grants access to every entry.'**
  String get vaultModeFullDescription;

  /// Subtitle for the Granular mode option in the vault form
  ///
  /// In en, this message translates to:
  /// **'Each entry needs its own approval.'**
  String get vaultModeGranularDescription;

  /// Label above the grant mode selector in the vault form
  ///
  /// In en, this message translates to:
  /// **'Grant mode'**
  String get vaultModeLabel;

  /// Label for the vault name field
  ///
  /// In en, this message translates to:
  /// **'Vault Name'**
  String get vaultNameLabel;

  /// Label for the optional vault description field
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get vaultDescriptionLabel;

  /// Label above the icon picker in the vault form
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get vaultIconLabel;

  /// Label above the color picker in the vault form
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get vaultColorLabel;

  /// Loading label shown on the create button while the vault is being created
  ///
  /// In en, this message translates to:
  /// **'Creating...'**
  String get vaultCreating;

  /// Loading label shown on the save button while the vault is being updated
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get vaultSaving;

  /// Snackbar shown after a successful vault update
  ///
  /// In en, this message translates to:
  /// **'Vault updated'**
  String get vaultSavedSnackbar;

  /// Title of the delete-vault confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Vault?'**
  String get vaultDeleteTitle;

  /// Body of the delete-vault confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete \"{name}\" and all its entries. This cannot be undone.'**
  String vaultDeleteConfirmWithName(String name);

  /// Title of the vault settings page
  ///
  /// In en, this message translates to:
  /// **'Vault Settings'**
  String get vaultSettings;

  /// Save button label on the vault settings page
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get vaultSaveChanges;

  /// Section label for destructive actions on the vault settings page
  ///
  /// In en, this message translates to:
  /// **'DANGER ZONE'**
  String get vaultDangerZone;

  /// Explanatory text under the danger zone heading
  ///
  /// In en, this message translates to:
  /// **'Deleting a vault is permanent — entries and grants are removed too.'**
  String get vaultDangerZoneSubtitle;

  /// Destructive action button label
  ///
  /// In en, this message translates to:
  /// **'Delete Vault'**
  String get vaultDeleteVault;

  /// Vault card meta line: number of entries
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No entries} =1{1 entry} other{{count} entries}}'**
  String vaultEntryCount(int count);

  /// Vault card meta line: when the vault was last updated
  ///
  /// In en, this message translates to:
  /// **'Updated {date}'**
  String vaultUpdatedAt(String date);

  /// Relative timestamp label shown on a vault card when the vault was updated less than a minute ago
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get vaultUpdatedNow;

  /// Relative timestamp shown on a vault card when the last update was less than an hour ago
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1m ago} other{{count}m ago}}'**
  String vaultUpdatedMinutesAgo(int count);

  /// Relative timestamp shown on a vault card when the last update was less than a day ago
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1h ago} other{{count}h ago}}'**
  String vaultUpdatedHoursAgo(int count);

  /// Relative timestamp shown on a vault card when the last update was less than 30 days ago
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1d ago} other{{count}d ago}}'**
  String vaultUpdatedDaysAgo(int count);

  /// Stat chip label on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get vaultStatEntries;

  /// Stat chip label on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Active grants'**
  String get vaultStatActiveGrants;

  /// Stat chip label on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get vaultStatMembers;

  /// Section heading on the vault detail page for the entries list
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get vaultSectionEntries;

  /// Section heading on the vault detail page for the agents list
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get vaultSectionAgents;

  /// Placeholder card title under Entries on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Entries coming soon'**
  String get vaultEntriesPlaceholderTitle;

  /// Placeholder card body under Entries on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Add and manage credentials from the web panel for now — mobile entry management lands in the next phase.'**
  String get vaultEntriesPlaceholderSubtitle;

  /// Placeholder card title under Agents on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Agents coming soon'**
  String get vaultAgentsPlaceholderTitle;

  /// Placeholder card body under Agents on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Approve agent grants from the home screen — per-vault agent management is on the roadmap.'**
  String get vaultAgentsPlaceholderSubtitle;

  /// Error shown when the backend returns 404 for a vault operation
  ///
  /// In en, this message translates to:
  /// **'This vault no longer exists.'**
  String get vaultErrorNotFound;

  /// Error shown when the backend returns 403 without a more specific reason
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to perform this action.'**
  String get vaultErrorForbidden;

  /// Error shown when the user has hit the vault count cap for their billing plan
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached the vault limit for your plan. Upgrade to create more.'**
  String get vaultErrorPlanLimitReached;

  /// Error shown when the user tries to create a Full-mode vault on a plan that doesn't support it
  ///
  /// In en, this message translates to:
  /// **'Your plan doesn\'t allow Full-mode vaults. Choose Granular or upgrade.'**
  String get vaultErrorFullModeNotAllowed;

  /// Generic fallback error for vault operations
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get vaultErrorUnknown;

  /// Vault card header right-side label: count of grants on the vault
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No grants} =1{1 grant} other{{count} grants}}'**
  String vaultGrantCount(int count);

  /// Vault card footer label: number of currently active grants
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No active grants} =1{1 active grant} other{{count} active grants}}'**
  String vaultActiveGrantCount(int count);

  /// Vault detail tab — Entries
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get vaultTabEntries;

  /// Vault detail tab — Agents
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get vaultTabAgents;

  /// Vault detail tab — Logs
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get vaultTabLogs;

  /// Vault detail tab — Members
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get vaultTabMembers;

  /// Vault detail tab — Settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get vaultTabSettings;

  /// Placeholder for the search input on the Entries tab
  ///
  /// In en, this message translates to:
  /// **'Search entries…'**
  String get vaultSearchEntries;

  /// Placeholder for the search input on the Agents tab
  ///
  /// In en, this message translates to:
  /// **'Search agents…'**
  String get vaultSearchAgents;

  /// Mode label on a grant card — full vault access
  ///
  /// In en, this message translates to:
  /// **'Full access'**
  String get vaultGrantFull;

  /// Mode label on a grant card — per-entry access
  ///
  /// In en, this message translates to:
  /// **'Granular'**
  String get vaultGrantGranular;

  /// Status pill on the grant card — currently active
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get vaultGrantActive;

  /// Status pill on the grant card — expired
  ///
  /// In en, this message translates to:
  /// **'expired'**
  String get vaultGrantExpired;

  /// Status pill on the grant card — revoked by the vault owner
  ///
  /// In en, this message translates to:
  /// **'revoked'**
  String get vaultGrantRevoked;

  /// Footer line on an active / expired grant card
  ///
  /// In en, this message translates to:
  /// **'Granted by {person} at {date}'**
  String vaultGrantGrantedBy(String person, String date);

  /// Footer line on a revoked grant card
  ///
  /// In en, this message translates to:
  /// **'Revoked by {person} at {date}'**
  String vaultGrantRevokedBy(String person, String date);

  /// Trailing chip indicating extra entries hidden inside a granular grant
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String vaultGrantMoreEntries(int count);

  /// Action button on an active grant card
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get vaultRevokeButton;

  /// Action button on a revoked grant card
  ///
  /// In en, this message translates to:
  /// **'Re-grant'**
  String get vaultRegrantButton;

  /// Action button on an expired grant card
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get vaultRestoreButton;

  /// Empty-state title for the Entries tab when no entries exist
  ///
  /// In en, this message translates to:
  /// **'No entries yet'**
  String get vaultEntriesEmpty;

  /// Empty-state title for the Agents tab when no grants exist
  ///
  /// In en, this message translates to:
  /// **'No agents granted access'**
  String get vaultAgentsEmpty;

  /// Placeholder copy on the Logs tab
  ///
  /// In en, this message translates to:
  /// **'Activity log coming soon'**
  String get vaultLogsEmpty;

  /// Placeholder copy on the Members tab
  ///
  /// In en, this message translates to:
  /// **'Member management coming soon'**
  String get vaultMembersEmpty;

  /// Tooltip on the entry-row reveal button
  ///
  /// In en, this message translates to:
  /// **'Reveal entry data'**
  String get vaultRevealEntry;

  /// Tooltip on the entry-row arrow button
  ///
  /// In en, this message translates to:
  /// **'View entry details'**
  String get vaultViewEntry;

  /// Tooltip on the copy-to-clipboard button inside a revealed entry panel
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get vaultCopyValue;

  /// Tooltip on the open-in-browser button inside a revealed entry panel
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get vaultOpenLink;

  /// Tooltip on the visibility-toggle button next to a masked value
  ///
  /// In en, this message translates to:
  /// **'Reveal value'**
  String get vaultRevealValue;

  /// AppBar action label on the vault settings tab
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get vaultSaveAction;

  /// Tooltip / accessibility label for the FAB on the Entries tab
  ///
  /// In en, this message translates to:
  /// **'Add entry'**
  String get vaultAddEntryFab;

  /// Tooltip / accessibility label for the FAB on the Agents tab
  ///
  /// In en, this message translates to:
  /// **'Add grant'**
  String get vaultAddGrantFab;

  /// Tooltip for the upload-custom-icon button in the icon picker
  ///
  /// In en, this message translates to:
  /// **'Upload custom icon'**
  String get vaultIconUpload;

  /// Error shown when S3 icon upload fails
  ///
  /// In en, this message translates to:
  /// **'Upload failed. Please try again.'**
  String get vaultIconUploadError;

  /// Error shown when selected file is too large
  ///
  /// In en, this message translates to:
  /// **'File exceeds 2 MB limit.'**
  String get vaultIconUploadSizeError;

  /// Error shown when selected file has an unsupported format
  ///
  /// In en, this message translates to:
  /// **'Unsupported format. Use PNG, JPEG or WebP.'**
  String get vaultIconUploadFormatError;

  /// Label for the Pro-upgrade FAB shown when a Basic-plan user has hit the single-vault limit
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro'**
  String get vaultUpgradeToPro;

  /// Snackbar shown when the user taps the upgrade FAB before the billing flow ships
  ///
  /// In en, this message translates to:
  /// **'Upgrade flow coming soon — you\'ve reached the Basic plan\'s single-vault limit.'**
  String get vaultUpgradeComingSoon;

  /// Bottom nav label for the Home tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom nav label for the Vaults tab
  ///
  /// In en, this message translates to:
  /// **'Vaults'**
  String get navVaults;

  /// Bottom nav label for the Agents tab
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get navAgents;

  /// Bottom nav label for the Audit tab
  ///
  /// In en, this message translates to:
  /// **'Audit'**
  String get navAudit;

  /// Bottom nav label for the Settings tab
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Header title shown on the vault list page
  ///
  /// In en, this message translates to:
  /// **'My Vaults'**
  String get vaultListTitle;

  /// Subtitle under the vault list header — count of vaults and total entries across them
  ///
  /// In en, this message translates to:
  /// **'{vaultCount, plural, =1{1 vault} other{{vaultCount} vaults}} · {entryCount, plural, =0{no entries} =1{1 entry} other{{entryCount} entries}}'**
  String vaultListSummary(int vaultCount, int entryCount);

  /// Placeholder for the search input on the vault list page
  ///
  /// In en, this message translates to:
  /// **'Search vaults…'**
  String get vaultSearchHint;

  /// Empty-state title when a search query has no matches in the vault list
  ///
  /// In en, this message translates to:
  /// **'No vaults match your search'**
  String get vaultSearchEmpty;

  /// Section title in the settings drawer for account-related actions
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountTitle;

  /// Settings drawer item: lock the vault but keep the user signed in
  ///
  /// In en, this message translates to:
  /// **'Lock Vault'**
  String get settingsLockVault;

  /// Settings drawer item: full sign-out, returns to the login screen
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get settingsLogout;

  /// Footer text in the settings drawer showing the app version
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsAppVersion(String version);

  /// Accessibility / tooltip label for the settings icon button in the vault list header
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get settingsTooltip;

  /// Headline of the premium-gate bottom sheet shown when a Basic-plan user taps the New Vault FAB
  ///
  /// In en, this message translates to:
  /// **'Unlock unlimited vaults'**
  String get premiumGateTitle;

  /// Supporting copy on the premium-gate bottom sheet
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached the 1-vault limit on the free plan.'**
  String get premiumGateSubtitle;

  /// Primary CTA on the premium-gate bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro'**
  String get premiumGateCta;

  /// Secondary / dismiss button on the premium-gate bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get premiumGateDismiss;

  /// Settings drawer row label for the dark/light theme toggle
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get settingsThemeToggle;

  /// Settings drawer row label for the EN/PL language selector
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Plan badge in the settings drawer header for users with the premium permission bit set
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get settingsPlanPro;

  /// Plan label in the settings drawer header for users on the free plan
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get settingsPlanFree;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pl':
      return AppLocalizationsPl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
