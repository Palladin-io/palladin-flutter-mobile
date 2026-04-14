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
