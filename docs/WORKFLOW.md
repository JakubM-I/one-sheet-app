# Workflow realizacji — one-sheet

## Zasady pracy

1. **Jeden etap naraz.** Nie zaczynaj kolejnego, zanim poprzedni nie przejdzie listy kontrolnej.
2. **Każdy etap kończy się działającą aplikacją.** Po każdym etapie da się uruchomić `./scripts/run.sh`
   i zobaczyć efekt. Nie ma etapów „samego kodu bez widocznego rezultatu".
3. **Po zakończeniu etapu Claude zatrzymuje się** i wykonuje protokół zakończenia etapu
   z [CLAUDE.md](../CLAUDE.md): build + testy, lista kontrolna, plik
   `docs/podsumowania/etap_N_podsumowanie.md`, raport w rozmowie. Weryfikację wizualną wykonuje
   człowiek — Claude nie ocenia sam, czy okno „wygląda dobrze".
4. Zmiana zakresu etapu wymaga aktualizacji tego pliku w tym samym kroku.
5. **Git prowadzi użytkownik.** Praca na gałęzi `dev`; commit po każdym zaakceptowanym etapie
   wykonuje człowiek. Claude nie dotyka repozytorium.

Legenda statusów: `⬜ do zrobienia` · `🟨 w toku` · `✅ ukończony`

---

## Etap 0 — Szkielet i pakowanie ✅

**Cel:** z pustego katalogu do ikony w belce systemowej.

**Zakres**
- `Package.swift` — biblioteka `OneSheetCore` + wykonywalny `OneSheet` + program testowy,
  platforma macOS 26, Swift 6, zero zależności
- struktura katalogów zgodna z CLAUDE.md
- `Resources/Info.plist` z `LSUIElement`
- `scripts/bundle.sh`, `scripts/run.sh`, `scripts/test.sh`
- własny harness testowy (Command Line Tools nie mają XCTest — patrz rejestr decyzji)
- `AppDelegate` + `StatusItemController` z ikoną SF Symbol `note.text`
- klik w ikonę wypisuje wpis do `os.Logger` (jeszcze bez panelu)
- ~~`.gitignore`~~ — utworzony wcześniej, przed inicjalizacją repozytorium

**Definicja ukończenia**
- ✅ `swift build` przechodzi bez ostrzeżeń
- ✅ `./scripts/test.sh` — 4 testy przechodzą
- ✅ `./scripts/run.sh` uruchamia aplikację
- ✅ aplikacja działa jako proces tła (`background only` = `true`), brak ikony w Docku i `⌘Tab`
- ⬜ ikona jest widoczna w belce i poprawnie wygląda w jasnym i ciemnym motywie — **wymaga oczu**
- ⬜ kliknięcia lewym i prawym przyciskiem trafiają do logu — **wymaga oczu**

**Weryfikacja ręczna:** uruchom, spójrz na belkę, kliknij ikonę oboma przyciskami przy otwartym
podglądzie logów, przełącz motyw systemu, zamknij przez `killall OneSheet`.

**Podsumowanie:** [podsumowania/etap_0_podsumowanie.md](podsumowania/etap_0_podsumowanie.md)

---

## Etap 1 — Panel z edytorem ⬜

**Cel:** kliknięcie ikony rozwija okno, w którym można pisać.

**Zakres**
- `NotePanel` z konfiguracją ze specyfikacji (sekcja 3.2)
- `NSVisualEffectView` jako tło, zaokrąglone rogi
- `EditorViewController` z `NSScrollView` + `NSTextView`
- pozycjonowanie panelu pod ikoną, przycięcie do widocznego obszaru ekranu
- toggle: klik w ikonę otwiera/zamyka; `Esc` zamyka — **i nic poza tym**
  (`hidesOnDeactivate = false`, brak reakcji na `windowDidResignKey`)
- `collectionBehavior` pozwalający panelowi trwać na wszystkich biurkach
- fokus w polu tekstu natychmiast po otwarciu
- zapamiętywanie rozmiaru i pozycji (`setFrameAutosaveName`)

**Definicja ukończenia**
- panel otwiera się pod ikoną, także gdy ikona jest przy prawej krawędzi ekranu
- da się pisać bez klikania w pole tekstu
- panel da się przeskalować, nowy rozmiar przeżywa restart aplikacji
- **panel pozostaje otwarty** po kliknięciu w inną aplikację, przełączeniu `⌘Tab`
  i przejściu na inne biurko
- panel nie znika w trakcie pisania i nie kradnie fokusu innym aplikacjom przy starcie

**Ryzyko etapu:** panel nieaktywujący może nie przyjmować klawiatury — jeśli tak, zastosuj plan
awaryjny z sekcji 8 specyfikacji i odnotuj to w tym pliku.

---

## Etap 2 — Trwałość ⬜

**Cel:** treść przeżywa zamknięcie aplikacji.

**Zakres**
- `NoteStore`: `load()`, `scheduleSave(_:)`, `flush()`
- zapis RTFD do `~/Library/Application Support/OneSheet/note.rtfd`
- zapis atomowy przez `replaceItemAt` z `backupItemName`
- debounce 700 ms + twardy limit 5 s
- `flush()` na: terminate, resign active, sleep, power off, schowanie panelu
- odczyt awaryjny: backup → pusty dokument, uszkodzony plik na bok jako `.corrupted-<ts>`
- `state.json` — pozycja kursora i przewinięcia
- testy jednostkowe warstwy `Storage`

**Definicja ukończenia**
- wpisany tekst po `killall -9 OneSheet` (1 s po wpisaniu) jest na miejscu — również wtedy,
  gdy panel przez cały czas pozostawał otwarty (zamknięcie panelu przestało być gwarantem zapisu)
- ręczne uszkodzenie `note.rtfd` powoduje odtworzenie z backupu, nie utratę treści
- ponowne otwarcie panelu przywraca pozycję kursora i przewinięcia
- `swift test` zielony

**Weryfikacja ręczna:** wpisz zdanie, `killall -9 OneSheet`, uruchom ponownie. Powtórz z restartem Maca.

---

## Etap 3 — Formatowanie ⬜

**Cel:** jedyna funkcja aplikacji poza pisaniem.

**Zakres**
- `FormattingCommands` — lokalny monitor `keyDown` aktywny tylko dla `NotePanel`
- pełna tabela skrótów z sekcji 3.3 specyfikacji
- menu kontekstowe z tymi samymi operacjami
- grupowanie operacji w `undoManager`, żeby jedno `⌘Z` cofało całą zmianę
- wklejanie z formatowaniem i `⌥⇧⌘V` bez formatowania
- kolory tekstu wiązane z `.labelColor` — poprawne po zmianie motywu

**Definicja ukończenia**
- każdy skrót z tabeli działa na zaznaczeniu i na `typingAttributes`
- `⌘Z` cofa pojedynczą operację formatowania w całości
- wklejenie fragmentu z Safari zachowuje pogrubienia i kursywę
- żaden skrót nie działa, gdy panel jest zamknięty (sprawdź `⌘B` w innej aplikacji)
- po przełączeniu na ciemny motyw cały tekst pozostaje czytelny

---

## Etap 4 — Integracja z systemem ⬜

**Cel:** aplikacja zachowuje się jak stały element systemu.

**Zakres**
- podpis ad-hoc w `bundle.sh` (warunek działania `SMAppService`)
- `GlobalHotKey` przez `RegisterEventHotKey`, domyślnie `⌥⌘N`, z obsługą błędu rejestracji
- menu kontekstowe ikony: „Uruchamiaj przy logowaniu" (stan z `SMAppService.mainApp.status`),
  „Zakończ"
- `SMAppService.mainApp.register()` / `.unregister()`
- ikona aplikacji `AppIcon.icns`

**Definicja ukończenia**
- `⌥⌘N` otwiera i zamyka panel z dowolnej aplikacji, bez proszenia o uprawnienia
- po włączeniu autostartu i restarcie Maca ikona pojawia się sama
- nieudana rejestracja skrótu nie wywraca aplikacji, tylko wyłącza funkcję z komunikatem
- aplikacja widoczna w Ustawieniach systemowych → Elementy logowania

---

## Etap 5 — Hardening ⬜

**Cel:** aplikacja, której można zaufać z jedynym egzemplarzem swoich notatek.

**Zakres**
- test z notatką 50 000 i 200 000 znaków: otwarcie, przewijanie, zapis
- profilowanie czasu otwarcia panelu (cel <150 ms)
- przegląd wszystkich ścieżek błędu w `NoteStore` — żadna nie może kończyć się utratą danych
- zachowanie przy dwóch monitorach i po zmianie rozdzielczości
- zachowanie przy przełączaniu Spaces i w trybie pełnoekranowym innej aplikacji
- usunięcie martwego kodu, ujednolicenie logowania

**Definicja ukończenia**
- wszystkie kryteria akceptacji z [FUNKCJONALNOSCI.md](FUNKCJONALNOSCI.md) spełnione i sprawdzone
- brak ostrzeżeń kompilatora
- `swift test` zielony

---

## Etap 6 — Wykończenie i instalacja ⬜

**Cel:** aplikacja gotowa do codziennego użycia.

**Zakres**
- finalna ikona (belka + Dock/Finder)
- `scripts/install.sh` — kopia `OneSheet.app` do `/Applications`
- krótkie `README.md`: instalacja, skróty, gdzie leżą dane, jak zrobić kopię zapasową
- decyzja o notaryzacji (potrzebna tylko przy przenoszeniu na inny Mac — poza zakresem MVP)

**Definicja ukończenia**
- aplikacja zainstalowana w `/Applications`, uruchamia się przy logowaniu
- tydzień codziennego użycia bez utraty danych i bez ręcznego restartu

---

## Rejestr decyzji

Każde odstępstwo od specyfikacji dopisujemy tutaj — data, decyzja, powód.

| Data | Etap | Decyzja | Powód |
|---|---|---|---|
| 2026-08-04 | — | Rich text (RTFD) zamiast Markdown | formatowanie ma być widoczne, nie składniowe |
| 2026-08-04 | — | SwiftPM + skrypt pakujący zamiast Xcode | na maszynie są tylko Command Line Tools |
| 2026-08-04 | — | `NSPanel` zamiast `NSPopover` | wymagane skalowanie okna przy wklejaniu długich treści |
| 2026-08-04 | — | Panel nie chowa się przy utracie aktywności (`hidesOnDeactivate = false`) | notatnik ma móc stać otwarty obok innej aplikacji; zamyka go tylko świadoma akcja |
| 2026-08-04 | — | Podsumowanie edukacyjne po każdym etapie w `docs/podsumowania/` | dokumentacja ma uczyć, jak działa własna aplikacja, nie tylko raportować postęp |
| 2026-08-04 | 0 | Własny harness testowy zamiast `swift test` | Command Line Tools nie zawierają XCTest ani swift-testing; alternatywą było 10 GB Xcode dla kilkunastu asercji |
| 2026-08-04 | 0 | Podział na bibliotekę `OneSheetCore` + wykonywalny `OneSheet` | symbole targetu wykonywalnego nie linkują się do programu testowego — bez podziału kod jest nietestowalny |
