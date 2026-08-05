# Etap 5 — Hardening — podsumowanie

**Data ukończenia:** 2026-08-05
**Status:** ukończony (czeka na weryfikację ręczną)

## 1. Co powstało

Etap bez nowych funkcji — celowo. Jego produktem jest zaufanie: zmierzony czas otwarcia
panelu, testy notatek na 50 000 i 200 000 znaków, komplet testów ścieżek błędu warstwy
trwałości oraz jedna realna poprawka odporności (panel otwarty na monitorze, który
właśnie zniknął, wsuwa się na ekran, który został). Do tego stanowisko testowe pozwalające
uruchomić aplikację z wygenerowaną długą notatką **bez dotykania prawdziwej notatki**.

## 2. Nowe pliki i ich rola

| Plik | Odpowiedzialność |
|---|---|
| `Tests/OneSheetTests/NoteStoreErrorPathTests.swift` | scenariusze awarii zapisu/odczytu — żaden nie może skończyć się utratą danych |
| `Tests/OneSheetTests/LongNoteFactory.swift` | generator sformatowanej notatki o zadanej długości |
| `Tests/OneSheetTests/LongNoteTests.swift` | zapis/odczyt 50 000 i 200 000 znaków z pomiarem czasu |
| `Tests/OneSheetTests/PanelOpenPerfTests.swift` | pomiar otwarcia panelu z notatką 200 000 znaków (bramkowany, patrz §3) |
| `scripts/longnote_gen.swift` | generator `note.rtfd` dla stanowiska testowego |
| `scripts/longnote_stand.sh` | uruchomienie aplikacji na odizolowanym katalogu danych z długą notatką |

Zmienione: `NotePanel` (pomiar czasu otwarcia w logu, korekta ramki przy zmianie układu
ekranów), `NoteFileLayout` + `AppConfiguration` (przekierowanie katalogu danych zmienną
środowiskową), `GlobalHotKey` (nieaktualny komentarz o `eventHotKeyExistsErr` po
sprostowaniu z etapu 4).

## 3. Jak to działa — mechanizmy

### Pomiar czasu otwarcia panelu

- **Problem:** specyfikacja (sekcja 6) daje budżet 150 ms od wywołania do gotowości na
  pisanie, ale dotąd nikt tego nie mierzył.
- **Rozwiązanie:** `NotePanel.present(below:)` mierzy własny czas `ContinuousClock`
  i wpisuje go do logu (`Panel pokazany w 3.1 ms`). Regresję widać bez profilera, jednym
  `log stream`. Osobny test (`PanelOpenPerfTests`) tworzy prawdziwe okno z notatką
  200 000 znaków i kursorem na końcu, po czym mierzy dwa otwarcia.
- **Wynik pomiaru (2026-08-05, M-series):** pierwsze otwarcie 41 ms, każde kolejne 3 ms.
  Serializacja RTFD: 200 000 znaków — zapis 6,2 ms, odczyt 7,3 ms; 50 000 znaków —
  odpowiednio 1,7 ms i 1,9 ms. Budżet 150 ms ma zapas rzędu wielkości.
- **Dlaczego pierwsze otwarcie jest droższe:** TextKit 2 rozkłada tekst leniwie.
  Pierwsze pokazanie panelu wykonuje `scrollRangeToVisible` do zapamiętanego kursora
  (etap 2), więc płaci za rozłożenie tekstu od początku dokumentu do kursora — raz.
  Kolejne otwarcia to czyste `orderFrontRegardless()` gotowego okna.
- **Na co uważać:** suita z prawdziwym oknem wymaga serwera okien i mignie panelem na
  ekranie, więc jest bramkowana cechą `.enabled(if:)` — uruchamia się tylko przez
  `ONESHEET_PANEL_PERF=1 ./scripts/test.sh`. Zwykły przebieg testów pozostaje bezokienny.

### Przegląd ścieżek błędu w `NoteStore` — wnioski

Przegląd nie znalazł ścieżki kończącej się utratą danych. Niezmienniki, na których to
stoi (wszystkie od etapu 2, teraz domknięte testami):

1. **Na dysku nigdy nie ma niekompletnej notatki.** Nowa wersja powstaje w pliku
   roboczym obok, a podmiana to jedno `FileManager.replaceItemAt(...)`.
2. **Nieudany zapis niczego nie rusza.** Serializacja i zapis roboczy dzieją się przed
   jakimkolwiek dotknięciem `note.rtfd`; błąd zostawia poprzednią wersję w całości.
3. **Niezapisana treść nie przepada po błędzie.** `pendingText` jest czyszczony dopiero
   po udanym zapisie — ponowną próbę wykonuje następna zmiana **albo sam `flush()`**
   (schowanie panelu, uśpienie, zakończenie aplikacji), bez potrzeby nowej edycji.
4. **Nieczytelny plik nigdy nie jest kasowany ani nadpisywany.** Notatka idzie do
   kwarantanny `note.rtfd.corrupted-<znacznik>`, a kolizja nazw w tej samej sekundzie
   dostaje licznik. Nieczytelna kopia zapasowa zostaje na miejscu.

Nowe testy pokrywają: zapis do katalogu tylko-do-odczytu (uprawnienia `0o555` jako
symulacja pełnego dysku), dokończenie zaległego zapisu samym `flush()`, plik roboczy
osierocony przez ubity proces, rotację kopii zapasowej przy trzecim zapisie, oba pliki
nieczytelne naraz i kolizję nazw kwarantanny.

### Odizolowany katalog danych — `ONESHEET_DATA_DIRECTORY`

- **Problem:** test „otwórz aplikację z notatką 200 000 znaków" wymaga podmiany notatki,
  a zasada nr 1 projektu brzmi: prawdziwej notatki nie wolno ryzykować.
- **Rozwiązanie:** `NoteFileLayout.applicationSupport()` honoruje zmienną środowiskową
  `ONESHEET_DATA_DIRECTORY` i wtedy cały katalog danych żyje we wskazanym miejscu.
  Stanowisko `scripts/longnote_stand.sh` generuje tam notatkę i uruchamia aplikację.
- **Dlaczego tak, a nie podmiana `HOME`:** pomiar pokazał, że na macOS 26
  `FileManager.urls(for: .applicationSupportDirectory, ...)` i `NSHomeDirectory()`
  **ignorują zmienną `HOME`** — katalog domowy pochodzi z bazy użytkowników
  (`getpwuid`), więc klasyczna sztuczka z `HOME=/tmp/...` po cichu nic nie robi.
  Pierwsza wersja stanowiska właśnie tak zawiodła: aplikacja wczytała prawdziwą notatkę.
- **Na co uważać:** binarkę trzeba uruchomić bezpośrednio
  (`OneSheet.app/Contents/MacOS/OneSheet`), nie przez `open` — LaunchServices nie
  przekazuje zmiennych środowiskowych procesowi potomnemu. Druga pułapka: proces
  w tle dziedziczy stdout skryptu, więc bez `>/dev/null` trzyma otwarty potok
  każdego, kto czyta wyjście stanowiska.

### Korekta ramki przy zmianie układu ekranów

- **Problem:** korekta ramki działała tylko przy **pokazywaniu** panelu
  (`positionBeforeShowing`). Panel stojący otwarty na monitorze, który został odłączony
  (albo zmienił rozdzielczość), mógł zostać poza wszystkimi ekranami.
- **Rozwiązanie:** nasłuch `NSApplication.didChangeScreenParametersNotification`;
  gdy panel jest widoczny, ramka przechodzi przez to samo `PanelGeometry.clamped(_:to:)`
  co przy pokazywaniu. `NSWindow.screen` bywa wtedy `nil` (okno poza wszystkimi
  ekranami — dokładnie ten przypadek), więc awaryjnie celujemy w `NSScreen.main`.
- **Dlaczego tak:** logika przycinania już istniała i była pod testami — dopisany został
  wyłącznie moment jej wywołania. Zero nowej arytmetyki, zero nowych przypadków brzegowych.

## 4. Decyzje i odstępstwa od planu

Trzy wpisy dopisane do rejestru decyzji w [WORKFLOW.md](../WORKFLOW.md):
zmienna `ONESHEET_DATA_DIRECTORY` (podmiana `HOME` nie działa na macOS 26),
korekta ramki na `didChangeScreenParametersNotification` (domknięcie scenariusza
z otwartym panelem) oraz bramkowanie suity okiennej zmienną `ONESHEET_PANEL_PERF`.

## 5. Testy

- **Automatyczne:** 59 testów w 10 suitach, wszystkie zielone (`./scripts/test.sh`);
  do tego bramkowana suita otwarcia panelu (`ONESHEET_PANEL_PERF=1`), też zielona.
  Czysta przebudowa od zera bez ostrzeżeń kompilatora.
- **Sprawdzone przeze mnie:**
  - zapis/odczyt 200 000 znaków w pojedynczych milisekundach (czasy w §3),
  - otwarcie panelu 41 ms / 3 ms — mieści się w budżecie 150 ms z zapasem,
  - stanowisko `longnote_stand.sh` uruchamia aplikację, która wczytuje wygenerowane
    200 000 znaków (potwierdzone wpisem `Notatka wczytana (200000 znaków)` w logu),
  - katalog danych po testach zawiera wyłącznie `note.rtfd`, `note.rtfd.backup`
    i `state.json` (kryterium akceptacji nr 6 — pod testem `leavesNoTemporaryFile`).
- **Wymaga weryfikacji przez Ciebie** (lista też w WORKFLOW):
  - płynność przewijania notatki 200 000 znaków — stanowisko zostało uruchomione,
    wystarczy kliknąć ikonę w belce; powrót: `killall OneSheet && ./scripts/run.sh`,
  - czas otwarcia panelu na żywo — wpis `Panel pokazany w X ms` w `log stream`,
  - dwa monitory: otwarcie panelu na drugim ekranie, odłączenie go przy otwartym
    i przy schowanym panelu, zmiana rozdzielczości przy otwartym panelu,
  - Spaces i pełny ekran: panel ma być widoczny na każdym biurku i nad aplikacją
    w trybie pełnoekranowym (konfiguracja z etapu 1, dotąd bez systematycznego testu).

## 6. Napotkane problemy

1. **`HOME` nie działa jako przekierowanie danych** — opisane w §3; skończyło się
   zmienną `ONESHEET_DATA_DIRECTORY` w `NoteFileLayout`.
2. **`log show` nie widzi wpisów poziomu `.info`** — system trzyma je tylko w pamięci
   (dostępne dla `log stream` na żywo), na dysk trafiają dopiero `error`/`fault`.
   Weryfikację startu stanowiska trzeba było robić przez uruchomiony wcześniej
   `log stream`, nie przez `log show --last`.
3. **Stanowisko wieszało czytelnika swojego wyjścia** — proces aplikacji w tle
   dziedziczył stdout skryptu i nie zamykał potoku; naprawione przekierowaniem
   do `/dev/null` + `disown`.

## 7. Dług techniczny

- Ponowna próba po nieudanym zapisie następuje przy kolejnej zmianie albo kolejnym
  `flush()` — nie ma zegara ponawiającego w tle. Świadome: momenty `flush()` (schowanie
  panelu, uśpienie, wylogowanie, zakończenie) są dostatecznie gęste, a pętla ponawiania
  przy pełnym dysku kosztowałaby więcej, niż daje.
- Suita `PanelOpenPerfTests` nie jest częścią zwykłego przebiegu testów — wymaga
  ręcznego `ONESHEET_PANEL_PERF=1`. Cena za bezokienny przebieg domyślny.

## 8. Co dalej

Etap 6 — wykończenie i instalacja: finalna ikona, `scripts/install.sh` kopiujący pakiet
do `/Applications`, krótkie `README.md`. Z tego etapu przydadzą się zmierzone liczby
(README może uczciwie napisać, ile aplikacja waży i jak szybko się otwiera) oraz
stanowisko długiej notatki do testu „tydzień codziennego użycia".
