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
  /// **'Palladin'**
  String get appTitle;

  /// Greeting shown on the home/dashboard placeholder page
  ///
  /// In en, this message translates to:
  /// **'Welcome to Palladin'**
  String get welcomeMessage;

  /// Rotating welcome line on the login screen — zero-knowledge
  ///
  /// In en, this message translates to:
  /// **'Zero-knowledge by design.'**
  String get loginRotatingZeroKnowledge;

  /// Rotating welcome line on the login screen — built for agents
  ///
  /// In en, this message translates to:
  /// **'Built for AI agents.'**
  String get loginRotatingForAgents;

  /// Rotating welcome line on the login screen — your keys
  ///
  /// In en, this message translates to:
  /// **'Your keys, your rules.'**
  String get loginRotatingYourKeys;

  /// Rotating welcome line on the login screen — always encrypted
  ///
  /// In en, this message translates to:
  /// **'Always encrypted.'**
  String get loginRotatingEncrypted;

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

  /// Error shown when the session/refresh token has expired and the account material can't be fetched — the user is routed back to sign-in
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please sign in again.'**
  String get unlockSessionExpired;

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
  /// **'Palladin Recovery Key'**
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

  /// Entry Agents tab — empty state title
  ///
  /// In en, this message translates to:
  /// **'No agents have access'**
  String get entryAgentsEmptyTitle;

  /// Entry Agents tab — empty state hint
  ///
  /// In en, this message translates to:
  /// **'No agent has been granted access to this entry yet.'**
  String get entryAgentsEmptyHint;

  /// Vault Agents tab — empty state title
  ///
  /// In en, this message translates to:
  /// **'No agents have access'**
  String get vaultAgentsEmptyTitle;

  /// Vault Agents tab — empty hint
  ///
  /// In en, this message translates to:
  /// **'No agent has been granted access to this vault yet.'**
  String get vaultAgentsEmptyHint;

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

  /// Bottom nav label for the Approvals (pending grants) tab
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get navApprovals;

  /// Bottom nav label for the business notification inbox
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get navInbox;

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

  /// Fallback display name shown in the settings drawer header when the user's email is missing or empty
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get settingsDefaultDisplayName;

  /// Generic 'coming soon' label used on placeholder pages for tabs not yet implemented
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get placeholderComingSoon;

  /// Page title for the Audit placeholder page — distinct from the bottom-nav 'Audit' label so the page reads as a full screen heading
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get placeholderAuditTitle;

  /// AppBar title on the Add Entry page
  ///
  /// In en, this message translates to:
  /// **'Add Entry'**
  String get entryAddTitle;

  /// AppBar title on the Entry Detail page when no label is known yet
  ///
  /// In en, this message translates to:
  /// **'Entry Details'**
  String get entryDetailTitle;

  /// Details tab label on the Entry Detail page (contains the edit form)
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get entryTabDetails;

  /// Shown while the detail page is decrypting the entry payload before the form can be shown
  ///
  /// In en, this message translates to:
  /// **'Loading entry data…'**
  String get entryRevealingForEdit;

  /// Section heading for the delete entry button at the bottom of the Details tab
  ///
  /// In en, this message translates to:
  /// **'Danger Zone'**
  String get entryDangerZone;

  /// Title of the delete entry confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Entry?'**
  String get entryDeleteTitle;

  /// Body of the delete entry confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete this entry and its encrypted data. This cannot be undone.'**
  String get entryDeleteConfirm;

  /// Destructive button label in the delete entry dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Entry'**
  String get entryDeleteAction;

  /// Button label while the delete request is in flight
  ///
  /// In en, this message translates to:
  /// **'Deleting…'**
  String get entryDeleting;

  /// Label above the entry-type dropdown on the Add Entry page
  ///
  /// In en, this message translates to:
  /// **'Entry type'**
  String get entryTypeLabel;

  /// Dropdown option for the Key entry type — single secret value
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get entryTypeKey;

  /// Dropdown option for the Credential entry type — username + password
  ///
  /// In en, this message translates to:
  /// **'Credential'**
  String get entryTypeCredential;

  /// Label for the entry name input field
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get entryLabelLabel;

  /// Placeholder text inside the entry label input field
  ///
  /// In en, this message translates to:
  /// **'e.g. Stripe API Key'**
  String get entryLabelHint;

  /// Label for the optional entry description input field
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get entryDescriptionLabel;

  /// Label for the secret value input field on a Key entry
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get entryValueLabel;

  /// Label for the username input field on a Credential entry
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get entryUsernameLabel;

  /// Label for the password input field on a Credential entry
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get entryPasswordLabel;

  /// Label for the optional URL input field on a Credential entry
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get entryUrlLabel;

  /// Validation error shown below the URL field when the value is not a valid URL
  ///
  /// In en, this message translates to:
  /// **'Enter a valid URL (e.g. stripe.com or https://stripe.com)'**
  String get entryUrlInvalid;

  /// Label for the optional notes input field on every entry
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get entryNotesLabel;

  /// Reassurance shown above the save button on the Add Entry page
  ///
  /// In en, this message translates to:
  /// **'Encrypted on-device with XSalsa20-Poly1305 before upload'**
  String get entryEncryptionNotice;

  /// Placeholder for the search input on the Entries tab
  ///
  /// In en, this message translates to:
  /// **'Search entries…'**
  String get entrySearchHint;

  /// Empty-state title shown on the Entries tab when no entries exist yet
  ///
  /// In en, this message translates to:
  /// **'No entries yet'**
  String get entryEmpty;

  /// Empty-state subtitle nudging the user to use the Add Entry FAB
  ///
  /// In en, this message translates to:
  /// **'Add your first credential to get started.'**
  String get entryEmptyAdd;

  /// AppBar action label on the Add Entry page
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get entrySaveAction;

  /// Loading label shown on the save button while the entry is being created
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get entrySaving;

  /// Error shown when the backend returns 404 for an entry operation
  ///
  /// In en, this message translates to:
  /// **'This entry no longer exists.'**
  String get entryErrorNotFound;

  /// Error shown when the backend returns 403 for an entry operation
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to perform this action.'**
  String get entryErrorForbidden;

  /// Error shown when the backend returns 400 for an entry operation
  ///
  /// In en, this message translates to:
  /// **'Some fields are invalid. Please review and try again.'**
  String get entryErrorValidation;

  /// Error shown when entry encryption or decryption fails
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t decrypt this entry. Lock and unlock your vault, then try again.'**
  String get entryErrorCrypto;

  /// Generic fallback error for entry operations
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get entryErrorUnknown;

  /// Title of the dedicated settings screen (organization details)
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsScreenTitle;

  /// Heading for the organization section on the settings screen
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get settingsOrganization;

  /// Label for the settings-drawer item that opens the organization settings screen
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get settingsManageOrganization;

  /// Label for the editable organization name input field
  ///
  /// In en, this message translates to:
  /// **'Organization name'**
  String get settingsOrgNameLabel;

  /// Placeholder text for the organization name input field
  ///
  /// In en, this message translates to:
  /// **'Enter organization name'**
  String get settingsOrgNameHint;

  /// Member count shown under the organization name
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String settingsOrgMembers(int count);

  /// Label for the save button on the organization form
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsSave;

  /// Snackbar confirmation shown after a successful organization rename
  ///
  /// In en, this message translates to:
  /// **'Organization name updated.'**
  String get settingsOrgSaved;

  /// Label for the settings-drawer item that opens the standalone API keys screen
  ///
  /// In en, this message translates to:
  /// **'API keys'**
  String get settingsApiKeys;

  /// Label for the retry button on settings error states
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get settingsRetry;

  /// Error shown when the backend returns 404 for a settings operation
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find this resource.'**
  String get settingsErrorNotFound;

  /// Error shown when the backend returns 403 for a settings operation
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to perform this action.'**
  String get settingsErrorForbidden;

  /// Error shown when the backend returns 400 for a settings operation
  ///
  /// In en, this message translates to:
  /// **'Please check the form and try again.'**
  String get settingsErrorValidation;

  /// Generic fallback error for settings operations
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get settingsErrorUnknown;

  /// Title of the standalone API keys list screen
  ///
  /// In en, this message translates to:
  /// **'API keys'**
  String get apiKeysScreenTitle;

  /// Empty-state title shown when the organization has no API keys
  ///
  /// In en, this message translates to:
  /// **'No API keys yet'**
  String get apiKeysEmpty;

  /// Empty-state supporting copy for the API keys list
  ///
  /// In en, this message translates to:
  /// **'Generate a key to connect your first agent.'**
  String get apiKeysEmptyHint;

  /// Status badge label for an active API key
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get apiKeysStatusActive;

  /// Status badge label for a revoked API key
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get apiKeysStatusRevoked;

  /// Label for the retry button on API keys error states
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get apiKeysRetry;

  /// Tooltip / heading for the generate-API-key action and sheet
  ///
  /// In en, this message translates to:
  /// **'Generate API key'**
  String get apiKeysGenerate;

  /// Submit-button label in the generate-API-key sheet
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get apiKeysGenerateAction;

  /// Loading label shown on the generate button while the key is being created
  ///
  /// In en, this message translates to:
  /// **'Generating…'**
  String get apiKeysGenerating;

  /// Label for the API key name input field in the generate sheet
  ///
  /// In en, this message translates to:
  /// **'Key name'**
  String get apiKeysNameLabel;

  /// Placeholder text for the API key name input field
  ///
  /// In en, this message translates to:
  /// **'e.g. Production agent'**
  String get apiKeysNameHint;

  /// Title of the one-time secret reveal step in the generate sheet
  ///
  /// In en, this message translates to:
  /// **'API key created'**
  String get apiKeysSecretTitle;

  /// Warning shown above the one-time plaintext API key secret
  ///
  /// In en, this message translates to:
  /// **'Save this key now — it will never be shown again.'**
  String get apiKeysSecretWarning;

  /// Label for the copy-to-clipboard button next to the API key secret
  ///
  /// In en, this message translates to:
  /// **'Copy key'**
  String get apiKeysCopyKey;

  /// Snackbar confirmation shown after copying the API key secret
  ///
  /// In en, this message translates to:
  /// **'API key copied to clipboard.'**
  String get apiKeysKeyCopied;

  /// Label for the button that dismisses the secret reveal step
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get apiKeysDone;

  /// Generic cancel label used by API key dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get apiKeysCancel;

  /// Label for the action that revokes an API key
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get apiKeysRevoke;

  /// Title of the revoke-API-key confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Revoke API key?'**
  String get apiKeysRevokeConfirmTitle;

  /// Body of the revoke-API-key confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Agents using \"{name}\" will lose access immediately. This cannot be undone.'**
  String apiKeysRevokeConfirmBody(String name);

  /// Fallback AppBar title on the API key detail screen while the key is loading
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get apiKeysDetailTitle;

  /// Message shown on the API key detail screen when the key id cannot be resolved
  ///
  /// In en, this message translates to:
  /// **'This API key no longer exists.'**
  String get apiKeysDetailNotFound;

  /// Label of the Details tab on the API key detail screen
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get apiKeysTabDetails;

  /// Label of the Agents tab on the API key detail screen
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get apiKeysTabAgents;

  /// Label for the masked key row on the API key detail screen
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get apiKeysDetailKey;

  /// Label for the created-date row on the API key detail screen
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get apiKeysDetailCreatedAt;

  /// Label for the revoked-date row on the API key detail screen
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get apiKeysDetailRevokedAt;

  /// Button label to re-activate a revoked API key
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get apiKeysActivate;

  /// Button label while activation is in flight
  ///
  /// In en, this message translates to:
  /// **'Activating…'**
  String get apiKeysActivating;

  /// Button label to permanently delete a revoked API key
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get apiKeysDeletePermanently;

  /// Button label while delete is in flight
  ///
  /// In en, this message translates to:
  /// **'Deleting…'**
  String get apiKeysDeleting;

  /// Title of the permanent-delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete API key?'**
  String get apiKeysDeleteConfirmTitle;

  /// Body of the permanent-delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete \"{name}\". This cannot be undone.'**
  String apiKeysDeleteConfirmBody(String name);

  /// Section header for the activate section on the revoked key detail page
  ///
  /// In en, this message translates to:
  /// **'ACTIVATE KEY'**
  String get apiKeysActivateZone;

  /// Subtitle in the activate section
  ///
  /// In en, this message translates to:
  /// **'Re-enable this key — agents using it will regain access immediately.'**
  String get apiKeysActivateHint;

  /// Count summary in the API keys screen AppBar subtitle
  ///
  /// In en, this message translates to:
  /// **'{total} keys · {active} active'**
  String apiKeysListSummary(int total, int active);

  /// Title of the agents list screen
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get agentsScreenTitle;

  /// Count summary in the agents screen AppBar subtitle
  ///
  /// In en, this message translates to:
  /// **'{total} agents, {active} active'**
  String agentsListSummary(int total, int active);

  /// Empty-state title for the agents list
  ///
  /// In en, this message translates to:
  /// **'No agents yet'**
  String get agentsEmpty;

  /// Empty-state hint for the agents list
  ///
  /// In en, this message translates to:
  /// **'Connect your first agent using the CLI to get started'**
  String get agentsEmptyHint;

  /// Placeholder text for the agents search field
  ///
  /// In en, this message translates to:
  /// **'Search agents…'**
  String get agentsSearchHint;

  /// Shown when the search query returns no results
  ///
  /// In en, this message translates to:
  /// **'No agents match your search'**
  String get agentsSearchEmpty;

  /// Fallback display name for an agent with no name set
  ///
  /// In en, this message translates to:
  /// **'Unnamed agent'**
  String get agentsUnnamed;

  /// Prompt shown in the split-view detail pane when no agent is selected
  ///
  /// In en, this message translates to:
  /// **'Select an agent to see its details'**
  String get agentsSplitPrompt;

  /// Agent status label — active
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get agentsStatusActive;

  /// Agent status label — pending approval
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get agentsStatusPending;

  /// Agent status label — deactivated
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get agentsStatusDeactivated;

  /// Prefix for the enrolled-date subtitle on an agent card
  ///
  /// In en, this message translates to:
  /// **'Enrolled'**
  String get agentsEnrolled;

  /// Prefix for the deactivated-date subtitle on an agent card
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get agentsDeactivated;

  /// Prefix for the deactivated-date in the agent card footer
  ///
  /// In en, this message translates to:
  /// **'Deactivated on'**
  String get agentsDeactivatedOn;

  /// Prefix for the first-connected-date in the agent card footer
  ///
  /// In en, this message translates to:
  /// **'Connected on'**
  String get agentsConnectedOn;

  /// Prefix for the last-access-date in the agent card footer
  ///
  /// In en, this message translates to:
  /// **'Last access'**
  String get agentsLastAccess;

  /// Subtitle on a pending agent card
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get agentsPendingApproval;

  /// Generic title of the agent detail screen while loading
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get agentsDetailTitle;

  /// Shown when the requested agent does not exist
  ///
  /// In en, this message translates to:
  /// **'Agent not found'**
  String get agentsDetailNotFound;

  /// Label for the agent id row on the detail screen
  ///
  /// In en, this message translates to:
  /// **'Id'**
  String get agentsDetailId;

  /// Label for the public key suffix row
  ///
  /// In en, this message translates to:
  /// **'Public Key'**
  String get agentsDetailPublicKey;

  /// Label for the date the agent first connected
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get agentsDetailCreatedAt;

  /// Label for the date the agent was approved
  ///
  /// In en, this message translates to:
  /// **'Enrolled'**
  String get agentsDetailEnrolledAt;

  /// Label for who approved the agent
  ///
  /// In en, this message translates to:
  /// **'Enrolled by'**
  String get agentsDetailEnrolledBy;

  /// Label for the date the agent was deactivated
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get agentsDetailDeactivatedAt;

  /// Section header for the approve zone on a pending agent
  ///
  /// In en, this message translates to:
  /// **'APPROVE AGENT'**
  String get agentsApproveZone;

  /// Hint in the approve zone
  ///
  /// In en, this message translates to:
  /// **'Lets this agent browse vault and entry listings only — secret contents stay locked until you approve a request or grant access in advance.'**
  String get agentsApproveHint;

  /// Button label to approve a pending agent
  ///
  /// In en, this message translates to:
  /// **'Approve Agent'**
  String get agentsApprove;

  /// Button label while approval is in flight
  ///
  /// In en, this message translates to:
  /// **'Approving…'**
  String get agentsApproving;

  /// Section header for the deactivate danger zone
  ///
  /// In en, this message translates to:
  /// **'DANGER ZONE'**
  String get agentsDeactivateZone;

  /// Hint inside the deactivate danger zone
  ///
  /// In en, this message translates to:
  /// **'This agent will immediately lose access to all vaults'**
  String get agentsDeactivateHint;

  /// Button label to deactivate an active agent
  ///
  /// In en, this message translates to:
  /// **'Deactivate Agent'**
  String get agentsDeactivate;

  /// Button label while deactivation is in flight
  ///
  /// In en, this message translates to:
  /// **'Deactivating…'**
  String get agentsDeactivating;

  /// Section header for the reactivate zone on a deactivated agent
  ///
  /// In en, this message translates to:
  /// **'REACTIVATE'**
  String get agentsReactivateZone;

  /// Hint in the reactivate zone
  ///
  /// In en, this message translates to:
  /// **'Re-enable access for this agent'**
  String get agentsReactivateHint;

  /// Button label to reactivate a deactivated agent
  ///
  /// In en, this message translates to:
  /// **'Reactivate Agent'**
  String get agentsReactivate;

  /// Button label while reactivation is in flight
  ///
  /// In en, this message translates to:
  /// **'Reactivating…'**
  String get agentsReactivating;

  /// Title of the approve confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'Approve Agent'**
  String get agentsApproveConfirmTitle;

  /// Body of the approve confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'Allow \"{name}\" to browse vault and entry listings? It still can\'t read any secret without your approval or a pre-granted access.'**
  String agentsApproveConfirmBody(String name);

  /// Title of the deactivate confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'Deactivate Agent'**
  String get agentsDeactivateConfirmTitle;

  /// Body of the deactivate confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'Deactivate \"{name}\"? It will immediately lose access.'**
  String agentsDeactivateConfirmBody(String name);

  /// Title of the agent edit screen
  ///
  /// In en, this message translates to:
  /// **'Edit Agent'**
  String get agentsEditTitle;

  /// Label for the agent display-name field
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get agentsEditName;

  /// Label for the agent description field
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get agentsEditDescription;

  /// Save button on the agent edit screen
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get agentsEditSave;

  /// Retry button on the agents error state
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get agentsRetry;

  /// Label / tooltip for the edit-agent action
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get agentsEditIcon;

  /// Title of the approve-agent form sheet
  ///
  /// In en, this message translates to:
  /// **'Approve Agent'**
  String get agentApproveTitle;

  /// Label for the optional agent name input in the approve form
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get agentNameLabel;

  /// Label for the agent type chip group in the approve form
  ///
  /// In en, this message translates to:
  /// **'Agent type'**
  String get agentTypeLabel;

  /// Label for the agent icon picker in the approve form
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get agentIconLabel;

  /// Agent type option — Open Claw
  ///
  /// In en, this message translates to:
  /// **'Open Claw'**
  String get agentTypeOpenClaw;

  /// Agent type option — Claude Code
  ///
  /// In en, this message translates to:
  /// **'Claude Code'**
  String get agentTypeClaudeCode;

  /// Agent type option — Hermes
  ///
  /// In en, this message translates to:
  /// **'Hermes'**
  String get agentTypeHermes;

  /// Agent type option — Cursor
  ///
  /// In en, this message translates to:
  /// **'Cursor'**
  String get agentTypeCursor;

  /// Agent type option — GitHub Copilot
  ///
  /// In en, this message translates to:
  /// **'GitHub Copilot'**
  String get agentTypeCopilot;

  /// Agent type option — Gemini
  ///
  /// In en, this message translates to:
  /// **'Gemini'**
  String get agentTypeGemini;

  /// Agent type option — OpenAI Codex
  ///
  /// In en, this message translates to:
  /// **'OpenAI Codex'**
  String get agentTypeCodex;

  /// Agent type option — Kimi Code
  ///
  /// In en, this message translates to:
  /// **'Kimi Code'**
  String get agentTypeKimiCode;

  /// Agent type option — Devin
  ///
  /// In en, this message translates to:
  /// **'Devin'**
  String get agentTypeDevin;

  /// Agent type option — Aider
  ///
  /// In en, this message translates to:
  /// **'Aider'**
  String get agentTypeAider;

  /// Agent type option — Cline
  ///
  /// In en, this message translates to:
  /// **'Cline'**
  String get agentTypeCline;

  /// Agent type option — Roo Code
  ///
  /// In en, this message translates to:
  /// **'Roo Code'**
  String get agentTypeRoo;

  /// Agent type option — Other
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get agentTypeOther;

  /// Subtitle under the approve-agent dialog title
  ///
  /// In en, this message translates to:
  /// **'Optionally set a name, type, and icon before activating.'**
  String get agentApproveSetupHint;

  /// Placeholder for the agent name input on the approve form
  ///
  /// In en, this message translates to:
  /// **'e.g. Claude Code, Cursor'**
  String get agentNamePlaceholder;

  /// Tab label — agent details tab
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get agentsTabDetails;

  /// Tab label — agent grants tab
  ///
  /// In en, this message translates to:
  /// **'Grants'**
  String get agentsTabGrants;

  /// Agent Grants tab — empty title
  ///
  /// In en, this message translates to:
  /// **'No grants yet'**
  String get agentGrantsEmptyTitle;

  /// Agent Grants tab — empty hint
  ///
  /// In en, this message translates to:
  /// **'This agent has no grants. Add one to give it access to a vault or entry.'**
  String get agentGrantsEmptyHint;

  /// Tab label — agent logs tab
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get agentsTabLogs;

  /// Empty state for the agent grants tab
  ///
  /// In en, this message translates to:
  /// **'No active grants'**
  String get agentsGrantsEmpty;

  /// Empty state hint for the agent grants tab
  ///
  /// In en, this message translates to:
  /// **'This agent has not been granted access to any vault entries yet'**
  String get agentsGrantsEmptyHint;

  /// Timeline entry — agent first connected
  ///
  /// In en, this message translates to:
  /// **'First connected'**
  String get agentsLogsFirstConnected;

  /// Timeline entry — agent was enrolled / approved
  ///
  /// In en, this message translates to:
  /// **'Enrolled'**
  String get agentsLogsEnrolled;

  /// Timeline entry — agent was deactivated
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get agentsLogsDeactivated;

  /// Snackbar after saving agent edit changes
  ///
  /// In en, this message translates to:
  /// **'Agent saved'**
  String get agentsEditSaved;

  /// Placeholder for the agent type combobox in the approve form
  ///
  /// In en, this message translates to:
  /// **'Pick a preset or type a custom value'**
  String get agentTypePlaceholder;

  /// Accessibility label for the 'more' tile that opens the icon browser
  ///
  /// In en, this message translates to:
  /// **'More icons'**
  String get agentIconMore;

  /// Header of the icon browser modal
  ///
  /// In en, this message translates to:
  /// **'Browse icons'**
  String get agentIconBrowserTitle;

  /// Label above the color swatches in the icon browser modal
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get agentIconColorLabel;

  /// Confirm button label inside the icon browser modal
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get agentIconChoose;

  /// Fallback type label on the agent card when no type is set
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get agentsTypeUnknown;

  /// Label for the last known IP address of the agent
  ///
  /// In en, this message translates to:
  /// **'Last IP'**
  String get agentsDetailLastIp;

  /// Label for the last known hostname of the agent
  ///
  /// In en, this message translates to:
  /// **'Last Hostname'**
  String get agentsDetailLastHostname;

  /// Title of the grant-management list screen
  ///
  /// In en, this message translates to:
  /// **'Grants'**
  String get grantsScreenTitle;

  /// Status filter chip — show grants of every status
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get grantsFilterAll;

  /// Retry button on the grants error state
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get grantsRetry;

  /// Empty-state title on the grants list
  ///
  /// In en, this message translates to:
  /// **'No grants yet'**
  String get grantsEmpty;

  /// Empty-state hint on the grants list
  ///
  /// In en, this message translates to:
  /// **'Grants appear here when an agent requests access to this vault.'**
  String get grantsEmptyHint;

  /// Revoke action button label
  ///
  /// In en, this message translates to:
  /// **'Revoke grant'**
  String get grantsRevoke;

  /// Title of the revoke confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'Revoke grant?'**
  String get grantsRevokeConfirmTitle;

  /// Body of the revoke confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'{agentName} will immediately lose access. This cannot be undone.'**
  String grantsRevokeConfirmBody(String agentName);

  /// Label for the optional revoke reason field
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get grantsRevokeReasonLabel;

  /// Hint for the optional revoke reason field
  ///
  /// In en, this message translates to:
  /// **'Why are you revoking this grant?'**
  String get grantsRevokeReasonHint;

  /// One-line target summary on a grant card
  ///
  /// In en, this message translates to:
  /// **'Access to {target}'**
  String grantCardTarget(String target);

  /// Fallback when a granular grant's entry label is missing
  ///
  /// In en, this message translates to:
  /// **'Unknown entry'**
  String get grantEntryUnknown;

  /// Fallback display name for an agent without a name
  ///
  /// In en, this message translates to:
  /// **'Unnamed agent'**
  String get grantUnnamedAgent;

  /// Grant status label — pending approval
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get grantStatusPending;

  /// Grant status label — active
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get grantStatusActive;

  /// Grant status label — denied
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get grantStatusDenied;

  /// Grant status label — revoked
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get grantStatusRevoked;

  /// Grant status label — expired
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get grantStatusExpired;

  /// Grant status label — query limit exhausted
  ///
  /// In en, this message translates to:
  /// **'Consumed'**
  String get grantStatusConsumed;

  /// Grant scope label — full vault access
  ///
  /// In en, this message translates to:
  /// **'All entries'**
  String get grantScopeFull;

  /// Grant scope label — granular single-entry access
  ///
  /// In en, this message translates to:
  /// **'Single entry'**
  String get grantScopeGranular;

  /// Approvals screen segment — pending approval inbox
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get approvalSegmentPending;

  /// Approvals screen segment — org-wide grant history
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get approvalSegmentHistory;

  /// Search placeholder on the Approvals history segment
  ///
  /// In en, this message translates to:
  /// **'Search grants…'**
  String get approvalHistorySearchHint;

  /// Empty state title for the Approvals history feed
  ///
  /// In en, this message translates to:
  /// **'No grants yet'**
  String get approvalHistoryEmpty;

  /// Empty state hint for the Approvals history feed
  ///
  /// In en, this message translates to:
  /// **'Granted, expired and revoked access will appear here.'**
  String get approvalHistoryEmptyHint;

  /// Clears the status filter on the Approvals history feed
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get approvalHistoryFilterClear;

  /// Subtitle under the agent name on a pending-approval card
  ///
  /// In en, this message translates to:
  /// **'requests access'**
  String get approvalPendingRequestsAccess;

  /// Pending card row label — when the request was made
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get approvalPendingRowRequested;

  /// Org grant card row label — target vault (FULL grant)
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get orgGrantRowVault;

  /// Org grant card row label — target entry (granular grant)
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get orgGrantRowEntry;

  /// Org grant card row label — actor who last acted on the grant
  ///
  /// In en, this message translates to:
  /// **'By'**
  String get orgGrantRowActor;

  /// Org grant card row label — access policy summary
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get orgGrantRowAccess;

  /// Org grant card row label — permitted methods
  ///
  /// In en, this message translates to:
  /// **'Methods'**
  String get orgGrantRowMethods;

  /// Org grant card row label — agent's access request reason
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get orgGrantRowReason;

  /// Org grant card row label — owner's deny reason
  ///
  /// In en, this message translates to:
  /// **'Deny reason'**
  String get orgGrantRowDenyReason;

  /// Org grant card row label — owner's revoke reason
  ///
  /// In en, this message translates to:
  /// **'Revoke reason'**
  String get orgGrantRowRevokeReason;

  /// Fallback actor name when no user acted (e.g. automatic expiry)
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get orgGrantActorSystem;

  /// Access summary — no usage or time limit
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get orgGrantUnlimited;

  /// Access summary — remaining query uses for a use-limited grant
  ///
  /// In en, this message translates to:
  /// **'{left} of {limit} uses left'**
  String orgGrantUsesLeft(int left, int limit);

  /// Access summary — absolute expiry date for a time-limited grant
  ///
  /// In en, this message translates to:
  /// **'Until {date}'**
  String orgGrantExpiresOn(String date);

  /// Footer on a terminal grant whose agent already holds active coverage
  ///
  /// In en, this message translates to:
  /// **'Already active'**
  String get orgGrantAlreadyActive;

  /// Title of the grant detail screen
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get grantDetailTitle;

  /// Detail field label — grant scope
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get grantDetailScope;

  /// Detail field label — target entry
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get grantDetailEntry;

  /// Detail field label — expiry / use limit
  ///
  /// In en, this message translates to:
  /// **'Expiry'**
  String get grantDetailExpiry;

  /// Detail section label — agent-supplied reason
  ///
  /// In en, this message translates to:
  /// **'Agent\'s reason'**
  String get grantDetailReason;

  /// Detail field label — request timestamp
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get grantDetailRequested;

  /// Detail field label — approval timestamp
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get grantDetailApproved;

  /// Approval timestamp with approver name
  ///
  /// In en, this message translates to:
  /// **'{date} by {name}'**
  String grantDetailApprovedBy(String date, String name);

  /// Detail field label — revoke timestamp
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get grantDetailRevoked;

  /// Expiry line — absolute TTL
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String grantDetailExpiresAt(String date);

  /// Expiry line — use-limited grant
  ///
  /// In en, this message translates to:
  /// **'{used} of {limit} uses'**
  String grantDetailUsesLimit(int used, int limit);

  /// Expiry line — unbounded grant
  ///
  /// In en, this message translates to:
  /// **'No expiry'**
  String get grantDetailNoExpiry;

  /// Error — 404 on grants
  ///
  /// In en, this message translates to:
  /// **'This grant no longer exists.'**
  String get grantsErrorNotFound;

  /// Error — 403 on grants
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to manage grants.'**
  String get grantsErrorForbidden;

  /// Error — 400/409 on grants
  ///
  /// In en, this message translates to:
  /// **'The request was rejected. Please check and try again.'**
  String get grantsErrorValidation;

  /// Error — network failure on grants
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check your connection.'**
  String get grantsErrorNetwork;

  /// Error — on-device crypto failure during approval
  ///
  /// In en, this message translates to:
  /// **'Could not securely prepare the credential. Please try again.'**
  String get grantsErrorCrypto;

  /// Error — unexpected failure on grants
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get grantsErrorUnknown;

  /// Title of the cross-vault pending-grant approval inbox
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get approvalInboxTitle;

  /// Empty-state title on the approval inbox
  ///
  /// In en, this message translates to:
  /// **'Nothing to approve'**
  String get approvalInboxEmpty;

  /// Empty-state hint on the approval inbox
  ///
  /// In en, this message translates to:
  /// **'When an agent requests access to a credential, the request shows up here for you to approve or deny.'**
  String get approvalInboxEmptyHint;

  /// Retry button on the approval inbox error state
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get approvalRetry;

  /// One-line summary on a pending-grant card
  ///
  /// In en, this message translates to:
  /// **'Wants {entry} in {vault}'**
  String approvalCardRequest(String entry, String vault);

  /// Title of the approve/deny screen for a single grant
  ///
  /// In en, this message translates to:
  /// **'Review request'**
  String get approvalScreenTitle;

  /// Label for the requested entry in the approval summary
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get approvalSummaryEntry;

  /// Label for the vault in the approval summary
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get approvalSummaryVault;

  /// Label for the agent-supplied reason in the approval summary
  ///
  /// In en, this message translates to:
  /// **'Agent\'s reason'**
  String get approvalSummaryReason;

  /// Fallback display name for an agent without a name
  ///
  /// In en, this message translates to:
  /// **'Unnamed agent'**
  String get approvalUnnamedAgent;

  /// Fallback when the requested entry label is missing
  ///
  /// In en, this message translates to:
  /// **'this credential'**
  String get approvalEntryUnknown;

  /// Fallback when the vault name is missing
  ///
  /// In en, this message translates to:
  /// **'a vault'**
  String get approvalVaultUnknown;

  /// Section title for the XOR expiry/use-count limit picker
  ///
  /// In en, this message translates to:
  /// **'Access limit'**
  String get approvalLimitSectionTitle;

  /// Hint under the access-limit section title
  ///
  /// In en, this message translates to:
  /// **'Choose how long this access lasts — by time or by number of uses.'**
  String get approvalLimitSectionHint;

  /// Segmented toggle option — time-to-live limit
  ///
  /// In en, this message translates to:
  /// **'Expires after'**
  String get approvalLimitExpiry;

  /// Segmented toggle option — use-count limit
  ///
  /// In en, this message translates to:
  /// **'Number of uses'**
  String get approvalLimitUses;

  /// Text field label for the maximum number of uses
  ///
  /// In en, this message translates to:
  /// **'Max uses'**
  String get approvalLimitUsesLabel;

  /// Approve button label
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approvalApprove;

  /// Section title for the deny action
  ///
  /// In en, this message translates to:
  /// **'Deny instead'**
  String get approvalDenySectionTitle;

  /// Label for the optional deny reason field
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get approvalDenyReasonLabel;

  /// Hint for the optional deny reason field
  ///
  /// In en, this message translates to:
  /// **'Why are you denying this request?'**
  String get approvalDenyReasonHint;

  /// Deny button label
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get approvalDeny;

  /// Cancel button on approval sheets
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get approvalCancel;

  /// Title of the approve bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Approve request'**
  String get approvalApproveTitle;

  /// Approve subtitle fragment — leading verb before the agent name
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get approvalApproveSubGrant;

  /// Approve subtitle fragment — between agent and entry
  ///
  /// In en, this message translates to:
  /// **'access to'**
  String get approvalApproveSubAccessTo;

  /// Approve subtitle fragment — between entry and vault
  ///
  /// In en, this message translates to:
  /// **'in'**
  String get approvalApproveSubIn;

  /// Label above the access policy selector
  ///
  /// In en, this message translates to:
  /// **'Access type'**
  String get approvalAccessType;

  /// Label above the grant methods selector
  ///
  /// In en, this message translates to:
  /// **'How the agent may use it'**
  String get approvalMethodsLegend;

  /// Title of the amber warning box shown when the plaintext get method is selected
  ///
  /// In en, this message translates to:
  /// **'Warning Zone'**
  String get approvalMethodWarningZone;

  /// Error when no method is selected on approve
  ///
  /// In en, this message translates to:
  /// **'Select at least one method.'**
  String get approvalMethodNoneSelected;

  /// Label for the get method
  ///
  /// In en, this message translates to:
  /// **'Get (plaintext)'**
  String get approvalMethodGetLabel;

  /// Warning shown for the get method
  ///
  /// In en, this message translates to:
  /// **'The secret enters the agent\'s context — on a hosted LLM it may leave the device.'**
  String get approvalMethodGetWarning;

  /// Label for the exec method
  ///
  /// In en, this message translates to:
  /// **'Exec'**
  String get approvalMethodExecLabel;

  /// Label for the inject method
  ///
  /// In en, this message translates to:
  /// **'Inject'**
  String get approvalMethodInjectLabel;

  /// Approve button label while submitting
  ///
  /// In en, this message translates to:
  /// **'Approving…'**
  String get approvalApproving;

  /// Access policy option — time-limited (TTL)
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get approvalPolicyTime;

  /// Access policy option — use-count limited
  ///
  /// In en, this message translates to:
  /// **'Uses'**
  String get approvalPolicyUses;

  /// Access policy option — unlimited / until revoked
  ///
  /// In en, this message translates to:
  /// **'Lifetime'**
  String get approvalPolicyLifetime;

  /// Hint shown when the lifetime access policy is selected
  ///
  /// In en, this message translates to:
  /// **'The agent keeps access until you revoke it.'**
  String get approvalLifetimeHint;

  /// Label for the expiry date picker field
  ///
  /// In en, this message translates to:
  /// **'Expires on'**
  String get approvalExpiresOnLabel;

  /// Quick-pick minutes chip label
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String approvalQuickMinutes(int count);

  /// Quick-pick hours chip label
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String approvalQuickHours(int count);

  /// Chip that opens the custom date/time picker
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get approvalQuickCustom;

  /// Relative expiry (minutes) in the approve summary
  ///
  /// In en, this message translates to:
  /// **'Expires in {count}m'**
  String approvalExpiresInMinutes(int count);

  /// Relative expiry (hours) in the approve summary
  ///
  /// In en, this message translates to:
  /// **'Expires in {count}h'**
  String approvalExpiresInHours(int count);

  /// Relative expiry (days) in the approve summary
  ///
  /// In en, this message translates to:
  /// **'Expires in {count}d'**
  String approvalExpiresInDays(int count);

  /// Relative expiry (months) in the approve summary
  ///
  /// In en, this message translates to:
  /// **'Expires in {count}mo'**
  String approvalExpiresInMonths(int count);

  /// Shown when the chosen expiry is in the past
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get approvalExpiredAlready;

  /// Title of the deny bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Deny {name}?'**
  String approvalDenyTitle(String name);

  /// Body text of the deny bottom sheet
  ///
  /// In en, this message translates to:
  /// **'The agent won\'t get access to this entry.'**
  String get approvalDenyText;

  /// Deny button label while submitting
  ///
  /// In en, this message translates to:
  /// **'Denying…'**
  String get approvalDenying;

  /// Title of the re-grant (grant again) bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Grant again'**
  String get approvalRegrantTitle;

  /// Re-grant button label
  ///
  /// In en, this message translates to:
  /// **'Grant again'**
  String get approvalRegrant;

  /// Re-grant button label while submitting
  ///
  /// In en, this message translates to:
  /// **'Granting…'**
  String get approvalRegranting;

  /// Error — 404 on approval
  ///
  /// In en, this message translates to:
  /// **'This request no longer exists.'**
  String get approvalErrorNotFound;

  /// Error — 403 on approval
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to manage grants.'**
  String get approvalErrorForbidden;

  /// Error — 400/409 on approval
  ///
  /// In en, this message translates to:
  /// **'The request was rejected. Please check and try again.'**
  String get approvalErrorValidation;

  /// Error — network failure on approval
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check your connection.'**
  String get approvalErrorNetwork;

  /// Error — on-device crypto failure producing the envelope
  ///
  /// In en, this message translates to:
  /// **'Could not securely prepare the credential. Please try again.'**
  String get approvalErrorCrypto;

  /// Error — vault locked, no in-memory key to produce the envelope
  ///
  /// In en, this message translates to:
  /// **'Unlock your vault first to approve this request.'**
  String get approvalErrorVaultLocked;

  /// Error — unexpected failure on approval
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get approvalErrorUnknown;

  /// No description provided for @grantAccessTitleAgent.
  ///
  /// In en, this message translates to:
  /// **'Add agent'**
  String get grantAccessTitleAgent;

  /// No description provided for @grantAccessTitleVault.
  ///
  /// In en, this message translates to:
  /// **'Grant access'**
  String get grantAccessTitleVault;

  /// No description provided for @grantAccessPickAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get grantAccessPickAgent;

  /// No description provided for @grantAccessPickVault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get grantAccessPickVault;

  /// No description provided for @grantAccessNoAgents.
  ///
  /// In en, this message translates to:
  /// **'No active agents to grant'**
  String get grantAccessNoAgents;

  /// No description provided for @grantAccessNoVaults.
  ///
  /// In en, this message translates to:
  /// **'No vaults available'**
  String get grantAccessNoVaults;

  /// No description provided for @grantAccessSelectAgent.
  ///
  /// In en, this message translates to:
  /// **'Select an agent'**
  String get grantAccessSelectAgent;

  /// No description provided for @grantAccessSelectVault.
  ///
  /// In en, this message translates to:
  /// **'Select a vault'**
  String get grantAccessSelectVault;

  /// No description provided for @grantAccessConfirm.
  ///
  /// In en, this message translates to:
  /// **'Grant access'**
  String get grantAccessConfirm;

  /// No description provided for @grantAccessGranting.
  ///
  /// In en, this message translates to:
  /// **'Granting…'**
  String get grantAccessGranting;

  /// No description provided for @grantAccessError.
  ///
  /// In en, this message translates to:
  /// **'Could not create the grant. Please try again.'**
  String get grantAccessError;

  /// No description provided for @grantAddGrant.
  ///
  /// In en, this message translates to:
  /// **'Add grant'**
  String get grantAddGrant;

  /// No description provided for @approvalMethodGetDesc.
  ///
  /// In en, this message translates to:
  /// **'Returns the secret as plaintext to the agent.'**
  String get approvalMethodGetDesc;

  /// No description provided for @approvalMethodExecDesc.
  ///
  /// In en, this message translates to:
  /// **'Runs a command with the secret in its environment — never enters the agent\'s context.'**
  String get approvalMethodExecDesc;

  /// No description provided for @approvalMethodInjectDesc.
  ///
  /// In en, this message translates to:
  /// **'Fills a login form in the agent\'s browser — never enters the agent\'s context.'**
  String get approvalMethodInjectDesc;

  /// No description provided for @approvalMethodsSelect.
  ///
  /// In en, this message translates to:
  /// **'Select methods'**
  String get approvalMethodsSelect;

  /// No description provided for @approvalMethodsDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get approvalMethodsDone;

  /// No description provided for @approvalMethodRequested.
  ///
  /// In en, this message translates to:
  /// **'requested'**
  String get approvalMethodRequested;

  /// No description provided for @inboxTitle.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get inboxTitle;

  /// No description provided for @inboxSegAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get inboxSegAll;

  /// No description provided for @inboxTodo.
  ///
  /// In en, this message translates to:
  /// **'To-do'**
  String get inboxTodo;

  /// No description provided for @inboxHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get inboxHistory;

  /// No description provided for @inboxSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by agent, entry or vault…'**
  String get inboxSearchHint;

  /// No description provided for @inboxMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get inboxMarkAllRead;

  /// No description provided for @inboxMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get inboxMoreActions;

  /// No description provided for @inboxGrantsMenu.
  ///
  /// In en, this message translates to:
  /// **'Grants'**
  String get inboxGrantsMenu;

  /// No description provided for @inboxPreferencesMenu.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences'**
  String get inboxPreferencesMenu;

  /// No description provided for @inboxAcceptAction.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get inboxAcceptAction;

  /// No description provided for @inboxViewAgent.
  ///
  /// In en, this message translates to:
  /// **'View Agent'**
  String get inboxViewAgent;

  /// No description provided for @inboxViewAccess.
  ///
  /// In en, this message translates to:
  /// **'View Access'**
  String get inboxViewAccess;

  /// No description provided for @inboxViewEntry.
  ///
  /// In en, this message translates to:
  /// **'View Entry'**
  String get inboxViewEntry;

  /// No description provided for @inboxGrantsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No grants yet'**
  String get inboxGrantsEmpty;

  /// No description provided for @inboxGrantsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Access you grant to your agents will appear here.'**
  String get inboxGrantsEmptyHint;

  /// No description provided for @inboxActionGone.
  ///
  /// In en, this message translates to:
  /// **'This action is no longer available.'**
  String get inboxActionGone;

  /// No description provided for @inboxAllEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your inbox is empty'**
  String get inboxAllEmpty;

  /// No description provided for @inboxAllEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Requests, approvals and other agent activity will appear here.'**
  String get inboxAllEmptyHint;

  /// No description provided for @inboxTodoEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs your attention'**
  String get inboxTodoEmpty;

  /// No description provided for @inboxTodoEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Access requests and other actions from your agents will show up here.'**
  String get inboxTodoEmptyHint;

  /// No description provided for @inboxUpdatesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get inboxUpdatesEmpty;

  /// No description provided for @inboxUpdatesEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Approved, revoked and other resolved items will appear here.'**
  String get inboxUpdatesEmptyHint;

  /// No description provided for @inboxErrorForbidden.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to view notifications.'**
  String get inboxErrorForbidden;

  /// No description provided for @inboxErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check your connection.'**
  String get inboxErrorNetwork;

  /// No description provided for @inboxErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Could not load notifications. Please try again.'**
  String get inboxErrorUnknown;

  /// Fallback for a notification agent name
  ///
  /// In en, this message translates to:
  /// **'An agent'**
  String get notifUnnamedAgent;

  /// Placeholder on agent cards when the agent has no name yet
  ///
  /// In en, this message translates to:
  /// **'Unknown agent'**
  String get notifUnknownAgent;

  /// No description provided for @notifTitleGrantPending.
  ///
  /// In en, this message translates to:
  /// **'Access request'**
  String get notifTitleGrantPending;

  /// No description provided for @notifTitleAgentPending.
  ///
  /// In en, this message translates to:
  /// **'New agent'**
  String get notifTitleAgentPending;

  /// No description provided for @notifTitleAgentApproved.
  ///
  /// In en, this message translates to:
  /// **'Agent approved'**
  String get notifTitleAgentApproved;

  /// No description provided for @notifTitleGrantRevoked.
  ///
  /// In en, this message translates to:
  /// **'Access revoked'**
  String get notifTitleGrantRevoked;

  /// No description provided for @notifTitleGrantApproved.
  ///
  /// In en, this message translates to:
  /// **'Access approved'**
  String get notifTitleGrantApproved;

  /// No description provided for @notifTitleGrantDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get notifTitleGrantDenied;

  /// No description provided for @notifTitleCredentialStale.
  ///
  /// In en, this message translates to:
  /// **'Credential not working'**
  String get notifTitleCredentialStale;

  /// No description provided for @notifSubGrantPending.
  ///
  /// In en, this message translates to:
  /// **'{agent}'**
  String notifSubGrantPending(String agent);

  /// No description provided for @notifSubAgentPending.
  ///
  /// In en, this message translates to:
  /// **'{agent}'**
  String notifSubAgentPending(String agent);

  /// No description provided for @notifSubAgentApproved.
  ///
  /// In en, this message translates to:
  /// **'{agent}'**
  String notifSubAgentApproved(String agent);

  /// No description provided for @notifSubCredentialStale.
  ///
  /// In en, this message translates to:
  /// **'reported by {agent}'**
  String notifSubCredentialStale(String agent);

  /// No description provided for @notifSubGrantUpdate.
  ///
  /// In en, this message translates to:
  /// **'{agent}'**
  String notifSubGrantUpdate(String agent);

  /// No description provided for @notifRowEntry.
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get notifRowEntry;

  /// No description provided for @notifRowMethods.
  ///
  /// In en, this message translates to:
  /// **'Methods'**
  String get notifRowMethods;

  /// No description provided for @notifRowReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get notifRowReason;

  /// No description provided for @notifRowHostIp.
  ///
  /// In en, this message translates to:
  /// **'Host · Ip'**
  String get notifRowHostIp;

  /// No description provided for @notifRowError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get notifRowError;

  /// No description provided for @notifRowAttempts.
  ///
  /// In en, this message translates to:
  /// **'Attempts'**
  String get notifRowAttempts;

  /// No description provided for @notifRowNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get notifRowNote;

  /// No description provided for @notifRowAccess.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get notifRowAccess;

  /// No description provided for @notifRowBy.
  ///
  /// In en, this message translates to:
  /// **'By'**
  String get notifRowBy;

  /// No description provided for @notifRowAgentId.
  ///
  /// In en, this message translates to:
  /// **'Agent Id'**
  String get notifRowAgentId;

  /// No description provided for @notifRowPublicKey.
  ///
  /// In en, this message translates to:
  /// **'Public key'**
  String get notifRowPublicKey;

  /// No description provided for @notifRowType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get notifRowType;

  /// No description provided for @notifAccessUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get notifAccessUnlimited;

  /// No description provided for @notifPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get notifPlaceholder;

  /// No description provided for @notifFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter by type'**
  String get notifFilterTitle;

  /// No description provided for @notifFilterClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get notifFilterClear;

  /// No description provided for @notifPrefsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification settings'**
  String get notifPrefsTitle;

  /// No description provided for @notifPrefsHint.
  ///
  /// In en, this message translates to:
  /// **'Choose how you want to be notified for each type. Some critical types stay on in your inbox.'**
  String get notifPrefsHint;

  /// No description provided for @notifPrefsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No preferences available.'**
  String get notifPrefsEmpty;

  /// No description provided for @notifPrefsSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save your preference. Please try again.'**
  String get notifPrefsSaveError;

  /// No description provided for @notifPrefsMandatory.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get notifPrefsMandatory;

  /// No description provided for @notifPrefsChannelInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get notifPrefsChannelInbox;

  /// No description provided for @notifPrefsChannelRealtime.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get notifPrefsChannelRealtime;

  /// No description provided for @notifPrefsChannelPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get notifPrefsChannelPush;

  /// No description provided for @notifPrefsTypeAgentPending.
  ///
  /// In en, this message translates to:
  /// **'New agent to accept'**
  String get notifPrefsTypeAgentPending;

  /// No description provided for @notifPrefsTypeGrantPending.
  ///
  /// In en, this message translates to:
  /// **'Access requests'**
  String get notifPrefsTypeGrantPending;

  /// No description provided for @notifPrefsTypeGrantRevoked.
  ///
  /// In en, this message translates to:
  /// **'Access revoked'**
  String get notifPrefsTypeGrantRevoked;

  /// No description provided for @notifPrefsTypeGrantApproved.
  ///
  /// In en, this message translates to:
  /// **'Access approved'**
  String get notifPrefsTypeGrantApproved;

  /// No description provided for @notifPrefsTypeGrantDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get notifPrefsTypeGrantDenied;

  /// No description provided for @notifPrefsTypeCredentialStale.
  ///
  /// In en, this message translates to:
  /// **'Credential stale'**
  String get notifPrefsTypeCredentialStale;

  /// No description provided for @auditSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search audit log…'**
  String get auditSearchHint;

  /// No description provided for @auditLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get auditLoadMore;

  /// No description provided for @auditLoadMoreError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load more logs.'**
  String get auditLoadMoreError;

  /// No description provided for @auditEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get auditEmptyTitle;

  /// No description provided for @auditEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Access and grant events for this entry will appear here.'**
  String get auditEmptyHint;

  /// No description provided for @auditEmptyFilteredTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching events'**
  String get auditEmptyFilteredTitle;

  /// No description provided for @auditEmptyFilteredHint.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your filters or search.'**
  String get auditEmptyFilteredHint;

  /// No description provided for @auditFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter logs'**
  String get auditFilterTitle;

  /// No description provided for @auditFilterEventTypes.
  ///
  /// In en, this message translates to:
  /// **'Event types'**
  String get auditFilterEventTypes;

  /// No description provided for @auditFilterAllEventTypes.
  ///
  /// In en, this message translates to:
  /// **'All event types'**
  String get auditFilterAllEventTypes;

  /// No description provided for @auditFilterAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get auditFilterAgent;

  /// No description provided for @auditFilterAllAgents.
  ///
  /// In en, this message translates to:
  /// **'All agents'**
  String get auditFilterAllAgents;

  /// No description provided for @multiSelectNSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String multiSelectNSelected(int count);

  /// No description provided for @multiSelectSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get multiSelectSearchHint;

  /// No description provided for @multiSelectNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get multiSelectNoResults;

  /// No description provided for @auditFilterDateRange.
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get auditFilterDateRange;

  /// No description provided for @auditFilterFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get auditFilterFrom;

  /// No description provided for @auditFilterTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get auditFilterTo;

  /// No description provided for @auditFilterReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get auditFilterReset;

  /// No description provided for @auditFilterApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get auditFilterApply;

  /// No description provided for @auditDetailEntry.
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get auditDetailEntry;

  /// No description provided for @auditDetailReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get auditDetailReason;

  /// No description provided for @auditDetailNone.
  ///
  /// In en, this message translates to:
  /// **'No additional details.'**
  String get auditDetailNone;

  /// No description provided for @auditActorOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get auditActorOwner;

  /// No description provided for @auditActorSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get auditActorSystem;

  /// No description provided for @auditActorAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get auditActorAgent;

  /// No description provided for @auditErrorForbidden.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to view audit logs.'**
  String get auditErrorForbidden;

  /// No description provided for @auditErrorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Audit logs are unavailable for this vault.'**
  String get auditErrorNotFound;

  /// No description provided for @auditErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error. Check your connection and try again.'**
  String get auditErrorNetwork;

  /// No description provided for @auditErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the audit log. Please try again.'**
  String get auditErrorGeneric;

  /// No description provided for @auditEventGrantCreated.
  ///
  /// In en, this message translates to:
  /// **'Access granted'**
  String get auditEventGrantCreated;

  /// No description provided for @auditEventGrantRequested.
  ///
  /// In en, this message translates to:
  /// **'Access requested'**
  String get auditEventGrantRequested;

  /// No description provided for @auditEventGrantApproved.
  ///
  /// In en, this message translates to:
  /// **'Access approved'**
  String get auditEventGrantApproved;

  /// No description provided for @auditEventGrantDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get auditEventGrantDenied;

  /// No description provided for @auditEventGrantRevoked.
  ///
  /// In en, this message translates to:
  /// **'Access revoked'**
  String get auditEventGrantRevoked;

  /// No description provided for @auditEventGrantConsumed.
  ///
  /// In en, this message translates to:
  /// **'Grant consumed'**
  String get auditEventGrantConsumed;

  /// No description provided for @auditEventGrantExpired.
  ///
  /// In en, this message translates to:
  /// **'Grant expired'**
  String get auditEventGrantExpired;

  /// No description provided for @auditEventCredentialAccessed.
  ///
  /// In en, this message translates to:
  /// **'Credential accessed'**
  String get auditEventCredentialAccessed;

  /// No description provided for @auditEventCredentialAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get auditEventCredentialAccessDenied;

  /// No description provided for @auditEventAgentEnrolled.
  ///
  /// In en, this message translates to:
  /// **'Agent enrolled'**
  String get auditEventAgentEnrolled;

  /// No description provided for @auditEventAgentBlocked.
  ///
  /// In en, this message translates to:
  /// **'Agent blocked'**
  String get auditEventAgentBlocked;

  /// No description provided for @auditEventAgentReactivated.
  ///
  /// In en, this message translates to:
  /// **'Agent reactivated'**
  String get auditEventAgentReactivated;

  /// No description provided for @auditEventAgentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Agent deleted'**
  String get auditEventAgentDeleted;

  /// No description provided for @auditEventVaultCreated.
  ///
  /// In en, this message translates to:
  /// **'Vault created'**
  String get auditEventVaultCreated;

  /// No description provided for @auditEventVaultUpdated.
  ///
  /// In en, this message translates to:
  /// **'Vault updated'**
  String get auditEventVaultUpdated;

  /// No description provided for @auditEventVaultDeleted.
  ///
  /// In en, this message translates to:
  /// **'Vault deleted'**
  String get auditEventVaultDeleted;

  /// No description provided for @auditEventEntryCreated.
  ///
  /// In en, this message translates to:
  /// **'Entry created'**
  String get auditEventEntryCreated;

  /// No description provided for @auditEventEntryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Entry updated'**
  String get auditEventEntryUpdated;

  /// No description provided for @auditEventEntryDeleted.
  ///
  /// In en, this message translates to:
  /// **'Entry deleted'**
  String get auditEventEntryDeleted;

  /// No description provided for @auditEventApiKeyCreated.
  ///
  /// In en, this message translates to:
  /// **'API key created'**
  String get auditEventApiKeyCreated;

  /// No description provided for @auditEventApiKeyActivated.
  ///
  /// In en, this message translates to:
  /// **'API key activated'**
  String get auditEventApiKeyActivated;

  /// No description provided for @auditEventApiKeyRevoked.
  ///
  /// In en, this message translates to:
  /// **'API key revoked'**
  String get auditEventApiKeyRevoked;

  /// No description provided for @auditEventApiKeyDeleted.
  ///
  /// In en, this message translates to:
  /// **'API key deleted'**
  String get auditEventApiKeyDeleted;

  /// No description provided for @auditEventOrgCreated.
  ///
  /// In en, this message translates to:
  /// **'Organization created'**
  String get auditEventOrgCreated;

  /// No description provided for @auditEventOrgUpdated.
  ///
  /// In en, this message translates to:
  /// **'Organization updated'**
  String get auditEventOrgUpdated;

  /// No description provided for @auditEventUserSignedUp.
  ///
  /// In en, this message translates to:
  /// **'User signed up'**
  String get auditEventUserSignedUp;

  /// No description provided for @auditEventAccountSetupCompleted.
  ///
  /// In en, this message translates to:
  /// **'Account setup completed'**
  String get auditEventAccountSetupCompleted;

  /// No description provided for @auditEventAccountRecoveryCompleted.
  ///
  /// In en, this message translates to:
  /// **'Account recovery completed'**
  String get auditEventAccountRecoveryCompleted;

  /// No description provided for @auditEventUnknown.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get auditEventUnknown;

  /// Title of the org-wide audit Logs screen
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get auditScreenTitle;

  /// No description provided for @auditFilterVault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get auditFilterVault;

  /// No description provided for @auditFilterAllVaults.
  ///
  /// In en, this message translates to:
  /// **'All vaults'**
  String get auditFilterAllVaults;

  /// No description provided for @auditFilterUser.
  ///
  /// In en, this message translates to:
  /// **'Performed by'**
  String get auditFilterUser;

  /// No description provided for @auditFilterAllUsers.
  ///
  /// In en, this message translates to:
  /// **'Anyone'**
  String get auditFilterAllUsers;

  /// No description provided for @auditUserUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown user'**
  String get auditUserUnknown;

  /// No description provided for @auditUserUnknownShort.
  ///
  /// In en, this message translates to:
  /// **'Unknown user ({id})'**
  String auditUserUnknownShort(String id);

  /// No description provided for @auditGroupCredentialAccess.
  ///
  /// In en, this message translates to:
  /// **'Accessed'**
  String get auditGroupCredentialAccess;

  /// No description provided for @auditGroupGrants.
  ///
  /// In en, this message translates to:
  /// **'Grants'**
  String get auditGroupGrants;

  /// No description provided for @auditGroupVaultEntry.
  ///
  /// In en, this message translates to:
  /// **'Vault & entries'**
  String get auditGroupVaultEntry;

  /// No description provided for @auditGroupAgentLifecycle.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get auditGroupAgentLifecycle;

  /// No description provided for @auditGroupApiKeys.
  ///
  /// In en, this message translates to:
  /// **'API keys'**
  String get auditGroupApiKeys;

  /// No description provided for @auditGroupOrgAccount.
  ///
  /// In en, this message translates to:
  /// **'Org & account'**
  String get auditGroupOrgAccount;

  /// No description provided for @auditLegendTitle.
  ///
  /// In en, this message translates to:
  /// **'Event legend'**
  String get auditLegendTitle;

  /// No description provided for @auditLegendSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What the colours on each log entry mean.'**
  String get auditLegendSubtitle;

  /// No description provided for @auditSentenceCreated.
  ///
  /// In en, this message translates to:
  /// **'{actor} created {object}'**
  String auditSentenceCreated(String actor, String object);

  /// No description provided for @auditSentenceUpdated.
  ///
  /// In en, this message translates to:
  /// **'{actor} updated {object}'**
  String auditSentenceUpdated(String actor, String object);

  /// No description provided for @auditSentenceDeleted.
  ///
  /// In en, this message translates to:
  /// **'{actor} deleted {object}'**
  String auditSentenceDeleted(String actor, String object);

  /// No description provided for @auditSentenceActivated.
  ///
  /// In en, this message translates to:
  /// **'{actor} activated {object}'**
  String auditSentenceActivated(String actor, String object);

  /// No description provided for @auditSentenceRevoked.
  ///
  /// In en, this message translates to:
  /// **'{actor} revoked {object}'**
  String auditSentenceRevoked(String actor, String object);

  /// No description provided for @auditSentenceBlocked.
  ///
  /// In en, this message translates to:
  /// **'{actor} blocked {object}'**
  String auditSentenceBlocked(String actor, String object);

  /// No description provided for @auditSentenceReactivated.
  ///
  /// In en, this message translates to:
  /// **'{actor} reactivated {object}'**
  String auditSentenceReactivated(String actor, String object);

  /// No description provided for @auditSentenceUserSignedUp.
  ///
  /// In en, this message translates to:
  /// **'{actor} signed up'**
  String auditSentenceUserSignedUp(String actor);

  /// No description provided for @auditSentenceAccountSetupCompleted.
  ///
  /// In en, this message translates to:
  /// **'{actor} completed account setup'**
  String auditSentenceAccountSetupCompleted(String actor);

  /// No description provided for @auditSentenceAccountRecoveryCompleted.
  ///
  /// In en, this message translates to:
  /// **'{actor} completed account recovery'**
  String auditSentenceAccountRecoveryCompleted(String actor);

  /// No description provided for @auditSentenceAgentEnrolled.
  ///
  /// In en, this message translates to:
  /// **'{agent} enrolled in the system'**
  String auditSentenceAgentEnrolled(String agent);

  /// No description provided for @auditObjectVaultNamed.
  ///
  /// In en, this message translates to:
  /// **'vault {name}'**
  String auditObjectVaultNamed(String name);

  /// No description provided for @auditObjectEntryNamed.
  ///
  /// In en, this message translates to:
  /// **'entry {name}'**
  String auditObjectEntryNamed(String name);

  /// No description provided for @auditObjectOrgNamed.
  ///
  /// In en, this message translates to:
  /// **'organization {name}'**
  String auditObjectOrgNamed(String name);

  /// No description provided for @auditObjectApiKeyNamed.
  ///
  /// In en, this message translates to:
  /// **'API key {name}'**
  String auditObjectApiKeyNamed(String name);

  /// No description provided for @auditObjectAgentNamed.
  ///
  /// In en, this message translates to:
  /// **'agent {name}'**
  String auditObjectAgentNamed(String name);

  /// No description provided for @auditObjectVault.
  ///
  /// In en, this message translates to:
  /// **'a vault'**
  String get auditObjectVault;

  /// No description provided for @auditObjectEntry.
  ///
  /// In en, this message translates to:
  /// **'an entry'**
  String get auditObjectEntry;

  /// No description provided for @auditObjectOrg.
  ///
  /// In en, this message translates to:
  /// **'the organization'**
  String get auditObjectOrg;

  /// No description provided for @auditObjectApiKey.
  ///
  /// In en, this message translates to:
  /// **'an API key'**
  String get auditObjectApiKey;

  /// No description provided for @auditObjectAgent.
  ///
  /// In en, this message translates to:
  /// **'an agent'**
  String get auditObjectAgent;

  /// Greeting on the dashboard
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get dashboardGoodMorning;

  /// Search placeholder on dashboard
  ///
  /// In en, this message translates to:
  /// **'Agents, vaults, entries…'**
  String get dashboardSearchHint;

  /// Localized name for the default vault auto-created during onboarding
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get defaultVaultName;

  /// Title of the onboarding progress card
  ///
  /// In en, this message translates to:
  /// **'Set up Palladin'**
  String get dashboardOnboardingTitle;

  /// Subtitle of the onboarding progress card
  ///
  /// In en, this message translates to:
  /// **'Complete these steps to start managing access securely'**
  String get dashboardOnboardingSubtitle;

  /// Progress counter in the onboarding card
  ///
  /// In en, this message translates to:
  /// **'{completed} of 4 completed'**
  String dashboardOnboardingProgress(int completed);

  /// Link to dismiss the onboarding checklist
  ///
  /// In en, this message translates to:
  /// **'Skip setup'**
  String get dashboardOnboardingSkipSetup;

  /// Step 1 title
  ///
  /// In en, this message translates to:
  /// **'Enable notifications'**
  String get dashboardOnboardingStep1Title;

  /// Step 1 description
  ///
  /// In en, this message translates to:
  /// **'Respond in seconds — agents wait for your approval. Faster responses mean smoother AI workflows.'**
  String get dashboardOnboardingStep1Description;

  /// Enable notifications button
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get dashboardOnboardingStep1Enable;

  /// Skip notifications step button
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get dashboardOnboardingStep1Skip;

  /// Button shown instead of Enable when the OS notification permission was denied — opens system app settings
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get dashboardOnboardingStep1OpenSettings;

  /// Step 2 title — prompts user to add a password entry or import
  ///
  /// In en, this message translates to:
  /// **'Add your first entry or import passwords'**
  String get dashboardOnboardingStep2Title;

  /// Step 2 description
  ///
  /// In en, this message translates to:
  /// **'Your Personal vault is ready — add a password entry manually or import your existing credentials.'**
  String get dashboardOnboardingStep2Description;

  /// Step 2 CTA button — navigates to vault list so user can add first entry
  ///
  /// In en, this message translates to:
  /// **'Go to Vaults'**
  String get dashboardOnboardingStep2Cta;

  /// Step 3 title
  ///
  /// In en, this message translates to:
  /// **'Add an API Key'**
  String get dashboardOnboardingStep3Title;

  /// Step 3 description
  ///
  /// In en, this message translates to:
  /// **'Connect Palladin to external services'**
  String get dashboardOnboardingStep3Description;

  /// Step 3 CTA button
  ///
  /// In en, this message translates to:
  /// **'Add API Key'**
  String get dashboardOnboardingStep3Cta;

  /// Step 4 title
  ///
  /// In en, this message translates to:
  /// **'Register an Agent'**
  String get dashboardOnboardingStep4Title;

  /// Step 4 description
  ///
  /// In en, this message translates to:
  /// **'Add your first AI agent that can request access'**
  String get dashboardOnboardingStep4Description;

  /// Step 4 CTA button
  ///
  /// In en, this message translates to:
  /// **'Register Agent'**
  String get dashboardOnboardingStep4Cta;

  /// Step number badge
  ///
  /// In en, this message translates to:
  /// **'Step {n}'**
  String dashboardOnboardingStep(int n);

  /// Warning label on the unknown agent card
  ///
  /// In en, this message translates to:
  /// **'Unregistered agent'**
  String get dashboardUnknownAgentWarning;

  /// Unknown agent card description
  ///
  /// In en, this message translates to:
  /// **'This agent is not yet in the system. You can register it and approve access at the same time.'**
  String get dashboardUnknownAgentDescription;

  /// Register & Approve button label
  ///
  /// In en, this message translates to:
  /// **'Register & Approve'**
  String get dashboardUnknownAgentRegisterAndApprove;

  /// Reject button label on unknown agent card
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get dashboardUnknownAgentReject;

  /// Pending approvals section header
  ///
  /// In en, this message translates to:
  /// **'Pending Approvals'**
  String get dashboardPendingApprovals;

  /// Recent activity section header
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get dashboardRecentActivity;

  /// Empty state message for activity section
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get dashboardNoActivity;

  /// Section header for recently added or updated entries on the dashboard
  ///
  /// In en, this message translates to:
  /// **'Recently added / modified'**
  String get dashboardRecentlyModified;

  /// See all link in section headers
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get dashboardSeeAll;

  /// Empty state shown in search results
  ///
  /// In en, this message translates to:
  /// **'No results for this search'**
  String get searchResultsEmpty;

  /// Error state for search results
  ///
  /// In en, this message translates to:
  /// **'Search failed. Please try again.'**
  String get searchResultsError;

  /// Type badge label for agent search results
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get searchTypeBadgeAgent;

  /// Type badge label for vault search results
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get searchTypeBadgeVault;

  /// Type badge label for entry search results
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get searchTypeBadgeEntry;
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
