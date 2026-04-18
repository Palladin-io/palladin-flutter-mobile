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
}
