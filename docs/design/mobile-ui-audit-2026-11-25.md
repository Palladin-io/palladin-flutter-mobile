# Mobile UI — audyt spójności, 2026-11-25

Status: właściciel zaakceptował poprawki; wdrożono lokalnie po punkcie powrotu `fcac3107`.
Źródło: aktualny worktree `design/mobile-ui-alignment`, podgląd `3a3ca519390c`.

## Zakres i jakość dowodów

Przegląd przekrojowy kodu stron, tabów, formularzy i komponentów. Wizualnie
potwierdzone w podglądzie 390×844: Home, lista i detale API keys, Team/lista
i role członka, Vault/lista/Settings/Members, Entry/Details/History, Inbox
i Approve request. W jasnym motywie sprawdzono także Security. Nie jest to pełny
przegląd każdej kombinacji stanu, języka, powiększenia tekstu i motywu.
Natywne ekrany biometrii, aparatu, AutoFill i systemowych pickerów wymagają urządzenia.

## Ustalone wzorce

- Prosta lista A dla zasobów; Inbox pozostaje kartami z akcjami.
- Entry Details: label nad wartością, neutralna powierzchnia, pełne separatory.
- CompactDangerZone: neutralna ramka, inline nagłówek, akcja po prawej.
- Neutralna obwódka aktywnych tabów; czerwony pozostaje primary/licznikiem.
- Formy Add/Edit pełnoekranowe, wspólny pinned Save; FAB jak Entries Add.
- Symetria to wspólne osie i konsekwentny rytm, nie identyczna wysokość każdego rodzaju kontrolki.

## Potwierdzone rozbieżności i proponowane decyzje

| ID | Miejsce / dowód | Problem | Propozycja |
|---|---|---|---|
| 01 | Entry Sharing, `entry_sharing_tab.dart:414,450` | Padding scrolla zawiera 16dp nad FAB, ale KAŻDA karta, w tym ostatnia, dodaje jeszcze 10dp. Faktyczny koniec karty jest 26dp nad FAB. | Odstęp 10dp tylko pomiędzy kartami; koniec dokładnie według wspólnego clearance. |
| 02 | Entry Details vs Agents/Logs/History; Vault detail wrapper | Details/Sharing startują od 16dp, Agents/Logs/History nadal od 12dp; Vault wrapper także 12dp. | Jeden odstęp 16dp po tabach, jeden właściciel odstępu, bez dodawania go równocześnie w rodzicu i dziecku. |
| 03 | `agent_detail_body.dart:165`, `vault_detail_page.dart:649`, `app_screen.dart` | Część odstępu nad contentem jest poza scrollem. Nawet po przewinięciu zostaje pas, podczas gdy inne taby przewijają padding razem z treścią. | Odstęp wewnątrz scrolla; obszar treści dochodzi do dolnej krawędzi tabów. |
| 04 | `entry_history_tab.dart:108`, `entry_logs_tab.dart:32`, `global_audit_log_page.dart:82`, `vault_members_tab.dart:61` | Stałe 96dp na końcu także tam, gdzie nie ma FAB. Puste doły różnią się od końców zwykłych detali. | Osobno końcowy gap bez FAB i clearance z FAB; systemowy inset liczony raz. |
| 05 | Team, API keys, Permissions, Vault Members | Oddzielne karty i footery nadal konkurują z przyjętą prostą listą A. Team ma datę/role w dodatkowej stopce; zaproszenie ma inną wysokość. | Wspólna lista zasobów; data do detali; wyjątek Inbox zachować. |
| 06 | API key Details, `api_key_details_tab.dart:68` | Nazwa/status powtórzone pod nagłówkiem. Dane w małych poziomych wierszach, bez separatorów jak Entry. | Tożsamość/status w headerze, wspólne read-only rows dla danych. |
| 07 | Nieaktywny API key, `api_key_details_tab.dart:143` | Stary zielony panel, uppercase tytuł, zielone objaśnienie i wypełniony zielony przycisk. Potwierdzone wizualnie. | Neutralna powierzchnia, zwykła typografia, wspólna akcja przywrócenia z zielonym akcentem. |
| 08 | Vault Settings, `vault_settings_tab.dart:81,103` | Edycja w tabie; własny ElevatedButton Save wewnątrz scrolla, nie wspólny footer. Jest też akcja zapisu w nagłówku. | Read-only + Edit FAB → pełny formularz, jak Entry/Agent. |
| 09 | Team member / Permission role | Detale są od razu edytowalne z wielkim disabled Save na dole. W Team CheckboxListTile ma wyraźnie większy tekst niż pola danych. | Decyzja: rozszerzyć read-only + Edit na te zasoby; checkboxy typograficznie dopasować do formularzy. |
| 10 | Role deletion, `permission_role_page.dart:210` | Zwykła pozioma linia + czerwony TextButton zamiast CompactDangerZone. | Wspólny kompaktowy zone, z zachowaniem reguł blokujących usunięcie. |
| 11 | Approve request, `grant_limit_selector.dart` | Time/Uses/Lifetime ma czerwone zaznaczenie, preset czasu neutralne z tickiem; różne rozmiary, odstępy i osie. Widoczna rozrzucona siatka oraz Custom w osobnej środkowej linii. | Jeden język zaznaczenia, regularny układ presetów i pełnowymiarowa kontrolka Custom. Nie zmieniać semantyki akceptacji. |
| 12 | Potwierdzenia deactivate Agent, revoke/delete API key | Własne nagłówki 18sp, duże przerwy i przyciski jeden pod drugim; grant sheets mają 16sp i wspólny footer obok siebie. | Wspólny nagłówek i SheetActionButtons; tekst ostrzeżenia zachować. |
| 13 | Generate API key, `generate_api_key_sheet.dart:317` | Ręczny czerwony banner ostrzegawczy i własny OutlinedButton Copy. | Wspólny WarningZone i AccentButton; zachować ważność ostrzeżenia i one-time-secret flow. |
| 14 | Entry History, `entry_history_tab.dart:249,294` | Inset nagłówka 14dp, pól read-only 16dp; rozwinęta historia dodaje zewnętrzne 14dp wokół własnych padded pól. Restore to FilledButton, Reveal to osobny 32dp wariant. | Wyrównać osie, usunąć podwójny padding; ustalić kompaktowy standard akcji historii. |
| 15 | Agent tabs vs AppDetailTabs | Dwie implementacje podobnego paska. Agent ma padding zależny od tekstu, AppDetailTabs ma jawne 36dp wewnętrzne taby i overflow hint. | Jeden komponent z obsługą disabled/overflow; zachować przyjęty wygląd. |
| 16 | PrimaryButton / AppFab / Vault Save | Primary używa primaryAction; FAB i własny Vault Save używają brandRed. Disabled Primary zachowuje pełne czerwone tło i przygasza tekst; Team Save wciąż mocno dominuje. | Ustalić wspólny odcień CTA i czytelny neutralniejszy disabled; badge nadal czerwony. |
| 17 | Shared Entry actions / CompactDangerZone | Widoczny glyph 18/22dp jest optycznie zbliżony, ale sloty mają tylko ok.26dp; tekst zone13 vs wartość14 i inna wysokość wynikają z innej struktury. | Nie powiększać glyphów; rozdzielić dotykowy obszar od widocznego rozmiaru. Ustalić, czy zone ma być identycznej wysokości co readonly row. |
| 18 | Dokumentacja `mobile-ui-alignment.md`, AGENTS/CLAUDE | Chronologiczne reguły mówią jednocześnie o D i A, red-border/primary Danger i compact neutral, TOTP bez countdown i z countdown. Katalog nadal wspomina duplikaty, które częściowo usunięto. | Jedna bieżąca specyfikacja na początku, historia wyraźnie historyczna. Instrukcje i katalog zsynchronizować dopiero z zaakceptowanymi decyzjami. |

## Obszary bez rekomendacji nowego kierunku

Home i logi: zachować obecną listę i hierarchię resource → agent → by.
Nie powiększać ponownie globalnie paddingu logów. Inbox: zachować zatwierdzone
karty, kompaktowy footer 44dp i semantyczną zieloną akceptację.
Entry Details i Agent Details są wzorcami dla pozostałych detali, ale nie są
certyfikowane jako pozbawione błędów przy długich tekstach i dużej czcionce.
Auth/Unlock mają osobny zatwierdzony background — sama różnica względem canvasu
nie jest błędem. Billing pozostaje jawnym placeholderem, nie rozwijać go w tym audycie.

## Pozostała weryfikacja wizualna przed stwierdzeniem „wszystkie widoki”

Nie zamknięto pełnej macierzy light/dark/PL/EN i stanów empty/loading/error.
Do osobnego przejścia: globalne i filtrowane logi, expanded history, create/edit
wszystkich typów Entry, Sharing create/receiver/protection, pełne Settings
(General/Privacy/Security/roles/invite), archive/trash/import/export,
authentication/onboarding/recovery oraz natywne AutoFill/biometria/aparat.
W tych rodzinach przejrzano strukturę kodu i użycie komponentów; to nie jest
równoznaczne z obejrzeniem wszystkich ekranów w działającej aplikacji.

## Proponowana kolejność decyzji

1. Rytm i geometria: 01–04, 14–15. Bez zmiany wybranego stylu.
2. Przeniesienie istniejących wzorców na resztę: 05–10, 12–13.
3. Osobne decyzje: siatka limitów grantu, disabled primary i optyczna wysokość zone.
4. Po akceptacji porządek dokumentacji; potem realizacja i pełna wizualna macierz.

## Realizacja po akceptacji

- Punkt powrotu: `fcac3107` (pełna wersja przed poprawkami; skan staged Gitleaks czysty).
- Zakres: 18 pozycji powyżej, bez zmian logiki uprawnień/crypto; zachowujemy Inbox i rytm logów.
- Wdrożono 01–16 i 18: rytm scrolla, wspólne listy/pola/taby, pełnoekranową edycję skarbca/członka/roli, wspólne potwierdzenia, neutralną reaktywację i disabled CTA, siatkę limitów oraz aktualny kontrakt komponentów.
- 17: glyphy zachowują przyjęte rozmiary; Copy/Reveal i akcja zone mają 44dp pole dotykowe. Puste pola zachowują wysokość. Zone nie jest sztucznie rozciągany do wysokości wielowierszowego pola — wspólne są osie i rytm.
- Przegląd niezależny: poprawiono retry zapisu skarbca z zachowaniem oczekiwanego metadata, brak shell scope w edycji root, wyścig Delete/Edit roli, oznaczenie właściciela, semantykę odczytu uprawnień, synchronizację disabled tabów oraz uchwyt potwierdzenia.
- Testy: pełny `flutter test --no-pub` z lokalnym `PALLADIN_LIBSODIUM_PATH`: 2599 passed, 2 skipped. Scenariusze obejmują role cancel/save w nested Navigator, Vault network failure → retry → success, disabled tab, potwierdzenia i pola dotykowe. Analyzer czysty; notices check i web preview build przeszły.
- Podgląd: `http://127.0.0.1:5461/?build=f509b931964c`. Sprawdzone wizualnie Team/read/edit/save w dark, API keys/list/details/confirmation w light, Entry Details/TOTP/History oraz Vault Settings. Dane są lokalne i fikcyjne.
- Nie zmieniano wysokości bottom navbar ani geometrii wystającej tarczy. Nie uruchamiano GitHub CI, nie publikowano i nie mergowano.
- Ograniczenie: nie jest to certyfikacja wszystkich kombinacji locale/skali tekstu/stanów ani natywnych powierzchni wymienionych powyżej.
