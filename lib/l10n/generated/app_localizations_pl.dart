// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get sharingAccountNotice =>
      'Odbiór nie wymaga konta. Aby zapisać kopię, przejdź przez swoje konto i wróć tutaj. Tymczasowa sesja zachowuje pierwotny termin ważności; jej zamknięcie lub wylogowanie usuwa kopię.';

  @override
  String get sharingRegister => 'Załóż konto, aby zapisać kopię';

  @override
  String get sharingLogin => 'Zaloguj się, aby zapisać kopię';

  @override
  String get sharingContinueAccount =>
      'Dokończ konfigurację lub odblokuj konto';

  @override
  String get sharingSaveCopy => 'Zapisz kopię';

  @override
  String get sharingCopyCorruptVaults =>
      'Niektórych sejfów nie udało się odszyfrować i nie można ich wybrać. Pozostałe sejfy są dostępne.';

  @override
  String get sharingCopySaved =>
      'Kopia zapisana w Twoim sejfie. Nie będzie synchronizowana z oryginałem.';

  @override
  String get sharingCopyNotice =>
      'Zapisz odebrane pola jako nowy wpis. Nie odbierzesz linku ponownie ani nie zmienisz oryginału.';

  @override
  String get sharingCopyVault => 'Sejf docelowy';

  @override
  String get sharingCopyChooseVault => 'Wybierz sejf';

  @override
  String get sharingCopyVaultError =>
      'Nie udało się wczytać sejfów. Spróbuj ponownie, nie zamykając sesji udostępniania.';

  @override
  String get sharingCopyNoVault =>
      'To konto nie ma dostępnego sejfu docelowego.';

  @override
  String get sharingCopyAccessTitle => 'Dostęp w sejfie docelowym';

  @override
  String get sharingCopyAccessNotice =>
      'Obecni członkowie i w pełni zaufani Agenci tego sejfu mogą mieć dostęp do kopii. Uprawnienia źródła nie są kopiowane; wykrywanie wpisu i dostęp Agentów do poszczególnych pól są początkowo wyłączone.';

  @override
  String get sharingCopyTitleError =>
      'Podaj nazwę od 1 do 200 znaków. Odebrana nazwa nigdy nie jest skracana automatycznie.';

  @override
  String get sharingCopyMissingNotice =>
      'Nadawca pominął pola wymagane przy zapisie wpisu. Uzupełnij je tutaj; odebrane wartości pozostaną bez zmian.';

  @override
  String get sharingCopyRequired => 'Uzupełnij wymagane pole.';

  @override
  String get sharingCopyScriptDescription => 'Opis wykonania Twojej kopii';

  @override
  String get sharingCopyScriptError =>
      'Podaj skrypt, obsługiwany interpreter (bash, sh, node lub python) i opis wykonania do 4096 znaków.';

  @override
  String get sharingCopyUnsupported =>
      'Ta kopia zawiera dane, których ta wersja nie zapisze bez zmian. Nic nie zapisano.';

  @override
  String get sharingCopySaveError =>
      'Nie udało się przygotować kopii do zapisu. Sprawdź połączenie i dostęp do sejfu, a następnie ponów próbę.';

  @override
  String get sharingCopyRetryNotice =>
      'Wynik zapisu nie jest jeszcze potwierdzony. Ponowienie wyśle ten sam zaszyfrowany wpis, nie duplikat. Nie rozpoczynaj nowego zapisu tej kopii.';

  @override
  String get sharingCopyBack => 'Wróć do odebranego wpisu';

  @override
  String get sharingCopySessionNotice =>
      'Opuszczenie tej sesji, blokada lub przejście do innej aplikacji usuwa kopię z pamięci. Nie cofnie to zapisu już przyjętego przez serwer.';

  @override
  String get sharingEndConfirm => 'Zakończ link';

  @override
  String get sharingReceiveTitle => 'Udostępniony wpis';

  @override
  String get sharingClose => 'Zamknij udostępnienie';

  @override
  String get sharingReceiveUnavailable =>
      'Ten link udostępnienia jest niedostępny. Otwórz ponownie oryginalny link, jeśli nadal jest ważny.';

  @override
  String get sharingReceiveWelcome =>
      'Odbierz kopię wpisu bez zakładania konta. Otwarcie weryfikacji nie zużywa limitu. Samodzielnie wybierasz moment odbioru.';

  @override
  String get sharingOpen => 'Otwórz udostępnienie';

  @override
  String get sharingReceive => 'Odbierz wpis';

  @override
  String get sharingReceiveError =>
      'Nie udało się wykonać tej czynności. Sprawdź kod lub hasło, jeśli są wymagane, i spróbuj ponownie. Link mógł wygasnąć lub zostać zakończony.';

  @override
  String get sharingOtpNotice =>
      'Wyślij kod na adres e-mail wskazany przez nadawcę. Konto Palladin nie jest wymagane.';

  @override
  String get sharingSendOtp => 'Wyślij kod e-mail';

  @override
  String get sharingResendOtp => 'Wyślij nowy kod';

  @override
  String get sharingRetryOtp => 'Ponów wysyłkę kodu';

  @override
  String get sharingOtpCode => 'Kod e-mail';

  @override
  String get sharingOtpFormatError => 'Wpisz sześciocyfrowy kod e-mail.';

  @override
  String get sharingVerifyOtp => 'Potwierdź kod e-mail';

  @override
  String get sharingVerifySecret => 'Potwierdź';

  @override
  String get sharingReadyToReceive =>
      'Weryfikacja zakończona. Odbiór wpisu zużywa jeden odbiór z limitu; ponowienie tej samej operacji nie zużywa kolejnego.';

  @override
  String get sharingReceivedNotice =>
      'To niezależna kopia. Zmiany oryginału jej nie aktualizują. Zakończenie linku nie odbiera już pobranych kopii i nie zmienia hasła w innym serwisie.';

  @override
  String get sharingCopyValue => 'Kopiuj wartość';

  @override
  String get sharingCopiedValue =>
      'Skopiowano. Schowek zostanie wyczyszczony po 45 sekundach, jeśli jego zawartość się nie zmieni.';

  @override
  String get sharingConfirmationFailed =>
      'Wpis jest dostępny, ale nie udało się wysłać potwierdzenia wyświetlenia. Ponowienie potwierdzenia nie pobiera wpisu ponownie.';

  @override
  String get sharingRetryConfirmation => 'Ponów potwierdzenie';

  @override
  String get sharingEnd => 'Zakończ udostępnianie';

  @override
  String get sharingEndNotice =>
      'Zakończyć ten link dla wszystkich uprawnionych odbiorców? Tej czynności nie można cofnąć. Nie usuwa ona oryginalnego wpisu ani zapisanych kopii.';

  @override
  String get sharingEnded =>
      'Udostępnianie zakończone. Ten link nie pozwala już odebrać wpisu.';

  @override
  String get sharingUnsupportedGate =>
      'Ten link używa weryfikacji nieobsługiwanej przez tę wersję aplikacji. Zaktualizuj aplikację lub poproś nadawcę o inny link.';

  @override
  String get sharingCreate => 'Utwórz link';

  @override
  String get sharingSelectFields => 'Wybierz pola do udostępnienia';

  @override
  String get sharingSelectNotice =>
      'Skopiowane zostaną tylko wybrane pola. Notatki, kody odzyskiwania i dane konfiguracji 2FA wymagają Twojego jawnego wyboru.';

  @override
  String get sharingPreviewConfirmed => 'Sprawdziłem wybrane pola';

  @override
  String get sharingUnsupportedField =>
      'Tej wartości nie można udostępnić w tej wersji aplikacji.';

  @override
  String get sharingRecipient => 'Kto może odebrać tę kopię?';

  @override
  String get sharingNamedRecipient => 'Tylko ta osoba (kod e-mail)';

  @override
  String get sharingEmail => 'E-mail odbiorcy';

  @override
  String get sharingEmailNotice =>
      'Samodzielnie przekaż skopiowany link. Palladin wysyła e-mailem tylko kod weryfikacji, nie link. Dla każdej osoby utwórz osobny link.';

  @override
  String get sharingAnyoneTitle => 'Każdy, kto ma link';

  @override
  String get sharingAnyoneWarning =>
      'Link można przekazać dalej. Limit odbiorów jest wspólny dla jego posiadaczy; każdy uprawniony odbiorca może zakończyć go dla wszystkich.';

  @override
  String get sharingSecretNotice =>
      'Przekaż hasło lub PIN osobnym kanałem. Możesz połączyć je z kodem e-mail.';

  @override
  String get sharingPinWarning =>
      'PIN jest słabszy od długiego hasła. Użyj co najmniej 6 cyfr; dla mocniejszej ochrony zalecamy hasło.';

  @override
  String get sharingLifetime => 'Ważność linku';

  @override
  String get sharingLifetimeHour => '1 godzina';

  @override
  String get sharingLifetimeDay => '1 dzień';

  @override
  String get sharingLifetimeThreeDays => '3 dni';

  @override
  String get sharingLifetimeWeek => '7 dni';

  @override
  String get sharingMaximumReceipts => 'Limit odbiorów';

  @override
  String get sharingNotifyChoice => 'Powiadom mnie o pierwszym odbiorze';

  @override
  String get sharingNotifyNotice =>
      'Jeden komunikat w Inbox po potwierdzeniu wyświetlenia przez klienta odbiorcy. Audyt działa zawsze; to nie dowód przeczytania przez człowieka.';

  @override
  String get sharingCreateNotice =>
      'To niezależna kopia, nie dostęp do sejfu. Późniejsze zmiany jej nie aktualizują. Odwołanie linku nie usuwa pobranych kopii.';

  @override
  String get sharingCancelNotice =>
      'Jeśli wyjdziesz po wysłaniu żądania, sprawdź listę udostępnień: link mógł powstać mimo utraty odpowiedzi.';

  @override
  String get sharingEmailError => 'Podaj jeden poprawny adres e-mail odbiorcy.';

  @override
  String get sharingPasswordError =>
      'Użyj 8–128 znaków. Spacje są częścią hasła.';

  @override
  String get sharingPinError => 'Użyj 6–128 cyfr (0–9), bez spacji.';

  @override
  String get sharingLimitError => 'Podaj liczbę całkowitą od 1 do 100.';

  @override
  String get sharingLifetimeError =>
      'Wybierz jeden z dostępnych terminów ważności.';

  @override
  String get sharingSelectionError =>
      'Wybierz co najmniej jedno dostępne pole i potwierdź podgląd.';

  @override
  String get sharingCreateError =>
      'Nie udało się utworzyć linku. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get sharingSourceError =>
      'Wpis się zmienił. Otwórz go ponownie i sprawdź pola przed udostępnieniem.';

  @override
  String get sharingSourceLoadError =>
      'Nie udało się otworzyć wpisu do udostępnienia. Spróbuj ponownie po odblokowaniu.';

  @override
  String get sharingRetryNotice =>
      'Wynik jest niepewny. Ponowienie wysyła tę samą zaszyfrowaną kopię i nie tworzy drugiego linku. Do tego czasu opcje pozostają zablokowane.';

  @override
  String get sharingRetryCreate => 'Ponów to samo żądanie';

  @override
  String get sharingCreated => 'Twój link jest gotowy';

  @override
  String get sharingCopyLink => 'Kopiuj link';

  @override
  String get sharingCopiedLink =>
      'Link skopiowany. Schowek wyczyści się po 45 sekundach, jeśli jego zawartość się nie zmieni.';

  @override
  String get sharingCopyError =>
      'Nie udało się skopiować linku. Spróbuj ponownie, pozostając na tym ekranie.';

  @override
  String get sharingLinkOnceNotice =>
      'Skopiuj link przed wyjściem. Palladin nie odzyska później jego klucza odszyfrowania. Nadal możesz odwołać link na liście udostępnień.';

  @override
  String get sharingConfigurationError =>
      'Udostępnianie nie jest skonfigurowane dla tego środowiska aplikacji. Nie utworzono linku.';

  @override
  String get sharingTotpSource => 'Dane konfiguracji 2FA';

  @override
  String get sharingHidePreview => 'Ukryj wartość';

  @override
  String get sharingTab => 'Udostępnienia';

  @override
  String get sharingListNotice =>
      'Linki zawierają niezależne kopie. Wydanie paczki i potwierdzenie wyświetlenia są osobne; żadne nie dowodzi przeczytania wpisu przez człowieka.';

  @override
  String get sharingEmpty => 'Ten wpis nie ma jeszcze linków udostępniania.';

  @override
  String get sharingUnavailable =>
      'Udostępnienia są niedostępne w tej sesji. Otwórz wpis ponownie po odblokowaniu.';

  @override
  String get sharingLoadError => 'Nie udało się wczytać linków udostępniania.';

  @override
  String get sharingRevokeError =>
      'Nie udało się odwołać linku. Sprawdź jego status i spróbuj ponownie.';

  @override
  String get sharingRevoke => 'Odwołaj link';

  @override
  String get sharingRevokeNotice =>
      'To zatrzyma kolejne odbiory przez link. Nie usunie pobranych kopii ani nie zmieni hasła w zewnętrznym serwisie.';

  @override
  String get sharingRevoked => 'Link udostępniania odwołany.';

  @override
  String get sharingRefresh => 'Odśwież';

  @override
  String get sharingAnyone => 'Każdy, kto ma link';

  @override
  String get sharingActive => 'Aktywny';

  @override
  String get sharingRevokedStatus => 'Odwołany';

  @override
  String get sharingExpired => 'Wygasły';

  @override
  String get sharingSuspended => 'Zawieszony';

  @override
  String get sharingLocked => 'Tymczasowo zablokowany';

  @override
  String get sharingConsumed => 'Limit odbiorów wykorzystany';

  @override
  String get sharingProtectionNone => 'Bez dodatkowego sekretu';

  @override
  String get sharingProtectionPassword => 'Hasło';

  @override
  String get sharingProtectionPin => 'PIN';

  @override
  String get sharingValidUntil => 'Link ważny do';

  @override
  String get sharingReceipts => 'Odbiory / limit';

  @override
  String get sharingFirstDelivery => 'Pierwsze wydanie paczki';

  @override
  String get sharingLastDelivery => 'Ostatnie wydanie paczki';

  @override
  String get sharingConfirmation => 'Pierwsze potwierdzenie wyświetlenia';

  @override
  String get sharingProtection => 'Dodatkowe zabezpieczenie';

  @override
  String get sharingNotification => 'Powiadomienie o pierwszym odbiorze';

  @override
  String get sharingNotificationOn => 'Włączone — jeden komunikat w Inbox';

  @override
  String get sharingNotificationOff => 'Wyłączone';

  @override
  String get sharingSourceChangedTitle => 'Źródło zmienione';

  @override
  String get sharingSourceChanged =>
      'Ta kopia nie aktualizuje się po zmianie oryginalnego wpisu. Odwołaj ją, jeśli nie powinna być już dostępna.';

  @override
  String get responseUnknownValue => 'Nieznane';

  @override
  String get appTitle => 'Palladin';

  @override
  String get welcomeMessage => 'Witaj w Palladin';

  @override
  String get loginRotatingZeroKnowledge => 'Zero-knowledge w każdym calu.';

  @override
  String get loginRotatingForAgents => 'Stworzony dla agentów AI.';

  @override
  String get loginRotatingYourKeys => 'Twoje klucze, Twoje zasady.';

  @override
  String get loginRotatingEncrypted => 'Zawsze zaszyfrowane.';

  @override
  String get continueWithGoogle => 'Kontynuuj z Google';

  @override
  String get continueWithApple => 'Kontynuuj z Apple';

  @override
  String get continueWithX => 'Zaloguj się przez X';

  @override
  String get continueWithEmail => 'Kontynuuj przez e-mail';

  @override
  String get authOtherSignInOptions => 'Inne opcje logowania';

  @override
  String get legalFooterPrefix => 'Kontynuując, akceptujesz nasze ';

  @override
  String get legalTermsLink => 'Warunki';

  @override
  String get legalFooterSeparator => ' i ';

  @override
  String get legalPrivacyLink => 'Politykę prywatności';

  @override
  String get legalLinkOpenError => 'Nie można otworzyć tego linku.';

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
  String get unlockSessionExpired => 'Sesja wygasła. Zaloguj się ponownie.';

  @override
  String get unlockBiometricHint => 'Odblokuj biometrycznie';

  @override
  String get unlockBiometricPrompt => 'Uwierzytelnij się, aby odblokować sejf';

  @override
  String get unlockBiometricPromptTitle => 'Odblokuj Palladin';

  @override
  String get unlockBiometricEnrollPrompt =>
      'Potwierdź, aby włączyć odblokowanie biometryczne';

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
  String get recoveryShareSubject => 'Klucz odzyskiwania Palladin';

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
  String get entryAgentsEmptyTitle => 'Brak agentów z dostępem';

  @override
  String get entryAgentsEmptyHint =>
      'Żaden agent nie ma jeszcze dostępu do tego wpisu.';

  @override
  String get vaultAgentsEmptyTitle => 'Brak agentów z dostępem';

  @override
  String get vaultAgentsEmptyHint =>
      'Żaden agent nie ma jeszcze dostępu do tego sejfu.';

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
  String get navApprovals => 'Zatwierdzenia';

  @override
  String get navInbox => 'Inbox';

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
  String get entryRevealDetailsAction => 'Pokaż szczegóły wpisu';

  @override
  String get entryRevealDetailsHint =>
      'Pola wrażliwe są odszyfrowywane dopiero na Twoje żądanie.';

  @override
  String get entryErrorConflict =>
      'Ten wpis zmienił się podczas edycji. Odśwież go i spróbuj ponownie.';

  @override
  String get entryAgentsPolicyTitle => 'Widoczność dla agentów';

  @override
  String get entryAgentsPolicyHint =>
      'Wybierz, co agenci mogą odkryć i co może udostępnić grant związany z dokładną rewizją.';

  @override
  String get entryAgentsDiscoverable => 'Widoczny dla agentów organizacji';

  @override
  String get entryAgentsAgentLabel => 'Etykieta widoczna dla agentów';

  @override
  String get entryAgentsDiscoveryPreview => 'Podgląd Discovery';

  @override
  String get entryAgentsDiscoveryEmpty =>
      'Żadne wartości nie trafią do Discovery.';

  @override
  String get entryAgentsSavePolicy => 'Zapisz politykę widoczności';

  @override
  String get entryAgentsSavingPolicy => 'Zapisywanie polityki…';

  @override
  String get entryAgentsPolicyError =>
      'Nie udało się bezpiecznie wczytać lub zapisać zaszyfrowanej polityki.';

  @override
  String get entryAgentsAccessNever => 'Nigdy';

  @override
  String get entryAgentsAccessDiscovery => 'Discovery';

  @override
  String get entryAgentsAccessGrantValue => 'Grant: wartość';

  @override
  String get entryAgentsAccessGrantDerived => 'Grant: tylko wynik pochodny';

  @override
  String get entryAgentsAccessGrantRuntime =>
      'Grant: tylko środowisko wykonawcze';

  @override
  String get entryChangesSaved => 'Zmiany zostały zapisane';

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
  String get entryTypeCreditCard => 'Karta płatnicza';

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
  String get entryDiscoverUsername =>
      'Pozwól agentom wykrywać nazwę użytkownika';

  @override
  String get entryDiscoverDomain => 'Pozwól agentom wykrywać domenę URL';

  @override
  String get entrySearchHint => 'Szukaj wpisów…';

  @override
  String get entryEmpty => 'Brak wpisów';

  @override
  String get entryEmptyAdd =>
      'Dodaj wpis ręcznie lub zaimportuj dane z innego menedżera haseł.';

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
  String get entryEditAction => 'Edytuj';

  @override
  String get entryShowMore => 'Pokaż więcej';

  @override
  String get entryShowLess => 'Pokaż mniej';

  @override
  String entryCopiedField(String field) {
    return 'Skopiowano $field do schowka';
  }

  @override
  String get entryCopied => 'Skopiowano do schowka';

  @override
  String get entryTypeScript => 'Skrypt';

  @override
  String get entryCustomFieldsLabel => 'Pola niestandardowe';

  @override
  String get entryAddFieldAction => 'Dodaj pole';

  @override
  String get entryFieldNameLabel => 'Nazwa pola';

  @override
  String get entryFieldNameHint => 'np. E-mail odzyskiwania';

  @override
  String get entryFieldValueLabel => 'Wartość';

  @override
  String get entryFieldTypeLabel => 'Typ';

  @override
  String get entryFieldTypeText => 'Tekst';

  @override
  String get entryFieldTypeConcealed => 'Ukryte';

  @override
  String get entryFieldTypeTotp => 'Kod jednorazowy';

  @override
  String get entryFieldRemove => 'Usuń pole';

  @override
  String get entryFieldReorder => 'Przeciągnij, aby zmienić kolejność';

  @override
  String get entryFieldNameRequired => 'Dodaj nazwę tego pola';

  @override
  String get totpSetupTitle => 'Kod jednorazowy';

  @override
  String get totpScanQr => 'Zeskanuj kod QR';

  @override
  String get totpOr => 'lub';

  @override
  String get totpSetupKeyLabel => 'Klucz konfiguracyjny';

  @override
  String get totpSetupKeyHint => 'otpauth://… lub sekret base32';

  @override
  String get totpIssuerLabel => 'Wydawca (opcjonalnie)';

  @override
  String get totpAccountLabel => 'Konto (opcjonalnie)';

  @override
  String get totpInvalidKey =>
      'Podaj prawidłowy klucz otpauth:// lub sekret base32';

  @override
  String get totpScanInstruction =>
      'Skieruj aparat na kod QR z aplikacji uwierzytelniającej';

  @override
  String get totpScannerTitle => 'Zeskanuj kod QR';

  @override
  String get totpCameraDenied =>
      'Dostęp do aparatu jest wyłączony. Włącz go w Ustawieniach lub wklej klucz konfiguracyjny.';

  @override
  String get totpCameraOpenSettings => 'Otwórz ustawienia';

  @override
  String get totpConfigured => 'Kod jednorazowy skonfigurowany';

  @override
  String get totpReplaceSecret => 'Zmień';

  @override
  String get totpCodeCopied => 'Skopiowano kod jednorazowy';

  @override
  String get totpInvalidConfigured => 'Nieprawidłowy sekret kodu';

  @override
  String get entryScriptLabel => 'Skrypt';

  @override
  String get entryScriptHint => '#!/usr/bin/env bash\\n…';

  @override
  String get entryInterpreterLabel => 'Interpreter';

  @override
  String get entryScriptRefsLabel => 'Odwołania do danych';

  @override
  String get entryInjectedDataLabel => 'Wstrzyknięte dane skarbca';

  @override
  String get entryScriptRefsHint =>
      'Przypisz zmienną środowiskową do pola innego wpisu.';

  @override
  String get entryScriptParametersLabel => 'Parametry CLI';

  @override
  String get entryScriptParameterAdd => 'Dodaj parametr';

  @override
  String get entryScriptParameterName => 'Nazwa parametru';

  @override
  String get entryScriptParameterNameHint => 'np. team_id';

  @override
  String get entryScriptParameterDescription => 'Opis';

  @override
  String get entryScriptParameterType => 'Typ';

  @override
  String get entryScriptParameterRequired => 'Wymagany';

  @override
  String get entryScriptParameterRemove => 'Usuń parametr';

  @override
  String get entryScriptParameterTypeString => 'Tekst';

  @override
  String get entryScriptParameterTypeInteger => 'Liczba całkowita';

  @override
  String get entryScriptParameterTypeNumber => 'Liczba';

  @override
  String get entryScriptParameterTypeBoolean => 'Wartość logiczna';

  @override
  String get entryScriptReturnResultLabel => 'Zwróć wynik Agentowi';

  @override
  String get entryScriptReturnResultHint =>
      'Standardowe wyjście skryptu trafi do Agenta lub LLM. Sekrety pozostają wstrzyknięte lokalnie i nie powinny być wypisywane.';

  @override
  String get entryScriptImpactTitle => 'Agenci otrzymają tę zmianę';

  @override
  String entryScriptImpactMessage(int effective, int direct, int full) {
    return 'Ten skrypt jest dostępny dla $effective agentów: $direct bezpośrednio i $full przez dostęp FULL Exec. Zapis odświeży ich pakiet wykonawczy. Nowo wskazane sekrety będą dostępne wyłącznie podczas lokalnego wykonania.';
  }

  @override
  String get entryScriptImpactConfirm => 'Zapisz i odśwież dostęp';

  @override
  String get entryScriptImpactCheckFailed =>
      'Nie udało się sprawdzić, którzy agenci używają tego skryptu. Nic nie zapisano.';

  @override
  String get entryAddRefAction => 'Dodaj odwołanie';

  @override
  String get entryRefEnvLabel => 'Zmienna środowiskowa';

  @override
  String get entryRefEnvHint => 'np. GITHUB_TOKEN';

  @override
  String get entryRefEntryLabel => 'Wpis';

  @override
  String get entryRefFieldLabel => 'Pole';

  @override
  String get entryRefEntryHint => 'Wybierz wpis';

  @override
  String get entryRefRemove => 'Usuń odwołanie';

  @override
  String get entryScriptEmpty => 'Brak skryptu';

  @override
  String get entryRefsEmpty => 'Brak odwołań do danych';

  @override
  String get entryTooLarge =>
      'Ten wpis jest zbyt duży. Skróć skrypt lub usuń część pól.';

  @override
  String get entryScriptExecOnlyTitle => 'DOSTAWA TYLKO EXEC';

  @override
  String get entryScriptExecOnlyNotice =>
      'Uruchamiane u agenta przez palladin exec — agenci wykonują, nigdy nie czytają.';

  @override
  String entryScriptFooter(String interpreter, int lines) {
    String _temp0 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$lines linii',
      many: '$lines linii',
      few: '$lines linie',
      one: '1 linia',
    );
    return '$interpreter · $_temp0';
  }

  @override
  String get entryFieldTypeMultiline => 'Wieloliniowe';

  @override
  String get entryFieldTypeTextHint => 'jedna linia';

  @override
  String get entryFieldTypeMultilineHint => 'notatki, config';

  @override
  String get entryFieldTypeConcealedHint => 'zamaskowane';

  @override
  String get entryFieldAgentVisible => 'Widoczne dla agentów';

  @override
  String get entryFieldAgentVisibleTip =>
      'Widoczne dla agentów w Twojej organizacji — pokazywane w wyszukiwaniu agentów bez grantu. Tylko dla niesekretnych informacji pomocniczych.';

  @override
  String get entryFieldAgentVisibleEnableTip =>
      'Ukryte przed agentami w Discovery. Dotknij, aby udostępnić to niesekretne pole w Discovery.';

  @override
  String get entryFieldAgentVisibleDisableTip =>
      'Widoczne dla agentów w Discovery. Dotknij, aby ukryć to pole w Discovery.';

  @override
  String get entryFieldAgentDiscoveryVisible => 'Widoczne w Discovery agentów';

  @override
  String get entryFieldAgentDiscoveryHidden => 'Ukryte w Discovery agentów';

  @override
  String get entryFieldOn => 'Wł.';

  @override
  String get entryFieldOff => 'Wył.';

  @override
  String get entryFieldMoveUp => 'Przenieś w górę';

  @override
  String get entryFieldMoveDown => 'Przenieś w dół';

  @override
  String get entryFieldMenu => 'Opcje pola';

  @override
  String get entryVisibleToAgents => 'widoczne dla agentów';

  @override
  String get totpSectionTitle => 'Uwierzytelnianie dwuskładnikowe';

  @override
  String get totpEmptyHint =>
      'Dodaj kod czasowy (TOTP), aby autouzupełniać 2FA dla tego loginu.';

  @override
  String get totpAdd => 'Dodaj 2FA';

  @override
  String get totpRotates => 'zmienia się co 30 s';

  @override
  String get totpCopyCode => 'Kopiuj kod';

  @override
  String get totpRemove => 'Usuń 2FA';

  @override
  String get entryAddNotes => 'Dodaj notatki';

  @override
  String get settingsScreenTitle => 'Ustawienia';

  @override
  String get settingsManageOrganization => 'Organizacja';

  @override
  String get settingsOrgNameLabel => 'Nazwa organizacji';

  @override
  String get settingsOrgNameHint => 'Podaj nazwę organizacji';

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
  String get apiKeysCopied => 'Skopiowano do schowka.';

  @override
  String get apiKeysConnectTitle => 'Podłącz agenta';

  @override
  String get apiKeysAgentNameLabel => 'Nazwa agenta';

  @override
  String get apiKeysConnectInstall => 'Nie masz CLI? Zainstaluj:';

  @override
  String get apiKeysConnectDocs => 'Skopiuj link do dokumentacji';

  @override
  String get apiKeysAgentMessageTitle => 'Wiadomość dla agenta';

  @override
  String apiKeysAgentMessageBody(String name, String docs, String market) {
    return '$name, podłączono Cię do Palladin dla bezpiecznego dostępu do moich danych. Dowiedz się, jak utworzyć i używać swojego skilla Palladin: $docs — albo przejrzyj gotowe skille w markecie: $market.';
  }

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
  String get agentsSearchHint => 'Szukaj agentów…';

  @override
  String get agentsSearchEmpty => 'Żaden agent nie pasuje do wyszukiwania';

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
  String get agentsDeactivatedOn => 'Dezaktywowano';

  @override
  String get agentsConnectedOn => 'Połączono';

  @override
  String get agentsLastAccess => 'Ostatni dostęp';

  @override
  String get agentsPendingApproval => 'Oczekuje na zatwierdzenie';

  @override
  String get agentsDetailTitle => 'Agent';

  @override
  String get agentsDetailNotFound => 'Nie znaleziono agenta';

  @override
  String get agentsDetailId => 'Identyfikator';

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
      'Pozwala agentowi jedynie przeglądać listę sejfów i wpisów — zawartość sekretów pozostaje zablokowana, dopóki nie zatwierdzisz prośby lub nie nadasz dostępu z góry.';

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
    return 'Zezwolić agentowi „$name” na przeglądanie listy sejfów i wpisów? Bez Twojego zatwierdzenia lub wcześniej nadanego dostępu nie odczyta żadnego sekretu.';
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
  String get agentGrantsEmptyTitle => 'Brak grantów';

  @override
  String get agentGrantsEmptyHint =>
      'Ten agent nie ma żadnych grantów. Dodaj grant, aby dać dostęp do sejfu lub wpisu.';

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

  @override
  String get publicAssetSearchTitle => 'Ikony witryn';

  @override
  String get publicAssetSearchHint => 'Szukaj marki lub domeny';

  @override
  String get publicAssetSearchAction => 'Szukaj ikon witryn';

  @override
  String get agentsTypeUnknown => 'Nieznany';

  @override
  String get agentsDetailLastIp => 'Ostatnie IP';

  @override
  String get agentsDetailLastHostname => 'Ostatni hostname';

  @override
  String get grantsScreenTitle => 'Dostępy';

  @override
  String get grantsFilterAll => 'Wszystkie';

  @override
  String get grantsRetry => 'Ponów';

  @override
  String get grantsEmpty => 'Brak dostępów';

  @override
  String get grantsEmptyHint =>
      'Dostępy pojawią się tutaj, gdy agent poprosi o dostęp do tego sejfu.';

  @override
  String get grantsRevoke => 'Odbierz dostęp';

  @override
  String get grantsRevokeConfirmTitle => 'Odebrać dostęp?';

  @override
  String grantsRevokeConfirmBody(String agentName) {
    return '$agentName natychmiast straci dostęp. Tej operacji nie można cofnąć.';
  }

  @override
  String get grantsRevokeReasonLabel => 'Powód (opcjonalnie)';

  @override
  String get grantsRevokeReasonHint => 'Dlaczego odbierasz ten dostęp?';

  @override
  String grantCardTarget(String target) {
    return 'Dostęp do $target';
  }

  @override
  String get grantEntryUnknown => 'Nieznany wpis';

  @override
  String get grantUnnamedAgent => 'Agent bez nazwy';

  @override
  String get grantStatusPending => 'Oczekuje';

  @override
  String get grantStatusActive => 'Aktywny';

  @override
  String get grantStatusDenied => 'Odrzucony';

  @override
  String get grantStatusRevoked => 'Odebrany';

  @override
  String get grantStatusExpired => 'Wygasły';

  @override
  String get grantStatusConsumed => 'Wykorzystany';

  @override
  String get grantStatusSuperseded => 'Zastąpiony';

  @override
  String get grantScopeFull => 'Wszystkie wpisy';

  @override
  String get grantScopeGranular => 'Pojedynczy wpis';

  @override
  String get grantScopeScriptExecution => 'Wykonanie całego skryptu';

  @override
  String get grantAccessScriptTrustTitle => 'JEDEN GRANT WYKONANIA SKRYPTU';

  @override
  String get grantAccessScriptTrustBody =>
      'Nadaje dostęp Exec do kompletnego pakietu skryptu: źródła oraz wszystkich wskazanych pól, rozwiązanych lokalnie w jednym żądaniu. Późniejsze dodanie referencji rozszerzy dane dostępne temu Agentowi. Wartości parametrów CLI nigdy nie trafiają do backendu.';

  @override
  String get approvalSegmentPending => 'Oczekujące';

  @override
  String get approvalSegmentHistory => 'Historia';

  @override
  String get approvalHistorySearchHint => 'Szukaj dostępów…';

  @override
  String get approvalHistoryEmpty => 'Brak dostępów';

  @override
  String get approvalHistoryEmptyHint =>
      'Przyznane, wygasłe i odebrane dostępy pojawią się tutaj.';

  @override
  String get approvalHistoryFilterClear => 'Wyczyść';

  @override
  String get approvalPendingRequestsAccess => 'prosi o dostęp';

  @override
  String get approvalPendingRowRequested => 'Zażądano';

  @override
  String get orgGrantRowVault => 'Sejf';

  @override
  String get orgGrantRowEntry => 'Wpis';

  @override
  String get orgGrantRowActor => 'Przez';

  @override
  String get orgGrantRowAccess => 'Dostęp';

  @override
  String get orgGrantRowMethods => 'Metody';

  @override
  String get orgGrantRowReason => 'Powód';

  @override
  String get orgGrantRowDenyReason => 'Powód odmowy';

  @override
  String get orgGrantSupersededReason => 'Zastąpiony przez grant FULL';

  @override
  String get orgGrantRowRevokeReason => 'Powód odebrania';

  @override
  String get orgGrantActorSystem => 'System';

  @override
  String get orgGrantUnlimited => 'Bez limitu';

  @override
  String orgGrantUsesLeft(int left, int limit) {
    return 'Pozostało $left z $limit użyć';
  }

  @override
  String orgGrantExpiresOn(String date) {
    return 'Do $date';
  }

  @override
  String get orgGrantAlreadyActive => 'Aktywny w nowszym grancie';

  @override
  String get orgGrantShowActive => 'Pokaż aktywny grant';

  @override
  String get orgGrantRegrantUnavailable => 'Ponowne przyznanie niedostępne';

  @override
  String get orgGrantViewAgent => 'Zobacz Agenta';

  @override
  String get orgGrantViewVault => 'Zobacz sejf';

  @override
  String get orgGrantReviewRequest => 'Rozpatrz prośbę';

  @override
  String get grantDetailTitle => 'Dostęp';

  @override
  String get grantDetailScope => 'Zakres';

  @override
  String get grantDetailEntry => 'Wpis';

  @override
  String get grantDetailExpiry => 'Wygaśnięcie';

  @override
  String get grantDetailReason => 'Powód agenta';

  @override
  String get grantDetailRequested => 'Poproszono';

  @override
  String get grantDetailApproved => 'Zatwierdzono';

  @override
  String grantDetailApprovedBy(String date, String name) {
    return '$date przez $name';
  }

  @override
  String get grantDetailRevoked => 'Odebrano';

  @override
  String grantDetailExpiresAt(String date) {
    return 'Wygasa $date';
  }

  @override
  String grantDetailUsesLimit(int used, int limit) {
    return '$used z $limit użyć';
  }

  @override
  String get grantDetailNoExpiry => 'Bez wygaśnięcia';

  @override
  String get grantsErrorNotFound => 'Ten dostęp już nie istnieje.';

  @override
  String get grantsErrorForbidden =>
      'Nie masz uprawnień do zarządzania dostępami.';

  @override
  String get grantsErrorValidation =>
      'Żądanie zostało odrzucone. Sprawdź dane i spróbuj ponownie.';

  @override
  String get grantsErrorNetwork =>
      'Nie można połączyć się z serwerem. Sprawdź połączenie.';

  @override
  String get grantsErrorCrypto =>
      'Nie udało się bezpiecznie przygotować poświadczenia. Spróbuj ponownie.';

  @override
  String get grantsErrorUnknown => 'Coś poszło nie tak. Spróbuj ponownie.';

  @override
  String get approvalInboxTitle => 'Zatwierdzenia';

  @override
  String get approvalInboxEmpty => 'Nic do zatwierdzenia';

  @override
  String get approvalInboxEmptyHint =>
      'Gdy agent poprosi o dostęp do poświadczenia, prośba pojawi się tutaj — możesz ją zatwierdzić lub odrzucić.';

  @override
  String get approvalRetry => 'Ponów';

  @override
  String approvalCardRequest(String entry, String vault) {
    return 'Prosi o $entry w $vault';
  }

  @override
  String get approvalScreenTitle => 'Przejrzyj prośbę';

  @override
  String get approvalSummaryEntry => 'Wpis';

  @override
  String get approvalSummaryVault => 'Sejf';

  @override
  String get approvalSummaryReason => 'Powód agenta';

  @override
  String get approvalUnnamedAgent => 'Agent bez nazwy';

  @override
  String get approvalEntryUnknown => 'to poświadczenie';

  @override
  String get approvalVaultUnknown => 'sejf';

  @override
  String get approvalLimitSectionTitle => 'Limit dostępu';

  @override
  String get approvalLimitSectionHint =>
      'Wybierz jak długo trwa ten dostęp — czasowo lub liczbą użyć.';

  @override
  String get approvalLimitExpiry => 'Wygasa po';

  @override
  String get approvalLimitUses => 'Liczba użyć';

  @override
  String get approvalLimitUsesLabel => 'Maks. użyć';

  @override
  String get approvalApprove => 'Zatwierdź';

  @override
  String get approvalDenySectionTitle => 'Albo odrzuć';

  @override
  String get approvalDenyReasonLabel => 'Powód (opcjonalnie)';

  @override
  String get approvalDenyReasonHint => 'Dlaczego odrzucasz tę prośbę?';

  @override
  String get approvalDeny => 'Odrzuć';

  @override
  String get approvalCancel => 'Anuluj';

  @override
  String get approvalApproveTitle => 'Zatwierdź prośbę';

  @override
  String get approvalApproveSubGrant => 'Przyznaj';

  @override
  String get approvalApproveSubAccessTo => 'dostęp do';

  @override
  String get approvalApproveSubIn => 'w sejfie';

  @override
  String get approvalAccessType => 'Typ dostępu';

  @override
  String get approvalMethodsLegend => 'Jak agent może użyć';

  @override
  String get approvalMethodWarningZone => 'Strefa ostrzeżenia';

  @override
  String get approvalMethodNoneSelected => 'Wybierz co najmniej jedną metodę.';

  @override
  String get approvalMethodGetLabel => 'Get (plaintext)';

  @override
  String get approvalMethodGetWarning =>
      'Sekret trafia do kontekstu agenta — na hostowanym LLM może opuścić urządzenie.';

  @override
  String get approvalMethodExecLabel => 'Exec';

  @override
  String get approvalMethodInjectLabel => 'Inject';

  @override
  String get approvalApproving => 'Zatwierdzanie…';

  @override
  String get approvalPolicyTime => 'Czas';

  @override
  String get approvalPolicyUses => 'Użycia';

  @override
  String get approvalPolicyLifetime => 'Bezterminowo';

  @override
  String get approvalLifetimeHint =>
      'Agent zachowa dostęp, dopóki go nie odbierzesz.';

  @override
  String get approvalExpiresOnLabel => 'Wygasa dnia';

  @override
  String approvalQuickMinutes(int count) {
    return '${count}m';
  }

  @override
  String approvalQuickHours(int count) {
    return '${count}h';
  }

  @override
  String get approvalQuickCustom => 'Własny';

  @override
  String approvalExpiresInMinutes(int count) {
    return 'Wygasa za ${count}m';
  }

  @override
  String approvalExpiresInHours(int count) {
    return 'Wygasa za ${count}h';
  }

  @override
  String approvalExpiresInDays(int count) {
    return 'Wygasa za ${count}d';
  }

  @override
  String approvalExpiresInMonths(int count) {
    return 'Wygasa za ${count}mc';
  }

  @override
  String get approvalExpiredAlready => 'Wygasło';

  @override
  String approvalDenyTitle(String name) {
    return 'Odrzucić $name?';
  }

  @override
  String get approvalDenyText => 'Agent nie otrzyma dostępu do tego wpisu.';

  @override
  String get approvalDenying => 'Odrzucanie…';

  @override
  String get approvalRegrantTitle => 'Przyznaj ponownie';

  @override
  String get approvalRegrant => 'Przyznaj ponownie';

  @override
  String get approvalRegranting => 'Przyznawanie…';

  @override
  String get approvalErrorNotFound => 'Ta prośba już nie istnieje.';

  @override
  String get approvalErrorForbidden =>
      'Nie masz uprawnień do zarządzania dostępami.';

  @override
  String get approvalErrorValidation =>
      'Żądanie zostało odrzucone. Sprawdź dane i spróbuj ponownie.';

  @override
  String get approvalErrorNetwork =>
      'Nie można połączyć się z serwerem. Sprawdź połączenie.';

  @override
  String get approvalErrorCrypto =>
      'Nie udało się bezpiecznie przygotować poświadczenia. Spróbuj ponownie.';

  @override
  String get approvalErrorVaultLocked =>
      'Najpierw odblokuj sejf, aby zatwierdzić tę prośbę.';

  @override
  String get approvalErrorUnknown => 'Coś poszło nie tak. Spróbuj ponownie.';

  @override
  String get grantAccessTitleAgent => 'Dodaj agenta';

  @override
  String get grantAccessTitleVault => 'Przyznaj dostęp';

  @override
  String get grantAccessPickAgent => 'Agent';

  @override
  String get grantAccessPickVault => 'Sejf';

  @override
  String get grantAccessNoAgents => 'Brak aktywnych agentów';

  @override
  String get grantAccessNoVaults => 'Brak dostępnych sejfów';

  @override
  String get grantAccessSelectAgent => 'Wybierz agenta';

  @override
  String get grantAccessSelectVault => 'Wybierz sejf';

  @override
  String get grantAccessConfirm => 'Przyznaj dostęp';

  @override
  String get grantAccessGranting => 'Przyznawanie…';

  @override
  String get grantAccessError =>
      'Nie udało się utworzyć grantu. Spróbuj ponownie.';

  @override
  String get grantAccessFullTrustTitle => 'PEŁNE ZAUFANIE DO SEJFU';

  @override
  String get grantAccessFullTrustBody =>
      'Ten grant daje kryptograficzny dostęp do wszystkich bieżących i przyszłych wpisów w sejfie. Odebranie grantu blokuje nowe operacje online, ale nie wymazuje klucza skopiowanego przez przejętego agenta; po podejrzeniu kompromitacji obróć klucz sejfu.';

  @override
  String get grantAddGrant => 'Dodaj grant';

  @override
  String get approvalMethodGetDesc => 'Zwraca sekret jako plaintext do agenta.';

  @override
  String get approvalMethodExecDesc =>
      'Uruchamia komendę z sekretem w środowisku — nie trafia do kontekstu agenta.';

  @override
  String get approvalMethodInjectDesc =>
      'Wypełnia formularz logowania w przeglądarce agenta — nie trafia do kontekstu agenta.';

  @override
  String get approvalMethodsSelect => 'Wybierz metody';

  @override
  String get approvalMethodsDone => 'Gotowe';

  @override
  String get approvalMethodRequested => 'prośba';

  @override
  String get inboxTitle => 'Inbox';

  @override
  String get inboxSegAll => 'Wszystkie';

  @override
  String get inboxTodo => 'Do zrobienia';

  @override
  String get inboxHistory => 'Historia';

  @override
  String get inboxSearchHint => 'Szukaj po agencie, wpisie lub vaultcie…';

  @override
  String get inboxMarkAllRead => 'Oznacz wszystkie';

  @override
  String get inboxMoreActions => 'Więcej';

  @override
  String get inboxGrantsMenu => 'Granty';

  @override
  String get inboxPreferencesMenu => 'Ustawienia powiadomień';

  @override
  String get inboxAcceptAction => 'Akceptuj';

  @override
  String get inboxViewAgent => 'Zobacz agenta';

  @override
  String get inboxViewAccess => 'Zobacz dostęp';

  @override
  String get inboxViewEntry => 'Zobacz wpis';

  @override
  String get inboxGrantsEmpty => 'Brak grantów';

  @override
  String get inboxGrantsEmptyHint =>
      'Dostęp nadany Twoim agentom pojawi się tutaj.';

  @override
  String get inboxActionGone => 'Ta akcja nie jest już dostępna.';

  @override
  String get inboxAllEmpty => 'Twój inbox jest pusty';

  @override
  String get inboxAllEmptyHint =>
      'Prośby, zatwierdzenia i inna aktywność agentów pojawią się tutaj.';

  @override
  String get inboxTodoEmpty => 'Nic nie wymaga Twojej uwagi';

  @override
  String get inboxTodoEmptyHint =>
      'Prośby o dostęp i inne działania od Twoich agentów pojawią się tutaj.';

  @override
  String get inboxUpdatesEmpty => 'Brak historii';

  @override
  String get inboxUpdatesEmptyHint =>
      'Zatwierdzone, cofnięte i inne zakończone elementy pojawią się tutaj.';

  @override
  String get inboxErrorForbidden =>
      'Nie masz uprawnień do wyświetlania powiadomień.';

  @override
  String get inboxErrorNetwork =>
      'Nie można połączyć się z serwerem. Sprawdź połączenie.';

  @override
  String get inboxErrorUnknown =>
      'Nie udało się wczytać powiadomień. Spróbuj ponownie.';

  @override
  String get notifUnnamedAgent => 'Agent';

  @override
  String get notifUnknownAgent => 'Nieznany agent';

  @override
  String get notifTitleGrantPending => 'Prośba o dostęp';

  @override
  String get notifTitleAgentPending => 'Nowy agent';

  @override
  String get notifTitleAgentApproved => 'Agent zaakceptowany';

  @override
  String get notifTitleGrantRevoked => 'Dostęp cofnięty';

  @override
  String get notifTitleGrantApproved => 'Dostęp zatwierdzony';

  @override
  String get notifTitleGrantDenied => 'Dostęp odrzucony';

  @override
  String get notifTitleCredentialStale => 'Hasło nie działa';

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
    return 'zgłoszone przez $agent';
  }

  @override
  String notifSubGrantUpdate(String agent) {
    return '$agent';
  }

  @override
  String get notifRowEntry => 'Wpis';

  @override
  String get notifRowMethods => 'Metody';

  @override
  String get notifRowReason => 'Powód';

  @override
  String get notifRowHostIp => 'Host · Ip';

  @override
  String get notifRowError => 'Błąd';

  @override
  String get notifRowAttempts => 'Próby';

  @override
  String get notifRowNote => 'Notatka';

  @override
  String get notifRowAccess => 'Dostęp';

  @override
  String get notifRowBy => 'Przez';

  @override
  String get notifRowAgentId => 'Id agenta';

  @override
  String get notifRowPublicKey => 'Klucz publiczny';

  @override
  String get notifRowType => 'Typ';

  @override
  String get notifAccessUnlimited => 'Bez limitu';

  @override
  String get notifPlaceholder => '—';

  @override
  String get notifFilterTitle => 'Filtruj po typie';

  @override
  String get notifFilterClear => 'Wyczyść';

  @override
  String get notifPrefsTitle => 'Ustawienia powiadomień';

  @override
  String get notifPrefsHint =>
      'Wybierz, jak chcesz otrzymywać powiadomienia dla każdego typu. Niektóre krytyczne typy zawsze pozostają w skrzynce.';

  @override
  String get notifPrefsEmpty => 'Brak dostępnych preferencji.';

  @override
  String get notifPrefsSaveError =>
      'Nie udało się zapisać preferencji. Spróbuj ponownie.';

  @override
  String get notifPrefsMandatory => 'Zawsze włączone';

  @override
  String get notifPrefsChannelInbox => 'Inbox';

  @override
  String get notifPrefsChannelRealtime => 'Na żywo';

  @override
  String get notifPrefsChannelPush => 'Push';

  @override
  String get notifPrefsTypeAgentPending => 'Nowy agent do akceptacji';

  @override
  String get notifPrefsTypeGrantPending => 'Prośby o dostęp';

  @override
  String get notifPrefsTypeGrantRevoked => 'Cofnięcie dostępu';

  @override
  String get notifPrefsTypeGrantApproved => 'Zatwierdzenie dostępu';

  @override
  String get notifPrefsTypeGrantDenied => 'Odrzucenie dostępu';

  @override
  String get notifPrefsTypeCredentialStale => 'Nieaktualne hasło';

  @override
  String get auditSearchHint => 'Szukaj w dzienniku…';

  @override
  String get auditLoadMore => 'Wczytaj więcej';

  @override
  String get auditLoadMoreError => 'Nie udało się wczytać kolejnych wpisów.';

  @override
  String get auditEmptyTitle => 'Brak aktywności';

  @override
  String get auditEmptyHint =>
      'Tu pojawią się zdarzenia dostępu i nadań dla tego wpisu.';

  @override
  String get auditEmptyFilteredTitle => 'Brak pasujących zdarzeń';

  @override
  String get auditEmptyFilteredHint => 'Zmień filtry lub frazę wyszukiwania.';

  @override
  String get auditFilterTitle => 'Filtruj dziennik';

  @override
  String get auditFilterEventTypes => 'Typy zdarzeń';

  @override
  String get auditFilterAllEventTypes => 'Wszystkie typy';

  @override
  String get auditFilterAgent => 'Agent';

  @override
  String get auditFilterAllAgents => 'Wszyscy agenci';

  @override
  String multiSelectNSelected(int count) {
    return 'Wybrano: $count';
  }

  @override
  String get multiSelectSearchHint => 'Szukaj…';

  @override
  String get multiSelectNoResults => 'Brak wyników';

  @override
  String get auditFilterDateRange => 'Zakres dat';

  @override
  String get auditFilterFrom => 'Od';

  @override
  String get auditFilterTo => 'Do';

  @override
  String get auditFilterReset => 'Wyczyść';

  @override
  String get auditFilterApply => 'Zastosuj';

  @override
  String get auditDetailEntry => 'Wpis';

  @override
  String get auditDetailVault => 'Sejf';

  @override
  String get auditDetailReason => 'Powód';

  @override
  String get auditDetailNone => 'Brak dodatkowych szczegółów.';

  @override
  String get auditActorOwner => 'Właściciel';

  @override
  String get auditActorSystem => 'System';

  @override
  String get auditActorAgent => 'Agent';

  @override
  String get auditErrorForbidden =>
      'Nie masz uprawnień do przeglądania dziennika.';

  @override
  String get auditErrorNotFound => 'Dziennik jest niedostępny dla tego sejfu.';

  @override
  String get auditErrorNetwork =>
      'Błąd sieci. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get auditErrorGeneric =>
      'Nie udało się wczytać dziennika. Spróbuj ponownie.';

  @override
  String get auditEventGrantCreated => 'Przyznano dostęp';

  @override
  String get auditEventGrantRequested => 'Poproszono o dostęp';

  @override
  String get auditEventGrantApproved => 'Zatwierdzono dostęp';

  @override
  String get auditEventGrantDenied => 'Odrzucono dostęp';

  @override
  String get auditEventGrantRevoked => 'Cofnięto dostęp';

  @override
  String get auditEventGrantConsumed => 'Wykorzystano nadanie';

  @override
  String get auditEventGrantExpired => 'Nadanie wygasło';

  @override
  String get auditEventGrantSuperseded => 'Nadanie zastąpione';

  @override
  String get auditEventCredentialAccessed => 'Odczytano dane';

  @override
  String get auditEventCredentialAccessDenied => 'Odmówiono dostępu';

  @override
  String get auditEventAgentEnrolled => 'Zarejestrowano agenta';

  @override
  String get auditEventAgentBlocked => 'Zablokowano agenta';

  @override
  String get auditEventAgentReactivated => 'Ponownie aktywowano agenta';

  @override
  String get auditEventAgentDeleted => 'Usunięto agenta';

  @override
  String get auditEventVaultCreated => 'Utworzono sejf';

  @override
  String get auditEventVaultUpdated => 'Zaktualizowano sejf';

  @override
  String get auditEventVaultDeleted => 'Usunięto sejf';

  @override
  String get auditEventVaultExported => 'Sejf wyeksportowany';

  @override
  String get auditEventEntryCreated => 'Utworzono wpis';

  @override
  String get auditEventEntryUpdated => 'Zaktualizowano wpis';

  @override
  String get auditEventEntryDeleted => 'Usunięto wpis';

  @override
  String get auditEventApiKeyCreated => 'Utworzono klucz API';

  @override
  String get auditEventApiKeyActivated => 'Aktywowano klucz API';

  @override
  String get auditEventApiKeyRevoked => 'Unieważniono klucz API';

  @override
  String get auditEventApiKeyDeleted => 'Usunięto klucz API';

  @override
  String get auditEventOrgCreated => 'Utworzono organizację';

  @override
  String get auditEventOrgUpdated => 'Zaktualizowano organizację';

  @override
  String get auditEventUserSignedUp => 'Rejestracja użytkownika';

  @override
  String get auditEventAccountSetupCompleted => 'Ukończono konfigurację konta';

  @override
  String get auditEventAccountRecoveryCompleted =>
      'Ukończono odzyskiwanie konta';

  @override
  String get auditEventLoginFailed => 'Nieudane logowanie';

  @override
  String get auditEventUnknown => 'Aktywność';

  @override
  String get auditScreenTitle => 'Dziennik audytu';

  @override
  String get auditFilterVault => 'Sejf';

  @override
  String get auditFilterAllVaults => 'Wszystkie sejfy';

  @override
  String get auditFilterUser => 'Wykonane przez';

  @override
  String get auditFilterAllUsers => 'Dowolny';

  @override
  String get auditUserUnknown => 'Nieznany użytkownik';

  @override
  String auditUserUnknownShort(String id) {
    return 'Nieznany użytkownik ($id)';
  }

  @override
  String get auditGroupCredentialAccess => 'Odczyty';

  @override
  String get auditGroupGrants => 'Nadania';

  @override
  String get auditGroupVaultEntry => 'Sejfy i wpisy';

  @override
  String get auditGroupAgentLifecycle => 'Agenci';

  @override
  String get auditGroupApiKeys => 'Klucze API';

  @override
  String get auditGroupOrgAccount => 'Organizacja i konto';

  @override
  String get auditLegendTitle => 'Legenda zdarzeń';

  @override
  String get auditLegendSubtitle =>
      'Co oznaczają kolory przy każdym wpisie dziennika.';

  @override
  String auditSentenceCreated(String actor, String object) {
    return '$actor: utworzono $object';
  }

  @override
  String auditSentenceUpdated(String actor, String object) {
    return '$actor: zaktualizowano $object';
  }

  @override
  String auditSentenceDeleted(String actor, String object) {
    return '$actor: usunięto $object';
  }

  @override
  String auditSentenceExported(String actor, String object) {
    return '$actor wyeksportował $object';
  }

  @override
  String auditSentenceActivated(String actor, String object) {
    return '$actor: aktywowano $object';
  }

  @override
  String auditSentenceRevoked(String actor, String object) {
    return '$actor: unieważniono $object';
  }

  @override
  String auditSentenceBlocked(String actor, String object) {
    return '$actor: zablokowano $object';
  }

  @override
  String auditSentenceReactivated(String actor, String object) {
    return '$actor: ponownie aktywowano $object';
  }

  @override
  String auditSentenceUserSignedUp(String actor) {
    return '$actor: rejestracja w systemie';
  }

  @override
  String auditSentenceAccountSetupCompleted(String actor) {
    return '$actor: ukończono konfigurację konta';
  }

  @override
  String auditSentenceAccountRecoveryCompleted(String actor) {
    return '$actor: ukończono odzyskiwanie konta';
  }

  @override
  String get auditSentenceLoginFailed => 'Nieudana próba logowania';

  @override
  String auditSentenceAgentEnrolled(String agent) {
    return '$agent: rejestracja w systemie';
  }

  @override
  String auditObjectVaultNamed(String name) {
    return 'sejf $name';
  }

  @override
  String auditObjectEntryNamed(String name) {
    return 'wpis $name';
  }

  @override
  String auditObjectOrgNamed(String name) {
    return 'organizację $name';
  }

  @override
  String auditObjectApiKeyNamed(String name) {
    return 'klucz API $name';
  }

  @override
  String auditObjectAgentNamed(String name) {
    return 'agenta $name';
  }

  @override
  String get auditObjectVault => 'sejf';

  @override
  String get auditObjectEntry => 'wpis';

  @override
  String get auditObjectOrg => 'organizację';

  @override
  String get auditObjectApiKey => 'klucz API';

  @override
  String get auditObjectAgent => 'agenta';

  @override
  String get dashboardGoodMorning => 'Dzień dobry';

  @override
  String get dashboardSearchHint => 'Agenci, sejfy, wpisy…';

  @override
  String get defaultVaultName => 'Osobisty';

  @override
  String get dashboardOnboardingTitle => 'Skonfiguruj Palladin';

  @override
  String get dashboardOnboardingSubtitle =>
      'Wykonaj te kroki, aby bezpiecznie zarządzać dostępem';

  @override
  String dashboardOnboardingProgress(int completed) {
    return 'Ukończono $completed z 4';
  }

  @override
  String get dashboardOnboardingSkipSetup => 'Pomiń konfigurację';

  @override
  String get dashboardOnboardingStep1Title => 'Włącz powiadomienia';

  @override
  String get dashboardOnboardingStep1Description =>
      'Reaguj w sekundy — agenci czekają na Twoją zgodę. Szybsze odpowiedzi to płynniejsze przepływy pracy AI.';

  @override
  String get dashboardOnboardingStep1Enable => 'Włącz';

  @override
  String get dashboardOnboardingStep1Skip => 'Pomiń';

  @override
  String get dashboardOnboardingStep1OpenSettings => 'Otwórz Ustawienia';

  @override
  String get dashboardOnboardingStep2Title =>
      'Dodaj pierwszy wpis lub zaimportuj hasła';

  @override
  String get dashboardOnboardingStep2Description =>
      'Twój sejf Osobisty jest gotowy — dodaj hasło ręcznie lub zaimportuj istniejące dane.';

  @override
  String get dashboardOnboardingStep2Cta => 'Przejdź do sejfów';

  @override
  String get dashboardOnboardingStep3Title => 'Dodaj klucz API';

  @override
  String get dashboardOnboardingStep3Description =>
      'Połącz Palladin z zewnętrznymi usługami';

  @override
  String get dashboardOnboardingStep3Cta => 'Dodaj klucz API';

  @override
  String get dashboardOnboardingStep4Title => 'Zarejestruj agenta';

  @override
  String get dashboardOnboardingStep4Description =>
      'Dodaj pierwszego agenta AI, który może prosić o dostęp';

  @override
  String get dashboardOnboardingStep4Cta => 'Zarejestruj agenta';

  @override
  String dashboardOnboardingStep(int n) {
    return 'Krok $n';
  }

  @override
  String get dashboardUnknownAgentWarning => 'Niezarejestrowany agent';

  @override
  String get dashboardUnknownAgentDescription =>
      'Tego agenta nie ma jeszcze w systemie. Możesz go zarejestrować i jednocześnie zatwierdzić dostęp.';

  @override
  String get dashboardUnknownAgentRegisterAndApprove =>
      'Zarejestruj i zatwierdź';

  @override
  String get dashboardUnknownAgentReject => 'Odrzuć';

  @override
  String get dashboardRequestRejected => 'Prośba odrzucona';

  @override
  String get dashboardPendingApprovals => 'Oczekujące zgody';

  @override
  String get dashboardRecentActivity => 'Ostatnia aktywność';

  @override
  String get dashboardNoActivity => 'Brak aktywności';

  @override
  String get dashboardRecentlyModified => 'Ostatnio dodane / zmodyfikowane';

  @override
  String get dashboardSeeAll => 'Zobacz wszystko';

  @override
  String get dashboardSearchRecent => 'Ostatnie';

  @override
  String get searchResultsEmpty => 'Brak wyników dla tego wyszukiwania';

  @override
  String get searchResultsError =>
      'Wyszukiwanie nie powiodło się. Spróbuj ponownie.';

  @override
  String get searchTypeBadgeAgent => 'Agent';

  @override
  String get searchTypeBadgeMember => 'Członek';

  @override
  String get searchTypeBadgeVault => 'Vault';

  @override
  String get searchTypeBadgeEntry => 'Wpis';

  @override
  String get importTitle => 'Import';

  @override
  String get importChooseFile => 'Wybierz plik';

  @override
  String get importIntroTitle => 'Import z innego menedżera haseł';

  @override
  String get importIntroBody =>
      'Wybierz plik eksportu z Chrome, Bitwarden, 1Password, LastPass i innych. Wszystko jest parsowane i szyfrowane na Twoim urządzeniu.';

  @override
  String get importSupportedFormats =>
      'Obsługiwane: eksporty CSV, JSON, XML i ZIP (.1pux)';

  @override
  String get importParsing => 'Odczyt pliku…';

  @override
  String get importSelectVaultSubtitle =>
      'Wybierz, gdzie trafią zaimportowane wpisy';

  @override
  String get importNoVaults =>
      'Brak sejfów. Najpierw utwórz sejf, potem zaimportuj do niego.';

  @override
  String importEntriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wpisu',
      many: '$count wpisów',
      few: '$count wpisy',
      one: '1 wpis',
    );
    return '$_temp0';
  }

  @override
  String importSkippedNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pominięto $count pozycji niebędącej loginami',
      many: 'Pominięto $count pozycji niebędących loginami',
      few: 'Pominięto $count pozycje niebędące loginami',
      one: 'Pominięto 1 pozycję niebędącą loginem',
    );
    return '$_temp0';
  }

  @override
  String get importConflictStrategyLabel => 'Dla wpisów, które już istnieją';

  @override
  String get importStrategySkip => 'Pomiń';

  @override
  String get importStrategyOverwrite => 'Nadpisz';

  @override
  String get importStrategyRename => 'Zachowaj oba';

  @override
  String get importConflictBadge => 'Istnieje';

  @override
  String get importTotpBadge => '2FA';

  @override
  String get importNotesBadge => 'Notatki';

  @override
  String importAction(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wpisu',
      many: '$count wpisów',
      few: '$count wpisy',
      one: '1 wpis',
    );
    return 'Importuj $_temp0';
  }

  @override
  String importImporting(int done, int total) {
    return 'Importowanie… $done z $total';
  }

  @override
  String importPreparingIcons(int done, int total) {
    return 'Przygotowywanie ikon… $done z $total (maks. 15 sekund)';
  }

  @override
  String get importSuccessTitle => 'Import zakończony';

  @override
  String importSuccessBody(int created, int updated) {
    String _temp0 = intl.Intl.pluralLogic(
      created,
      locale: localeName,
      other: 'Dodano $created wpisu',
      many: 'Dodano $created wpisów',
      few: 'Dodano $created wpisy',
      one: 'Dodano 1 wpis',
    );
    String _temp1 = intl.Intl.pluralLogic(
      updated,
      locale: localeName,
      other: 'zaktualizowano $updated',
      one: 'zaktualizowano 1',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String importSuccessSkipped(int count) {
    return 'Pominięto $count';
  }

  @override
  String get importDone => 'Gotowe';

  @override
  String get importFailedTitle => 'Import nie powiódł się';

  @override
  String get importTryAnother => 'Wybierz inny plik';

  @override
  String get importErrorEmpty => 'Ten plik jest pusty.';

  @override
  String get importErrorEncrypted =>
      'Ten eksport jest zaszyfrowany i nie można go odczytać. Wyeksportuj plik niezaszyfrowany (np. KeePass XML) i spróbuj ponownie.';

  @override
  String get importErrorUnrecognised =>
      'Nie rozpoznaliśmy tego pliku. Spróbuj eksportu CSV, JSON lub XML.';

  @override
  String get importErrorNoEntries =>
      'Nie znaleziono wpisów logowania w tym pliku.';

  @override
  String get importErrorCrypto =>
      'Nie udało się zaszyfrować wpisów. Zablokuj i odblokuj sejf, a następnie spróbuj ponownie.';

  @override
  String get importErrorNetwork =>
      'Nie można połączyć się z serwerem. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get importErrorUnknown => 'Coś poszło nie tak. Spróbuj ponownie.';

  @override
  String get importColumnMapTitle => 'Mapuj kolumny';

  @override
  String get importColumnMapSubtitle =>
      'Nie wykryliśmy tego formatu. Wskaż, która kolumna jest która.';

  @override
  String get importColumnName => 'Kolumna nazwy';

  @override
  String get importColumnUsername => 'Kolumna loginu';

  @override
  String get importColumnPassword => 'Kolumna hasła';

  @override
  String get importColumnUrl => 'Kolumna adresu URL';

  @override
  String get importColumnNotes => 'Kolumna notatek';

  @override
  String get importColumnTotp => 'Kolumna TOTP';

  @override
  String get importColumnNone => '— Brak —';

  @override
  String importColumnFallback(int number) {
    return 'Kolumna $number';
  }

  @override
  String get importUntitledFallback => 'Bez nazwy';

  @override
  String get importColumnMapContinue => 'Kontynuuj';

  @override
  String get importColumnMapNeedPassword =>
      'Wybierz przynajmniej kolumnę hasła.';

  @override
  String get importFormatGeneric => 'CSV';

  @override
  String get importFormatManual => 'Własny CSV';

  @override
  String get settingsImport => 'Import';

  @override
  String get vaultActionImport => 'Importuj wpisy';

  @override
  String get vaultActionExport => 'Eksportuj sejf';

  @override
  String get exportTitle => 'Eksport sejfu';

  @override
  String get exportFormatCsv => 'CSV';

  @override
  String get exportFormatJson => 'JSON';

  @override
  String get exportCsvHint =>
      'Zgodny z Chrome, Bitwarden i większością menedżerów.';

  @override
  String get exportJsonHint =>
      'Pełny format Palladin — bezstratny ponowny import.';

  @override
  String get exportWarningTitle => 'EKSPORT W POSTACI JAWNEJ';

  @override
  String get exportWarningBody =>
      'Plik zawiera Twoje hasła i sekrety TOTP w postaci jawnej. Każdy, kto ma ten plik, może je odczytać. Przechowuj go bezpiecznie i usuń po zakończeniu.';

  @override
  String get exportConfirm => 'Eksportuj';

  @override
  String exportSuccess(int count) {
    return 'Wyeksportowano $count wpisów';
  }

  @override
  String get exportEmpty => 'Ten sejf nie ma wpisów do eksportu.';

  @override
  String get exportErrorCrypto =>
      'Nie udało się odszyfrować sejfu. Zablokuj i odblokuj, a następnie spróbuj ponownie.';

  @override
  String get exportErrorNetwork =>
      'Nie można połączyć się z serwerem. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get exportErrorUnknown => 'Coś poszło nie tak. Spróbuj ponownie.';

  @override
  String get exportIncludeArchived => 'Uwzględnij zarchiwizowane wpisy';

  @override
  String get exportIncludeDeleted => 'Uwzględnij ostatnio usunięte wpisy';

  @override
  String get exportIncludeHistory => 'Uwzględnij poprzednie wersje';

  @override
  String get exportDeletionDisclosure =>
      'Palladin usuwa swoją kopię tymczasową po udostępnieniu w miarę możliwości. Kopie utworzone przez wybraną aplikację lub usługę chmurową pozostają pod kontrolą odbiorcy i mogą nadal tam istnieć.';

  @override
  String get exportErrorTooLarge =>
      'Eksport przekracza lokalny limit bezpieczeństwa. Wybierz mniejszy zakres.';

  @override
  String get authLoginSubtitle =>
      'Zaloguj się adresem e-mail i hasłem głównym.';

  @override
  String get authEmailLabel => 'E-mail';

  @override
  String get authEmailHint => 'ty@przyklad.pl';

  @override
  String get authEmailInvalid => 'Podaj prawidłowy adres e-mail.';

  @override
  String get authPasswordLabel => 'Hasło główne';

  @override
  String get authLoginButton => 'Zaloguj się';

  @override
  String get authInvalidCredentials => 'Nieprawidłowy e-mail lub hasło.';

  @override
  String get authRateLimited => 'Zbyt wiele prób. Spróbuj ponownie później.';

  @override
  String get authNoAccountPrompt => 'Nie masz konta?';

  @override
  String get authSignUpLink => 'Zarejestruj się';

  @override
  String get authRegisterButton => 'Zarejestruj się';

  @override
  String get authOrDivider => 'lub';

  @override
  String get authRegisterTitle => 'Załóż konto';

  @override
  String get authRegisterSubtitle =>
      'Hasło główne szyfruje wszystko na urządzeniu. Nigdy go nie widzimy.';

  @override
  String get authRegisterConfirmLabel => 'Potwierdź hasło';

  @override
  String get authRegisterHaveAccount => 'Masz już konto?';

  @override
  String get authRegisterSignIn => 'Zaloguj się';

  @override
  String get authRegisterEmailTaken =>
      'Konto z tym adresem e-mail już istnieje.';

  @override
  String get authPasswordChecking => 'Sprawdzanie Twojego hasła...';

  @override
  String get authPasswordSecure => 'Bezpieczne!';

  @override
  String get authPasswordImprove => 'Użyj dłuższego hasła z różnymi znakami.';

  @override
  String get authPasswordCheckUnavailable =>
      'Nie udało się sprawdzić wycieków - użyj unikalnego hasła.';

  @override
  String get authPasswordBreached =>
      'Hasło znaleziono w wycieku - wybierz inne.';

  @override
  String get authRecoveryWarningTitle => 'ZAPISZ KLUCZ ODZYSKIWANIA';

  @override
  String authVerifyGateSubtitle(String email) {
    return 'Wysłaliśmy link weryfikacyjny na adres $email.';
  }

  @override
  String get authVerifyGateSubtitleNoEmail =>
      'Wysłaliśmy Ci link weryfikacyjny.';

  @override
  String get authVerifyGateInstruction => 'Otwórz go, aby aktywować konto.';

  @override
  String get authVerifyResendButton => 'Wyślij ponownie';

  @override
  String get authVerifyCheckAgain => 'E-mail został zweryfikowany';

  @override
  String get authVerifyStillPending =>
      'Nie udało się jeszcze potwierdzić weryfikacji. Otwórz link i spróbuj ponownie.';

  @override
  String get authVerifyCheckError =>
      'Nie udało się dokończyć konfiguracji konta. Spróbuj ponownie.';

  @override
  String get authVerifyResendSent => 'E-mail weryfikacyjny wysłany.';

  @override
  String get authVerifyResendError =>
      'Nie udało się wysłać ponownie. Spróbuj ponownie.';

  @override
  String get authVerifyLogout => 'Wyloguj się';

  @override
  String get authVerifyingTitle => 'Weryfikacja…';

  @override
  String get authVerifiedTitle => 'E-mail zweryfikowany';

  @override
  String get authVerifiedSubtitle => 'Twoje konto jest już aktywne.';

  @override
  String get authVerifyContinue => 'Kontynuuj';

  @override
  String get authVerifyGoToLogin => 'Przejdź do logowania';

  @override
  String get authVerifyExpiredTitle => 'Link wygasł';

  @override
  String get authVerifyExpiredSubtitle =>
      'Ten link weryfikacyjny wygasł. Poproś o nowy.';

  @override
  String get authVerifyInvalidTitle => 'Nieprawidłowy link';

  @override
  String get authVerifyInvalidSubtitle =>
      'Ten link weryfikacyjny jest nieprawidłowy lub został już użyty.';

  @override
  String get authTotpChallengeTitle => 'Uwierzytelnianie dwuskładnikowe';

  @override
  String get authTotpChallengeSubtitle =>
      'Wpisz 6-cyfrowy kod z aplikacji uwierzytelniającej.';

  @override
  String get authTotpRecoverySubtitle =>
      'Wpisz jeden ze swoich kodów odzyskiwania.';

  @override
  String get authTotpCodeLabel => 'Kod uwierzytelniający';

  @override
  String get authTotpRecoveryLabel => 'Kod odzyskiwania';

  @override
  String get authTotpVerifyButton => 'Zweryfikuj';

  @override
  String get authTotpUseRecovery => 'Użyj kodu odzyskiwania';

  @override
  String get authTotpUseCode => 'Użyj kodu z aplikacji';

  @override
  String get authTotpInvalid => 'Nieprawidłowy kod. Spróbuj ponownie.';

  @override
  String get authTotpEnrollTitle =>
      'Skonfiguruj uwierzytelnianie dwuskładnikowe';

  @override
  String get authTotpEnrollSubtitle =>
      'Zeskanuj kod QR aplikacją uwierzytelniającą lub wpisz klucz konfiguracyjny ręcznie.';

  @override
  String get authTotpEnrollSecretLabel => 'Klucz konfiguracyjny';

  @override
  String get authTotpEnrollCopyKey => 'Kopiuj klucz';

  @override
  String get authTotpEnrollKeyCopied => 'Skopiowano klucz konfiguracyjny.';

  @override
  String get authTotpEnrollCodeLabel => 'Wpisz 6-cyfrowy kod';

  @override
  String get authTotpEnrollConfirmButton => 'Włącz';

  @override
  String get authTotpEnrollRetry => 'Ponów';

  @override
  String get authTotpEnrollRecoveryTitle => 'Zapisz kody odzyskiwania';

  @override
  String get authTotpEnrollRecoverySubtitle =>
      'Przechowuj je w bezpiecznym miejscu. Każdego kodu można użyć raz, jeśli utracisz aplikację uwierzytelniającą.';

  @override
  String get authTotpEnrollRecoveryWarningTitle => 'POKAZANE TYLKO RAZ';

  @override
  String get authTotpEnrollRecoveryWarning =>
      'Te kody nie zostaną pokazane ponownie. Zapisz je, zanim przejdziesz dalej.';

  @override
  String get authTotpEnrollNoCodes => 'Nie zwrócono kodów odzyskiwania.';

  @override
  String get authTotpEnrollCopyCodes => 'Kopiuj kody';

  @override
  String get authTotpEnrollCodesCopied => 'Skopiowano kody odzyskiwania.';

  @override
  String get authTotpEnrollDone => 'Gotowe';

  @override
  String get authChangePwTitle => 'Zmień hasło główne';

  @override
  String get authChangePwSubtitle =>
      'To ponownie zaszyfruje klucz sejfu na urządzeniu. Klucz odzyskiwania pozostaje bez zmian.';

  @override
  String get authChangePwCurrentLabel => 'Obecne hasło główne';

  @override
  String get authChangePwNewLabel => 'Nowe hasło główne';

  @override
  String get authChangePwConfirmLabel => 'Potwierdź nowe hasło';

  @override
  String get authChangePwWrongCurrent => 'Obecne hasło jest nieprawidłowe.';

  @override
  String get authChangePwSameAsCurrent => 'Wybierz hasło inne niż obecne.';

  @override
  String get authChangePwWarningTitle => 'ODBLOKOWANIE BIOMETRYCZNE';

  @override
  String get authChangePwWarning =>
      'Po zmianie hasła musisz ponownie włączyć odblokowanie biometryczne.';

  @override
  String get authChangePwButton => 'Zmień hasło';

  @override
  String get authChangePwSuccess => 'Zmieniono hasło główne.';

  @override
  String get settingsChangePassword => 'Zmień hasło główne';

  @override
  String get entryStateActive => 'Aktywne';

  @override
  String get entryStateArchived => 'Archiwum';

  @override
  String get entryStateDeleted => 'Ostatnio usunięte';

  @override
  String get entryArchivedRecoverability => 'Zarchiwizowany · można przywrócić';

  @override
  String get entryDeletedRecoverability =>
      'Ostatnio usunięty · możliwy do odzyskania w okresie retencji';

  @override
  String get entryCorruptProjection =>
      'Nie udało się zweryfikować zaszyfrowanych metadanych';

  @override
  String get entryArchiveTitle => 'Archiwum';

  @override
  String get entryArchiveSubtitle => 'Wpisy poza aktywnym sejfem';

  @override
  String get entryArchiveSearchHint => 'Szukaj w archiwum';

  @override
  String get entryArchiveEmpty => 'Brak zarchiwizowanych wpisów';

  @override
  String get entryArchiveRestore => 'Przywróć';

  @override
  String get entryArchiveRestoring => 'Przywracanie…';

  @override
  String get entryArchiveConflict =>
      'Ten wpis zmienił się na innym urządzeniu. Zsynchronizuj i spróbuj ponownie.';

  @override
  String get entryArchiveAllTypes => 'Wszystkie typy';

  @override
  String get entryArchiveSortAscending => 'A–Z';

  @override
  String get entryArchiveSortDescending => 'Z–A';

  @override
  String get entryArchiveSortType => 'Według typu';

  @override
  String get entryDeletedTitle => 'Ostatnio usunięte';

  @override
  String get entryDeletedSubtitle => 'Wpisy oczekujące na trwałe usunięcie';

  @override
  String get entryDeletedSearchHint => 'Szukaj w ostatnio usuniętych';

  @override
  String get entryDeletedEmpty => 'Brak ostatnio usuniętych wpisów';

  @override
  String get entryDeletedRestore => 'Przywróć';

  @override
  String entryDeletedPurgeAt(String date) {
    return 'Trwałe usunięcie po $date';
  }

  @override
  String get entryDeletedPurgeTitle => 'Usunąć trwale?';

  @override
  String get entryDeletedPurgeWarning =>
      'Ta operacja trwale usuwa całą zaszyfrowaną zawartość, klucze i historię. Nie można jej cofnąć.';

  @override
  String get entryDeletedPurgeConfirm => 'Usuń trwale';

  @override
  String get vaultDiscoveryTitle => 'Wykrywanie agentów';

  @override
  String get vaultDiscoveryNoActiveAgents =>
      'Żaden aktywny agent organizacji nie wymaga provisioningu Discovery.';

  @override
  String get vaultDiscoveryCurrent => 'Aktualny';

  @override
  String get vaultDiscoveryPending => 'Oczekujący / nieaktualny';

  @override
  String vaultDiscoveryVdkVersion(int version) {
    return 'Aktualna wersja klucza Discovery: v$version';
  }

  @override
  String vaultDiscoveryKeyVersion(int version) {
    return 'Klucz odbiorcy v$version';
  }

  @override
  String get vaultMemberYou => 'Ty';

  @override
  String get vaultMemberActive => 'Aktywny';

  @override
  String get vaultMemberPending => 'Usunięcie oczekuje';

  @override
  String get vaultMemberRotating =>
      'Zabezpieczanie dostępu — sejf pozostaje dostępny';

  @override
  String get vaultMemberBlockedLast =>
      'Zablokowane — ostatni uprawniony członek';

  @override
  String get vaultMemberRemove => 'Usuń';

  @override
  String get vaultMemberRemoveTitle => 'Usunąć członka organizacji?';

  @override
  String vaultMemberRemoveBody(String name) {
    return 'Usunięcie użytkownika $name dotyczy wszystkich sejfów, do których ma dostęp. Dostęp pozostanie aktywny do zatwierdzenia wszystkich wymaganych rotacji kluczy.';
  }

  @override
  String get vaultMemberRemovalStarted =>
      'Rozpoczęto usuwanie. Sejf pozostaje dostępny podczas rotacji.';

  @override
  String get vaultMembersLoadError => 'Nie udało się wczytać stanu członków.';

  @override
  String get vaultMemberForbidden =>
      'Nie masz uprawnień do zarządzania członkami organizacji.';

  @override
  String get vaultMemberProtected => 'Tego członka nie można usunąć.';

  @override
  String get vaultMemberNetworkError =>
      'Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get vaultMetadataConflict =>
      'Ten sejf został zmieniony na innym urządzeniu. Sprawdź najnowsze wartości i spróbuj ponownie.';

  @override
  String get vaultMetadataCorrupt =>
      'Nie udało się zweryfikować zaszyfrowanych ustawień sejfu. Nie zapisano zmian.';

  @override
  String get entryTabHistory => 'Historia';

  @override
  String get entryHistoryEmpty => 'Brak poprzednich wersji';

  @override
  String get entryHistoryLoadError =>
      'Nie udało się wczytać lub zweryfikować zaszyfrowanej historii.';

  @override
  String entryHistoryVersion(String revision) {
    return 'Wersja $revision';
  }

  @override
  String entryHistoryActor(String actor, String time) {
    return '$actor · $time';
  }

  @override
  String get entryHistoryLoadMore => 'Wczytaj starsze wersje';

  @override
  String get entryHistoryCurrent => 'Bieżąca';

  @override
  String get entryHistoryReveal => 'Pokaż';

  @override
  String get entryHistoryHide => 'Ukryj';

  @override
  String get entryHistoryDecrypting => 'Odszyfrowywanie…';

  @override
  String get entryHistoryRestore => 'Przywróć tę wersję';

  @override
  String get entryHistoryRestoring => 'Przywracanie…';

  @override
  String get entryHistoryRestored =>
      'Historyczna treść została przywrócona jako nowa aktualna wersja.';

  @override
  String get entryHistoryDecryptError =>
      'Nie udało się odszyfrować tej wersji. Sejf może być zablokowany.';

  @override
  String get entryHistoryRestoreError => 'Nie udało się przywrócić tej wersji.';

  @override
  String get entryHistoryOperationCreated => 'Utworzono';

  @override
  String get entryHistoryOperationUpdated => 'Zmieniono';

  @override
  String get entryHistoryOperationArchived => 'Zarchiwizowano';

  @override
  String get entryHistoryOperationRestored => 'Przywrócono';

  @override
  String get entryHistoryOperationDeleted => 'Usunięto';

  @override
  String entryHistoryMemberActor(String name) {
    return 'Użytkownik: $name';
  }

  @override
  String entryHistoryAgentActor(String name) {
    return 'Agent: $name';
  }

  @override
  String get entryHistorySystemActor => 'System';

  @override
  String get entryHistorySensitiveWarning =>
      'Historyczne wersje mogą zawierać poprzednie hasła i nasiona TOTP.';

  @override
  String get entryHistoryLocked =>
      'Odblokuj aplikację, aby odszyfrować tę wersję.';

  @override
  String get settingsTwoFactor => 'Uwierzytelnianie dwuskładnikowe';

  @override
  String get entryCardholderNameLabel => 'Imię i nazwisko posiadacza';

  @override
  String get entryCardNumberLabel => 'Numer karty';

  @override
  String get entryExpiryMonthLabel => 'Miesiąc ważności';

  @override
  String get entryExpiryYearLabel => 'Rok ważności';

  @override
  String get entryBillingAddressLabel => 'Adres rozliczeniowy (opcjonalnie)';

  @override
  String get settingsOrganizationTitle => 'Organizacja';

  @override
  String get settingsGeneralTitle => 'Ogólne';

  @override
  String get settingsGeneralSubtitle => 'Profil organizacji';

  @override
  String get settingsTeam => 'Zespół';

  @override
  String get settingsPermissions => 'Uprawnienia';

  @override
  String get settingsAuditLogs => 'Dzienniki audytu';

  @override
  String get settingsBilling => 'Rozliczenia';

  @override
  String get settingsSecurity => 'Bezpieczeństwo';

  @override
  String get settingsDataImport => 'Import danych';

  @override
  String get settingsActionsTitle => 'Sesja';

  @override
  String get settingsReadOnly =>
      'Możesz wyświetlać te ustawienia, ale zmienić je może tylko osoba zarządzająca organizacją.';

  @override
  String get settingsErrorConflict =>
      'Zasób został zmieniony albo jest nadal używany. Odśwież i spróbuj ponownie.';

  @override
  String get teamScreenTitle => 'Zespół';

  @override
  String get teamScreenSubtitle => 'Członkowie i oczekujące zaproszenia';

  @override
  String get teamSearchHint => 'Szukaj członków i zaproszeń';

  @override
  String get teamFilterMembers => 'Członkowie';

  @override
  String get teamFilterPending => 'Oczekujące zaproszenia';

  @override
  String get teamInvite => 'Zaproś';

  @override
  String get teamInviteTitle => 'Zaproś członka';

  @override
  String teamSeatUsage(int used, int limit) {
    return 'Zajęte: $used z $limit';
  }

  @override
  String get teamSeatUsageLabel => 'Wykorzystanie miejsc';

  @override
  String teamSeatUsageValue(int used, int limit) {
    return '$used / $limit';
  }

  @override
  String teamSeatsAvailable(int count) {
    return 'Wolne: $count';
  }

  @override
  String get teamSeatsUnavailable =>
      'Nie udało się wczytać wykorzystania miejsc.';

  @override
  String get teamManageSeats => 'Zarządzaj miejscami';

  @override
  String get teamSeatLimitReached => 'Organizacja nie ma wolnych miejsc.';

  @override
  String get teamNoSeatsTitle => 'Brak wolnych miejsc';

  @override
  String get teamNoSeatsBody =>
      'Zarządzaj miejscami w organizacji, zanim zaprosisz kolejnego członka.';

  @override
  String get teamEmailLabel => 'Adres e-mail';

  @override
  String get teamRoleLabel => 'Rola początkowa';

  @override
  String get teamSendInvitation => 'Wyślij zaproszenie';

  @override
  String get teamInvitationSent => 'Wysłano zaproszenie.';

  @override
  String get teamInvitationCancelled => 'Anulowano zaproszenie.';

  @override
  String get teamInvitationResent =>
      'Ponownie wysłano zaproszenie z nowym linkiem.';

  @override
  String get teamInvitationRoleUpdated => 'Zaktualizowano rolę zaproszenia.';

  @override
  String get teamMemberRolesUpdated => 'Zaktualizowano role członka.';

  @override
  String get teamInvalidEmail => 'Podaj prawidłowy adres e-mail.';

  @override
  String get teamNoInvitationRoles =>
      'Brak ról, których można bezpiecznie użyć w zaproszeniu.';

  @override
  String get teamEmpty => 'Nie znaleziono członków organizacji.';

  @override
  String get teamNoMatches => 'Brak pasujących osób lub zaproszeń.';

  @override
  String get teamOwner => 'Właściciel';

  @override
  String get teamPending => 'Oczekuje';

  @override
  String teamRoleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count roli',
      many: '$count ról',
      few: '$count role',
      one: '1 rola',
    );
    return '$_temp0';
  }

  @override
  String get teamMemberTitle => 'Członek';

  @override
  String teamJoined(String date) {
    return 'Dołączono $date';
  }

  @override
  String get teamRolesTitle => 'Role';

  @override
  String get teamRolesHint =>
      'Role kontrolują administrację organizacją. Nie przyznają dostępu do zaszyfrowanej zawartości sejfów.';

  @override
  String get teamSaveRoles => 'Zapisz role';

  @override
  String get teamAtLeastOneRole =>
      'Każdy członek musi zachować co najmniej jedną rolę.';

  @override
  String get teamMemberReadOnly =>
      'Twoje konto nie może zmieniać ról tego członka.';

  @override
  String get teamInvitationTitle => 'Oczekujące zaproszenie';

  @override
  String teamInvitedBy(String name) {
    return 'Osoba zapraszająca: $name';
  }

  @override
  String teamSentAt(String date) {
    return 'Wysłano $date';
  }

  @override
  String teamExpiresAt(String date) {
    return 'Wygasa $date';
  }

  @override
  String get teamResend => 'Wyślij ponownie';

  @override
  String teamResendAvailable(String date) {
    return 'Ponowne wysłanie dostępne $date';
  }

  @override
  String get teamCancelInvitation => 'Anuluj zaproszenie';

  @override
  String get teamCancelInvitationTitle => 'Anulować to zaproszenie?';

  @override
  String get teamCancelInvitationBody =>
      'Aktualny link przestanie działać, a zarezerwowane miejsce zostanie zwolnione.';

  @override
  String get teamCancel => 'Anuluj';

  @override
  String get teamConfirmCancel => 'Anuluj zaproszenie';

  @override
  String get permissionsScreenTitle => 'Uprawnienia';

  @override
  String get permissionsScreenSubtitle =>
      'Role organizacji i dostęp administracyjny';

  @override
  String get permissionsCreate => 'Utwórz rolę';

  @override
  String get permissionsCreateTitle => 'Utwórz rolę';

  @override
  String get permissionsEditTitle => 'Rola';

  @override
  String get permissionsRoleName => 'Nazwa roli';

  @override
  String get permissionsRoleNameHint => 'np. Menedżer sejfów';

  @override
  String get permissionsPermissionTitle => 'Uprawnienia administracyjne';

  @override
  String get permissionsPermissionHint =>
      'Uprawnienia nie zapewniają kryptograficznego dostępu do zawartości sejfów.';

  @override
  String get permissionsSystem => 'Systemowa';

  @override
  String permissionsAssignedMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count przypisanego członka',
      many: '$count przypisanych członków',
      few: '$count przypisanych członków',
      one: '1 przypisany członek',
    );
    return '$_temp0';
  }

  @override
  String get permissionsEmpty => 'Nie znaleziono ról organizacji.';

  @override
  String get permissionsCreated => 'Utworzono rolę.';

  @override
  String get permissionsUpdated => 'Zaktualizowano rolę.';

  @override
  String get permissionsDeleted => 'Usunięto rolę.';

  @override
  String get permissionsDelete => 'Usuń rolę';

  @override
  String get permissionsDeleteTitle => 'Usunąć tę rolę?';

  @override
  String get permissionsDeleteBody =>
      'Usunięcia nieprzypisanej roli własnej nie można cofnąć.';

  @override
  String get permissionsDeleteBlocked =>
      'Przed usunięciem odbierz tę rolę wszystkim członkom.';

  @override
  String get permissionsSystemReadOnly =>
      'Role systemowe są zarządzane przez Palladin i nie można ich edytować.';

  @override
  String get permissionsRoleReadOnly =>
      'Ta rola wykracza poza Twój zakres nadawania uprawnień i jest tylko do odczytu.';

  @override
  String get permissionsSave => 'Zapisz rolę';

  @override
  String get settingsSecurityTitle => 'Bezpieczeństwo';

  @override
  String get settingsSecuritySubtitle => 'Uwierzytelnianie i ochrona konta';

  @override
  String get settingsSecurityPasswordHint =>
      'Zmień hasło główne używane do odblokowania konta.';

  @override
  String get settingsSecurityTwoFactorHint =>
      'Chroń logowanie hasłem za pomocą czasowego kodu jednorazowego.';

  @override
  String get settingsSecurityOAuth =>
      'Ustawieniami hasła i uwierzytelniania dwuskładnikowego zarządza dostawca logowania.';

  @override
  String get settingsDataImportTitle => 'Import danych';

  @override
  String get settingsDataImportSubtitle =>
      'Przenieś dane z innego menedżera haseł';

  @override
  String get settingsDataImportBody =>
      'Wybierz plik eksportu i docelowy sejf. Plik zostanie odczytany i zaszyfrowany na tym urządzeniu, zanim jakiekolwiek dane zostaną wysłane.';

  @override
  String get settingsDataImportAction => 'Wybierz sejf i plik';

  @override
  String get settingsBillingTitle => 'Rozliczenia';

  @override
  String get settingsBillingSubtitle => 'Plan i miejsca w organizacji';

  @override
  String get settingsBillingComingSoon => 'Rozliczenia będą dostępne wkrótce';

  @override
  String get settingsBillingComingSoonBody =>
      'Zarządzanie planem nie jest jeszcze dostępne. Twój obecny dostęp pozostaje bez zmian.';

  @override
  String get permissionAddUser => 'Zapraszanie członków';

  @override
  String get permissionOrganizationManagement => 'Zarządzanie organizacją';

  @override
  String get permissionVaultCreate => 'Tworzenie sejfów';

  @override
  String get permissionVaultManage => 'Zarządzanie sejfami';

  @override
  String get permissionAgentManage => 'Zarządzanie agentami';

  @override
  String get permissionGrantManage => 'Zarządzanie dostępami';

  @override
  String get permissionAuditView => 'Wyświetlanie dzienników audytu';

  @override
  String get permissionMultipleVaults => 'Wiele sejfów';

  @override
  String get permissionReadApiKey => 'Wyświetlanie kluczy API';

  @override
  String get permissionWriteApiKey => 'Zarządzanie kluczami API';

  @override
  String get settingsGrantManageCutoverUnavailable =>
      'Nie można jeszcze zmienić uprawnienia do zarządzania dostępami. Nie zapisano zmian roli.';

  @override
  String get privacyManageChoices => 'Zarządzaj zgodami';

  @override
  String get privacyTitle => 'Prywatność';

  @override
  String get privacySubtitle =>
      'Opcjonalne zgody są dobrowolne. Możesz je później zmienić w ustawieniach prywatności.';

  @override
  String get privacyAnalytics => 'Analityka produktu';

  @override
  String get privacyMarketing => 'Marketing e-mailowy';

  @override
  String get privacyContinue => 'Kontynuuj';

  @override
  String get privacyLoadError =>
      'Nie udało się pobrać ustawień prywatności. Analityka pozostaje wyłączona.';

  @override
  String get privacyConflictError =>
      'Ustawienia prywatności zmieniły się na innym urządzeniu. Sprawdź aktualne wybory i zapisz je ponownie, aby potwierdzić.';

  @override
  String get privacySaveError =>
      'Nie udało się potwierdzić wyboru. Analityka w tej aplikacji pozostaje wyłączona. Ponów zapis lub korzystaj dalej z Palladin.';

  @override
  String get privacyMarketingSaveError =>
      'Nie udało się potwierdzić wyboru. Ponów zapis lub korzystaj dalej z Palladin.';

  @override
  String get privacyNoticeUnavailable =>
      'Zapisywanie tych opcjonalnych zgód nie jest jeszcze dostępne. Możesz korzystać z niezbędnych funkcji.';

  @override
  String get privacyLocalActivation =>
      'Zgoda konta obejmuje web i mobile. Analityka wymaga również aktywacji w każdej przeglądarce lub instalacji aplikacji. Cofnięcie zgody wyłącza ją na wszystkich urządzeniach.';

  @override
  String get privacySaving => 'Zapisywanie…';

  @override
  String get privacySaved => 'Zapisano wybór prywatności';

  @override
  String get privacyRetry => 'Ponów zapis';

  @override
  String get privacyUnknown => 'Nie zapisano wyboru';

  @override
  String get privacyGranted => 'Udzielono zgody na koncie';

  @override
  String get privacyDenied => 'Odmówiono zgody';

  @override
  String get privacyWithdrawn => 'Cofnięto zgodę';

  @override
  String get privacyOnboardingTitle => 'Twoja prywatność';

  @override
  String get privacyEssential => 'Niezbędne';

  @override
  String get privacyAlwaysActive => 'Zawsze aktywne';

  @override
  String get privacyEssentialDescription =>
      'Zapewniają działanie podstawowych funkcji i ochronę Twojego konta.';

  @override
  String get privacyAnalyticsDescription =>
      'Opcjonalne pomiary korzystania z funkcji aplikacji.';

  @override
  String get privacyMarketingDescription =>
      'Nowości i oferty Palladin e-mailem.';

  @override
  String get privacyAcceptAll => 'Akceptuj wszystkie';

  @override
  String get privacySaveChoice => 'Zapisz wybór';

  @override
  String get privacyDetails => 'Szczegóły zgody';

  @override
  String get privacyAnalyticsNotice =>
      'Za zgodą mierzymy w PostHog EU korzystanie z funkcji Palladin, aby ulepszać aplikację. Nie zbieramy treści sejfu ani formularzy, haseł lub kluczy i nie nagrywamy sesji. Zgodę możesz wycofać w ustawieniach prywatności.';

  @override
  String get privacyMarketingNotice =>
      'Za zgodą wyślemy Ci e-maile z nowościami i ofertami Palladin. Niezbędne wiadomości transakcyjne, dotyczące konta i bezpieczeństwa wysyłamy niezależnie od tej zgody. Zgodę możesz wycofać w ustawieniach prywatności.';
}
