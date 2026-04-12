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
}
