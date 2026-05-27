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
  String get onboardingRecoveryExport => 'Eksportuj jako plik (.txt)';

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

  @override
  String get unlockTitle => 'Wpisz hasło główne';

  @override
  String get unlockPasswordLabel => 'Hasło główne';

  @override
  String get unlockButton => 'Odblokuj';

  @override
  String get unlockForgotPassword => 'Zapomniałeś hasła?';

  @override
  String get unlockForgotPasswordComingSoon => 'Odzyskiwanie hasła już wkrótce';

  @override
  String get unlockWrongPassword =>
      'Nieprawidłowe hasło główne. Spróbuj ponownie.';

  @override
  String get unlockBiometricHint => 'Odblokuj biometrycznie';

  @override
  String get unlockBiometricPrompt => 'Uwierzytelnij się, aby odblokować sejf';

  @override
  String get unlockBiometricUnavailable =>
      'Odblokowanie biometryczne nie jest jeszcze skonfigurowane. Wpisz hasło główne.';

  @override
  String get unlockBiometricFailed =>
      'Uwierzytelnianie biometryczne nie powiodło się. Spróbuj ponownie lub użyj hasła.';

  @override
  String get unlockLockVault => 'Zablokuj sejf';

  @override
  String get recoveryTitle => 'Odzyskaj swoje konto';

  @override
  String get recoverySubtitle =>
      'Wprowadź swój 24-słowny klucz odzyskiwania. Użyjemy go lokalnie, aby odszyfrować sejf — nic nie trafia na nasze serwery w postaci jawnej.';

  @override
  String get recoveryEnterKeyLabel =>
      'Wpisz lub wklej 24 słowa klucza, oddzielone spacjami';

  @override
  String get recoveryPasteButton => 'Wklej ze schowka';

  @override
  String get recoveryShareSubject => 'Klucz odzyskiwania Claw Vault';

  @override
  String get recoveryImportButton => 'Importuj z pliku .txt';

  @override
  String get recoveryImportComingSoon =>
      'Import z pliku już wkrótce — skorzystaj na razie ze schowka';

  @override
  String get recoveryNewPasswordTitle => 'Ustaw nowe hasło główne';

  @override
  String get recoveryNewPasswordSubtitle =>
      'Wybierz nowe hasło główne. Zastąpi ono hasło, które zapomniałeś.';

  @override
  String get recoveryNewPasswordLabel => 'Nowe hasło główne';

  @override
  String get recoveryConfirmPasswordLabel => 'Potwierdź nowe hasło';

  @override
  String get recoveryRecoverButton => 'Odzyskaj konto';

  @override
  String get recoverySaveKeyTitle => 'Zapisz nowy klucz odzyskiwania';

  @override
  String get recoverySaveKeyCheckbox =>
      'Zapisałem nowy klucz odzyskiwania w bezpiecznym miejscu';

  @override
  String get recoveryFinishButton => 'Zakończ';

  @override
  String get recoveryCopyButton => 'Skopiuj do schowka';

  @override
  String get recoveryWrongKey =>
      'Ten klucz odzyskiwania nie pasuje do naszych danych. Sprawdź dokładnie 24 słowa i spróbuj ponownie.';

  @override
  String get recoveryPasswordMismatch => 'Hasła są różne';

  @override
  String get recoveryMaterialMissing =>
      'Tego konta nie można odzyskać — klucz odzyskiwania nie został ustawiony. Skontaktuj się z pomocą techniczną.';

  @override
  String get recoveryServerError =>
      'Odzyskiwanie nie powiodło się. Spróbuj ponownie.';

  @override
  String get vaultTitle => 'Sejfy';

  @override
  String get vaultNewVault => 'Nowy sejf';

  @override
  String get vaultNoVaults => 'Brak sejfów';

  @override
  String get vaultCreateFirst =>
      'Utwórz pierwszy sejf, aby uporządkować dane logowania i zarządzać dostępem agentów AI.';

  @override
  String get vaultRetry => 'Spróbuj ponownie';

  @override
  String get vaultCancel => 'Anuluj';

  @override
  String get vaultModeFull => 'Pełny';

  @override
  String get vaultModeGranular => 'Szczegółowy';

  @override
  String get vaultModeFullDescription =>
      'Jedna zgoda daje dostęp do wszystkich wpisów.';

  @override
  String get vaultModeGranularDescription => 'Każdy wpis wymaga osobnej zgody.';

  @override
  String get vaultModeLabel => 'Tryb dostępu';

  @override
  String get vaultNameLabel => 'Nazwa sejfu';

  @override
  String get vaultDescriptionLabel => 'Opis';

  @override
  String get vaultIconLabel => 'Ikona';

  @override
  String get vaultColorLabel => 'Kolor';

  @override
  String get vaultCreating => 'Tworzenie...';

  @override
  String get vaultSaving => 'Zapisywanie...';

  @override
  String get vaultSavedSnackbar => 'Sejf zaktualizowany';

  @override
  String get vaultDeleteTitle => 'Usunąć sejf?';

  @override
  String vaultDeleteConfirmWithName(String name) {
    return 'Sejf „$name” oraz wszystkie jego wpisy zostaną trwale usunięte. Tej operacji nie można cofnąć.';
  }

  @override
  String get vaultSettings => 'Ustawienia sejfu';

  @override
  String get vaultSaveChanges => 'Zapisz zmiany';

  @override
  String get vaultDangerZone => 'STREFA NIEBEZPIECZNA';

  @override
  String get vaultDangerZoneSubtitle =>
      'Usunięcie sejfu jest nieodwracalne — wpisy oraz aktywne zgody zostaną usunięte.';

  @override
  String get vaultDeleteVault => 'Usuń sejf';

  @override
  String vaultEntryCount(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString wpisów',
      many: '$countString wpisów',
      few: '$countString wpisy',
      one: '1 wpis',
      zero: 'Brak wpisów',
    );
    return '$_temp0';
  }

  @override
  String vaultUpdatedAt(String date) {
    return 'Aktualizacja $date';
  }

  @override
  String get vaultUpdatedNow => 'teraz';

  @override
  String vaultUpdatedMinutesAgo(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString min temu',
      many: '$countString min temu',
      few: '$countString min temu',
      one: '1 min temu',
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
      other: '$countString godz. temu',
      many: '$countString godz. temu',
      few: '$countString godz. temu',
      one: '1 godz. temu',
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
      other: '$countString dni temu',
      many: '$countString dni temu',
      few: '$countString dni temu',
      one: '1 dzień temu',
    );
    return '$_temp0';
  }

  @override
  String get vaultStatEntries => 'Wpisy';

  @override
  String get vaultStatActiveGrants => 'Aktywne zgody';

  @override
  String get vaultStatMembers => 'Członkowie';

  @override
  String get vaultSectionEntries => 'Wpisy';

  @override
  String get vaultSectionAgents => 'Agenci';

  @override
  String get vaultEntriesPlaceholderTitle => 'Wpisy już wkrótce';

  @override
  String get vaultEntriesPlaceholderSubtitle =>
      'Na razie dodawaj i zarządzaj danymi z panelu webowego — zarządzanie wpisami w aplikacji mobilnej pojawi się w kolejnej fazie.';

  @override
  String get vaultAgentsPlaceholderTitle => 'Agenci już wkrótce';

  @override
  String get vaultAgentsPlaceholderSubtitle =>
      'Zgody dla agentów akceptujesz z ekranu głównego — zarządzanie agentami w obrębie sejfu jest w planach.';

  @override
  String get vaultErrorNotFound => 'Ten sejf już nie istnieje.';

  @override
  String get vaultErrorForbidden => 'Brak uprawnień do wykonania tej operacji.';

  @override
  String get vaultErrorPlanLimitReached =>
      'Osiągnięto limit sejfów w Twoim planie. Ulepsz plan, aby utworzyć więcej.';

  @override
  String get vaultErrorFullModeNotAllowed =>
      'Twój plan nie pozwala na sejfy w trybie pełnym. Wybierz tryb szczegółowy lub ulepsz plan.';

  @override
  String get vaultErrorUnknown => 'Coś poszło nie tak. Spróbuj ponownie.';

  @override
  String vaultGrantCount(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString zgód',
      many: '$countString zgód',
      few: '$countString zgody',
      one: '1 zgoda',
      zero: 'Brak zgód',
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
      other: '$countString aktywnych zgód',
      many: '$countString aktywnych zgód',
      few: '$countString aktywne zgody',
      one: '1 aktywna zgoda',
      zero: 'Brak aktywnych zgód',
    );
    return '$_temp0';
  }

  @override
  String get vaultTabEntries => 'Wpisy';

  @override
  String get vaultTabAgents => 'Agenci';

  @override
  String get vaultTabLogs => 'Logi';

  @override
  String get vaultTabMembers => 'Członkowie';

  @override
  String get vaultTabSettings => 'Ustawienia';

  @override
  String get vaultSearchEntries => 'Szukaj wpisów…';

  @override
  String get vaultSearchAgents => 'Szukaj agentów…';

  @override
  String get vaultGrantFull => 'Pełny dostęp';

  @override
  String get vaultGrantGranular => 'Szczegółowy';

  @override
  String get vaultGrantActive => 'aktywna';

  @override
  String get vaultGrantExpired => 'wygasła';

  @override
  String get vaultGrantRevoked => 'cofnięta';

  @override
  String vaultGrantGrantedBy(String person, String date) {
    return 'Przyznane przez $person – $date';
  }

  @override
  String vaultGrantRevokedBy(String person, String date) {
    return 'Cofnięte przez $person – $date';
  }

  @override
  String vaultGrantMoreEntries(int count) {
    return '+$count więcej';
  }

  @override
  String get vaultRevokeButton => 'Cofnij';

  @override
  String get vaultRegrantButton => 'Przywróć';

  @override
  String get vaultRestoreButton => 'Wznów';

  @override
  String get vaultEntriesEmpty => 'Brak wpisów';

  @override
  String get vaultAgentsEmpty => 'Żaden agent nie ma jeszcze dostępu';

  @override
  String get vaultLogsEmpty => 'Dziennik aktywności już wkrótce';

  @override
  String get vaultMembersEmpty => 'Zarządzanie członkami już wkrótce';

  @override
  String get vaultRevealEntry => 'Pokaż dane wpisu';

  @override
  String get vaultViewEntry => 'Zobacz szczegóły wpisu';

  @override
  String get vaultCopyValue => 'Kopiuj';

  @override
  String get vaultOpenLink => 'Otwórz w przeglądarce';

  @override
  String get vaultRevealValue => 'Pokaż wartość';

  @override
  String get vaultSaveAction => 'Zapisz';

  @override
  String get vaultAddEntryFab => 'Dodaj wpis';

  @override
  String get vaultAddGrantFab => 'Dodaj zgodę';

  @override
  String get vaultIconUpload => 'Wgraj własną ikonę';

  @override
  String get vaultIconUploadError =>
      'Przesyłanie nie powiodło się. Spróbuj ponownie.';

  @override
  String get vaultIconUploadSizeError => 'Plik przekracza limit 2 MB.';

  @override
  String get vaultIconUploadFormatError =>
      'Nieobsługiwany format. Użyj PNG, JPEG lub WebP.';

  @override
  String get vaultUpgradeToPro => 'Przejdź na Pro';

  @override
  String get vaultUpgradeComingSoon =>
      'Płatności są w drodze — w planie Basic możesz mieć tylko jeden sejf.';

  @override
  String get navHome => 'Start';

  @override
  String get navVaults => 'Sejfy';

  @override
  String get navAgents => 'Agenci';

  @override
  String get navAudit => 'Logi';

  @override
  String get navSettings => 'Ustawienia';

  @override
  String get vaultListTitle => 'Twoje sejfy';

  @override
  String vaultListSummary(int vaultCount, int entryCount) {
    String _temp0 = intl.Intl.pluralLogic(
      vaultCount,
      locale: localeName,
      other: '$vaultCount sejfów',
      many: '$vaultCount sejfów',
      few: '$vaultCount sejfy',
      one: '1 sejf',
    );
    String _temp1 = intl.Intl.pluralLogic(
      entryCount,
      locale: localeName,
      other: '$entryCount wpisów',
      many: '$entryCount wpisów',
      few: '$entryCount wpisy',
      one: '1 wpis',
      zero: 'brak wpisów',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get vaultSearchHint => 'Szukaj sejfów…';

  @override
  String get vaultSearchEmpty => 'Żaden sejf nie pasuje do wyszukiwania';

  @override
  String get settingsAccountTitle => 'Konto';

  @override
  String get settingsLockVault => 'Zablokuj sejf';

  @override
  String get settingsLogout => 'Wyloguj się';

  @override
  String settingsAppVersion(String version) {
    return 'Wersja $version';
  }

  @override
  String get settingsTooltip => 'Otwórz ustawienia';

  @override
  String get premiumGateTitle => 'Odblokuj nielimitowaną liczbę sejfów';

  @override
  String get premiumGateSubtitle =>
      'Osiągnięto limit 1 sejfu w planie darmowym.';

  @override
  String get premiumGateCta => 'Przejdź na Pro';

  @override
  String get premiumGateDismiss => 'Może później';

  @override
  String get settingsThemeToggle => 'Tryb ciemny';

  @override
  String get settingsLanguage => 'Język';

  @override
  String get settingsPlanPro => 'Pro';

  @override
  String get settingsPlanFree => 'Darmowy';

  @override
  String get settingsDefaultDisplayName => 'Użytkownik';

  @override
  String get placeholderComingSoon => 'Już wkrótce';

  @override
  String get placeholderAuditTitle => 'Dziennik audytu';

  @override
  String get entryAddTitle => 'Dodaj wpis';

  @override
  String get entryDetailTitle => 'Szczegóły wpisu';

  @override
  String get entryTabDetails => 'Szczegóły';

  @override
  String get entryRevealingForEdit => 'Ładowanie danych wpisu…';

  @override
  String get entryDangerZone => 'Strefa niebezpieczna';

  @override
  String get entryDeleteTitle => 'Usunąć wpis?';

  @override
  String get entryDeleteConfirm =>
      'Wpis zostanie trwale usunięty wraz z zaszyfrowanymi danymi. Tej operacji nie można cofnąć.';

  @override
  String get entryDeleteAction => 'Usuń wpis';

  @override
  String get entryDeleting => 'Usuwanie…';

  @override
  String get entryTypeLabel => 'Typ wpisu';

  @override
  String get entryTypeKey => 'Klucz';

  @override
  String get entryTypeCredential => 'Login';

  @override
  String get entryLabelLabel => 'Etykieta';

  @override
  String get entryLabelHint => 'np. Stripe API Key';

  @override
  String get entryDescriptionLabel => 'Opis';

  @override
  String get entryValueLabel => 'Wartość';

  @override
  String get entryUsernameLabel => 'Nazwa użytkownika';

  @override
  String get entryPasswordLabel => 'Hasło';

  @override
  String get entryUrlLabel => 'URL';

  @override
  String get entryUrlInvalid =>
      'Podaj prawidłowy URL (np. stripe.com lub https://stripe.com)';

  @override
  String get entryNotesLabel => 'Notatki';

  @override
  String get entryEncryptionNotice =>
      'Szyfrowane na urządzeniu (XSalsa20-Poly1305) przed wysłaniem';

  @override
  String get entrySearchHint => 'Szukaj wpisów…';

  @override
  String get entryEmpty => 'Brak wpisów';

  @override
  String get entryEmptyAdd => 'Dodaj pierwsze dane, aby zacząć.';

  @override
  String get entrySaveAction => 'Zapisz';

  @override
  String get entrySaving => 'Zapisywanie…';

  @override
  String get entryErrorNotFound => 'Ten wpis już nie istnieje.';

  @override
  String get entryErrorForbidden => 'Brak uprawnień do wykonania tej operacji.';

  @override
  String get entryErrorValidation =>
      'Niektóre pola są nieprawidłowe. Sprawdź formularz i spróbuj ponownie.';

  @override
  String get entryErrorCrypto =>
      'Nie udało się odszyfrować wpisu. Zablokuj i odblokuj sejf, a następnie spróbuj ponownie.';

  @override
  String get entryErrorUnknown => 'Coś poszło nie tak. Spróbuj ponownie.';

  @override
  String get settingsScreenTitle => 'Ustawienia';

  @override
  String get settingsOrganization => 'Organizacja';

  @override
  String get settingsManageOrganization => 'Organizacja';

  @override
  String get settingsOrgNameLabel => 'Nazwa organizacji';

  @override
  String get settingsOrgNameHint => 'Podaj nazwę organizacji';

  @override
  String settingsOrgMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count członka',
      many: '$count członków',
      few: '$count członkowie',
      one: '1 członek',
    );
    return '$_temp0';
  }

  @override
  String get settingsSave => 'Zapisz';

  @override
  String get settingsOrgSaved => 'Zaktualizowano nazwę organizacji.';

  @override
  String get settingsApiKeys => 'Klucze API';

  @override
  String get settingsRetry => 'Ponów';

  @override
  String get settingsErrorNotFound => 'Nie udało się znaleźć tego zasobu.';

  @override
  String get settingsErrorForbidden =>
      'Brak uprawnień do wykonania tej operacji.';

  @override
  String get settingsErrorValidation => 'Sprawdź formularz i spróbuj ponownie.';

  @override
  String get settingsErrorUnknown => 'Coś poszło nie tak. Spróbuj ponownie.';

  @override
  String get apiKeysScreenTitle => 'Klucze API';

  @override
  String get apiKeysEmpty => 'Brak kluczy API';

  @override
  String get apiKeysEmptyHint =>
      'Wygeneruj klucz, aby podłączyć pierwszego agenta.';

  @override
  String get apiKeysStatusActive => 'Aktywny';

  @override
  String get apiKeysStatusRevoked => 'Unieważniony';

  @override
  String get apiKeysRetry => 'Ponów';

  @override
  String get apiKeysGenerate => 'Wygeneruj klucz API';

  @override
  String get apiKeysGenerateAction => 'Wygeneruj';

  @override
  String get apiKeysGenerating => 'Generowanie…';

  @override
  String get apiKeysNameLabel => 'Nazwa klucza';

  @override
  String get apiKeysNameHint => 'np. Agent produkcyjny';

  @override
  String get apiKeysSecretTitle => 'Klucz API utworzony';

  @override
  String get apiKeysSecretWarning =>
      'Zapisz ten klucz teraz — nie zostanie pokazany ponownie.';

  @override
  String get apiKeysCopyKey => 'Kopiuj klucz';

  @override
  String get apiKeysKeyCopied => 'Skopiowano klucz API do schowka.';

  @override
  String get apiKeysDone => 'Gotowe';

  @override
  String get apiKeysCancel => 'Anuluj';

  @override
  String get apiKeysRevoke => 'Unieważnij';

  @override
  String get apiKeysRevokeConfirmTitle => 'Unieważnić klucz API?';

  @override
  String apiKeysRevokeConfirmBody(String name) {
    return 'Agenci korzystający z „$name” natychmiast stracą dostęp. Tej operacji nie można cofnąć.';
  }

  @override
  String get apiKeysDetailTitle => 'Klucz API';

  @override
  String get apiKeysDetailNotFound => 'Ten klucz API już nie istnieje.';

  @override
  String get apiKeysTabDetails => 'Szczegóły';

  @override
  String get apiKeysTabAgents => 'Agenci';

  @override
  String get apiKeysDetailKey => 'Klucz';

  @override
  String get apiKeysDetailCreatedAt => 'Utworzono';

  @override
  String get apiKeysDetailRevokedAt => 'Unieważniono';

  @override
  String get apiKeysActivate => 'Aktywuj';

  @override
  String get apiKeysActivating => 'Aktywowanie…';

  @override
  String get apiKeysDeletePermanently => 'Usuń trwale';

  @override
  String get apiKeysDeleting => 'Usuwanie…';

  @override
  String get apiKeysDeleteConfirmTitle => 'Usuń klucz API?';

  @override
  String apiKeysDeleteConfirmBody(String name) {
    return 'Klucz \"$name\" zostanie trwale usunięty. Nie można cofnąć tej operacji.';
  }

  @override
  String get apiKeysActivateZone => 'AKTYWUJ KLUCZ';

  @override
  String get apiKeysActivateHint =>
      'Ponownie włącz ten klucz — agenci używający go odzyskają dostęp natychmiast.';

  @override
  String apiKeysListSummary(int total, int active) {
    return '$total kluczy · $active aktywnych';
  }

  @override
  String get agentsScreenTitle => 'Agenci';

  @override
  String agentsListSummary(int total, int active) {
    return '$total agentów, $active aktywnych';
  }

  @override
  String get agentsEmpty => 'Brak agentów';

  @override
  String get agentsEmptyHint =>
      'Podłącz pierwszego agenta za pomocą CLI, aby zacząć';

  @override
  String get agentsUnnamed => 'Agent bez nazwy';

  @override
  String get agentsSplitPrompt => 'Wybierz agenta, aby zobaczyć szczegóły';

  @override
  String get agentsStatusActive => 'Aktywny';

  @override
  String get agentsStatusPending => 'Oczekuje';

  @override
  String get agentsStatusDeactivated => 'Dezaktywowany';

  @override
  String get agentsEnrolled => 'Zatwierdzono';

  @override
  String get agentsDeactivated => 'Dezaktywowano';

  @override
  String get agentsPendingApproval => 'Oczekuje na zatwierdzenie';

  @override
  String get agentsDetailTitle => 'Agent';

  @override
  String get agentsDetailNotFound => 'Nie znaleziono agenta';

  @override
  String get agentsDetailPublicKey => 'Klucz publiczny';

  @override
  String get agentsDetailCreatedAt => 'Połączono';

  @override
  String get agentsDetailEnrolledAt => 'Zatwierdzono';

  @override
  String get agentsDetailEnrolledBy => 'Zatwierdził';

  @override
  String get agentsDetailDeactivatedAt => 'Dezaktywowano';

  @override
  String get agentsApproveZone => 'ZATWIERDŹ AGENTA';

  @override
  String get agentsApproveHint =>
      'Przyznaj temu agentowi dostęp do organizacji';

  @override
  String get agentsApprove => 'Zatwierdź agenta';

  @override
  String get agentsApproving => 'Zatwierdzanie…';

  @override
  String get agentsDeactivateZone => 'STREFA NIEBEZPIECZNA';

  @override
  String get agentsDeactivateHint =>
      'Agent natychmiast utraci dostęp do wszystkich sejfów';

  @override
  String get agentsDeactivate => 'Dezaktywuj agenta';

  @override
  String get agentsDeactivating => 'Dezaktywowanie…';

  @override
  String get agentsReactivateZone => 'REAKTYWACJA';

  @override
  String get agentsReactivateHint => 'Ponownie włącz dostęp dla tego agenta';

  @override
  String get agentsReactivate => 'Reaktywuj agenta';

  @override
  String get agentsReactivating => 'Reaktywowanie…';

  @override
  String get agentsApproveConfirmTitle => 'Zatwierdź agenta';

  @override
  String agentsApproveConfirmBody(String name) {
    return 'Zezwolić agentowi „$name” na dostęp do sejfów organizacji?';
  }

  @override
  String get agentsDeactivateConfirmTitle => 'Dezaktywuj agenta';

  @override
  String agentsDeactivateConfirmBody(String name) {
    return 'Dezaktywować agenta „$name”? Natychmiast utraci dostęp.';
  }

  @override
  String get agentsEditTitle => 'Edytuj agenta';

  @override
  String get agentsEditName => 'Nazwa wyświetlana';

  @override
  String get agentsEditDescription => 'Opis';

  @override
  String get agentsEditSave => 'Zapisz';

  @override
  String get agentsRetry => 'Ponów';

  @override
  String get agentsEditIcon => 'Edytuj';

  @override
  String get agentApproveTitle => 'Zatwierdź agenta';

  @override
  String get agentNameLabel => 'Nazwa (opcjonalna)';

  @override
  String get agentTypeLabel => 'Typ agenta';

  @override
  String get agentIconLabel => 'Ikona';

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
  String get agentTypeOther => 'Inne';

  @override
  String get agentApproveSetupHint =>
      'Opcjonalnie ustaw nazwę, typ i ikonę przed aktywacją.';

  @override
  String get agentNamePlaceholder => 'np. Claude Code, Cursor';

  @override
  String get agentsTabDetails => 'Szczegóły';

  @override
  String get agentsTabGrants => 'Dostępy';

  @override
  String get agentsTabLogs => 'Historia';

  @override
  String get agentsGrantsEmpty => 'Brak aktywnych dostępów';

  @override
  String get agentsGrantsEmptyHint =>
      'Ten agent nie ma jeszcze żadnych przyznanych wpisów';

  @override
  String get agentsLogsFirstConnected => 'Pierwsze połączenie';

  @override
  String get agentsLogsEnrolled => 'Zatwierdzono';

  @override
  String get agentsLogsDeactivated => 'Dezaktywowano';

  @override
  String get agentsEditSaved => 'Zmiany zapisane';

  @override
  String get agentTypePlaceholder => 'Wybierz lub wpisz własny typ';

  @override
  String get agentIconMore => 'Więcej ikon';

  @override
  String get agentIconBrowserTitle => 'Przeglądaj ikony';

  @override
  String get agentIconColorLabel => 'Kolor';

  @override
  String get agentIconChoose => 'Wybierz';
}
