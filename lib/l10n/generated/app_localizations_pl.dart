// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appTitle => 'Claw Vault';

  @override
  String get welcomeMessage => 'Witaj w Claw Vault';

  @override
  String get taglineZeroKnowledge => 'Zero-Knowledge';

  @override
  String get taglinePasswordManager => 'Menedżer haseł';

  @override
  String get taglineForAiAgents => 'Dla agentów AI';

  @override
  String get continueWithGoogle => 'Kontynuuj z Google';

  @override
  String get continueWithApple => 'Kontynuuj z Apple';

  @override
  String get continueWithX => 'Kontynuuj z X';

  @override
  String get legalFooter =>
      'Kontynuując, akceptujesz nasze Warunki i Politykę prywatności';

  @override
  String providerComingSoon(String provider) {
    return 'Logowanie przez $provider już wkrótce';
  }

  @override
  String get errorServerNotResponding =>
      'Serwer nie odpowiada. Spróbuj ponownie.';

  @override
  String get errorCannotConnectToServer =>
      'Nie można połączyć się z serwerem. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get errorConnectionFailed => 'Błąd połączenia. Spróbuj ponownie.';

  @override
  String get errorInvalidServerResponse =>
      'Nieprawidłowa odpowiedź serwera. Spróbuj ponownie.';

  @override
  String get onboardingMasterPasswordTitle => 'Ustaw hasło główne';

  @override
  String get onboardingMasterPasswordSubtitle =>
      'To hasło lokalnie szyfruje Twój sejf. Nigdy go nie widzimy.';

  @override
  String get onboardingMasterPasswordLabel => 'Hasło główne';

  @override
  String get onboardingConfirmPasswordLabel => 'Potwierdź hasło';

  @override
  String get onboardingPasswordRequirementsTitle => 'Wymagania';

  @override
  String get onboardingPasswordReqLength => 'Co najmniej 12 znaków';

  @override
  String get onboardingPasswordReqCase => 'Wielkie i małe litery';

  @override
  String get onboardingPasswordReqNumber => 'Co najmniej jedna cyfra';

  @override
  String get onboardingPasswordReqSymbol => 'Co najmniej jeden symbol';

  @override
  String get onboardingPasswordStrengthTooShort => 'Zbyt krótkie';

  @override
  String get onboardingPasswordStrengthWeak => 'Słabe hasło';

  @override
  String get onboardingPasswordStrengthFair => 'Przeciętne hasło';

  @override
  String get onboardingPasswordStrengthStrong => 'Silne hasło';

  @override
  String get onboardingPasswordStrengthVeryStrong => 'Bardzo silne hasło';

  @override
  String get onboardingPasswordsMatch => 'Hasła są zgodne';

  @override
  String get onboardingPasswordsDoNotMatch => 'Hasła są różne';

  @override
  String get onboardingContinue => 'Dalej';

  @override
  String get onboardingRecoveryTitle => 'Zapisz klucz odzyskiwania';

  @override
  String get onboardingRecoverySubtitle =>
      'Zapisz go i przechowaj bezpiecznie offline. Bez niego zapomnienie hasła głównego oznacza bezpowrotną utratę danych.';

  @override
  String get onboardingRecoveryWarning =>
      'Bez tego klucza nie odzyskasz swojego sejfu.';

  @override
  String get onboardingRecoveryCopy => 'Skopiuj do schowka';

  @override
  String get onboardingRecoveryCopied =>
      'Klucz odzyskiwania skopiowany do schowka';

  @override
  String get onboardingRecoveryShare => 'Udostępnij klucz';

  @override
  String get onboardingRecoverySaved => 'Zapisałem klucz odzyskiwania';

  @override
  String get onboardingConfirmTitle => 'Potwierdź klucz odzyskiwania';

  @override
  String get onboardingConfirmSubtitle =>
      'Wpisz poniższe słowa z klucza odzyskiwania, aby potwierdzić, że go zapisałeś.';

  @override
  String onboardingConfirmWordLabel(int index) {
    return 'Słowo #$index';
  }

  @override
  String onboardingConfirmWordHint(int index) {
    return 'Wpisz słowo #$index';
  }

  @override
  String get onboardingConfirmCorrect => 'Zgadza się';

  @override
  String get onboardingConfirmIncorrect => 'Niepoprawnie';

  @override
  String get onboardingConfirmVerify => 'Zweryfikuj i zakończ konfigurację';

  @override
  String get onboardingAlreadyCompleted =>
      'To konto zostało już skonfigurowane. Zaloguj się ponownie.';
}
