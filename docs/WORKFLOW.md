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

## Etap 0 — Szkielet i pakowanie ✅ (zweryfikowany)

**Cel:** z pustego katalogu do ikony w belce systemowej.

**Zakres**
- `Package.swift` — biblioteka `OneSheetCore` + wykonywalny `OneSheet` + program testowy,
  platforma macOS 26, Swift 6, zero zależności
- struktura katalogów zgodna z CLAUDE.md
- `Resources/Info.plist` z `LSUIElement`
- `scripts/bundle.sh`, `scripts/run.sh`, `scripts/test.sh`
- ~~własny harness testowy~~ — zastąpiony przez swift-testing 2026-08-04, patrz rejestr decyzji
- `AppDelegate` + `StatusItemController` z ikoną SF Symbol `note.text`
- klik w ikonę wypisuje wpis do `os.Logger` (jeszcze bez panelu)
- ~~`.gitignore`~~ — utworzony wcześniej, przed inicjalizacją repozytorium

**Definicja ukończenia**
- ✅ `swift build` przechodzi bez ostrzeżeń
- ✅ `./scripts/test.sh` — 4 testy przechodzą
- ✅ `./scripts/run.sh` uruchamia aplikację
- ✅ aplikacja działa jako proces tła (`background only` = `true`), brak ikony w Docku i `⌘Tab`
- ✅ ikona jest widoczna w belce i poprawnie wygląda w jasnym i ciemnym motywie — potwierdzone 2026-08-04
- ✅ kliknięcia lewym i prawym przyciskiem trafiają do logu — potwierdzone 2026-08-04

**Weryfikacja ręczna:** uruchom, spójrz na belkę, kliknij ikonę oboma przyciskami przy otwartym
podglądzie logów, przełącz motyw systemu, zamknij przez `killall OneSheet`.

**Podsumowanie:** [podsumowania/etap_0_podsumowanie.md](podsumowania/etap_0_podsumowanie.md)

---

## Etap 1 — Panel z edytorem ✅ (zweryfikowany)

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
- ✅ `swift build` bez ostrzeżeń, `./scripts/test.sh` — 11 testów przechodzi
- ✅ przycinanie ramki do ekranu (prawa i lewa krawędź, panel większy od ekranu, ramka po
  odłączonym monitorze) — pokryte testami `PanelGeometry`
- ✅ panel staje się oknem kluczowym, a pierwszym responderem jest `NSTextView` — sprawdzone
  jednorazowym programem tworzącym prawdziwe okno
- ✅ panel otwiera się pod ikoną, także gdy ikona jest przy prawej krawędzi ekranu — potwierdzone 2026-08-04
- ✅ da się pisać bez klikania w pole tekstu — potwierdzone 2026-08-04
- ✅ panel da się przeskalować, nowy rozmiar przeżywa restart aplikacji — potwierdzone 2026-08-04
- ✅ **panel pozostaje otwarty** po kliknięciu w inną aplikację, przełączeniu `⌘Tab`
  i przejściu na inne biurko — potwierdzone 2026-08-04
- ✅ panel nie znika w trakcie pisania i nie kradnie fokusu innym aplikacjom przy starcie — potwierdzone 2026-08-04
- ✅ wygląd: rozmycie tła, rogi okna, jasny i ciemny motyw — potwierdzone 2026-08-04
  (rozmycie wycofane 2026-08-05 na rzecz jednolitego tła — patrz rejestr decyzji)

**Ryzyko etapu — nie zmaterializowało się.** Panel nieaktywujący (`.nonactivatingPanel`) przyjmuje
klawiaturę bez aktywowania aplikacji. Plan awaryjny z sekcji 8 specyfikacji (`NSApp.activate()`
przy otwarciu) nie był potrzebny i pozostaje niewykorzystany.

**Podsumowanie:** [podsumowania/etap_1_podsumowanie.md](podsumowania/etap_1_podsumowanie.md)

---

## Etap 2 — Trwałość ✅ (zweryfikowany)

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
- ✅ `swift build` od zera bez ostrzeżeń, `./scripts/test.sh` — 27 testów przechodzi
- ✅ wpisany tekst po `SIGKILL` (1,3 s po wpisaniu, bez żadnego `flush`) jest na miejscu —
  sprawdzone na jednorazowym stanowisku testowym uruchamiającym prawdziwy `AppDelegate`
- ✅ uszkodzenie `note.rtfd` powoduje odtworzenie z kopii zapasowej, a uszkodzony plik trafia
  do `note.rtfd.corrupted-<ts>` zamiast zniknąć — sprawdzone na stanowisku testowym
- ✅ ponowne uruchomienie przywraca treść, zaznaczenie i przewinięcie — sprawdzone na
  stanowisku testowym (przewinięcie z dokładnością do ~2,5%, patrz podsumowanie)
- ✅ treść przeżywa `killall -9` przy panelu otwartym przez cały czas — potwierdzone przez
  użytkownika 2026-08-04
- ✅ wklejony fragment zachowuje formatowanie po restarcie aplikacji — potwierdzone
  przez użytkownika 2026-08-04
- ✅ skróty `⌘V`, `⌘C`, `⌘X`, `⌘A`, `⌘Z`, `⇧⌘Z` działają w polu tekstu (defekt wykryty
  przy weryfikacji etapu, naprawiony przez `MainMenu` — patrz rejestr decyzji)
- ✅ treść przeżywa pełny restart Maca — potwierdzone przez użytkownika 2026-08-05
  (notatka z poprzedniego dnia na miejscu po ponownym uruchomieniu komputera i aplikacji)

**Weryfikacja ręczna:** wpisz zdanie, odczekaj sekundę, `killall -9 OneSheet`, uruchom ponownie.
Powtórz bez zamykania panelu i z restartem Maca.

**Podsumowanie:** [podsumowania/etap_2_podsumowanie.md](podsumowania/etap_2_podsumowanie.md)

---

## Etap 3 — Formatowanie ✅ (czeka na weryfikację ręczną)

**Cel:** jedyna funkcja aplikacji poza pisaniem.

**Zakres** — przepisany 2026-08-04 po ustaleniu z etapu 2, że ukryte menu główne działa
(patrz rejestr decyzji i sekcja 3.3 specyfikacji). Zamiast lokalnego monitora `keyDown`:

- rozszerzenie `MainMenu` o menu „Format" z pełną tabelą skrótów z sekcji 3.3 specyfikacji
- standardowe selektory tam, gdzie AppKit je ma (`addFontTrait:`, `modifyFont:`, `underline:`,
  `alignLeft:`, `alignCenter:`, `pasteAsPlainText:`) — bez pisania własnego kodu
- `FormattingCommands` jako obiekt docelowy dla trzech operacji bez odpowiednika w AppKit:
  przekreślenie (`⌃⌘K`), lista punktowana (`⌃⌘L`), usunięcie formatowania (`⌃⌘\`)
- menu kontekstowe budowane z **tych samych** pozycji, żeby lista skrótów i lista pozycji
  nie mogły się rozjechać
- grupowanie operacji w `undoManager`, żeby jedno `⌘Z` cofało całą zmianę
- `⌥⇧⌘V` — wklejenie bez formatowania (zwykłe `⌘V` działa od etapu 2)
- kolory tekstu wiązane z `.labelColor` — poprawne po zmianie motywu

**Definicja ukończenia**
- ✅ `swift build` od zera bez ostrzeżeń, `./scripts/test.sh` — 43 testy przechodzą,
  aplikacja startuje i wczytuje istniejącą notatkę
- ✅ trzy operacje własne (`⌃⌘K`, `⌃⌘L`, `⌃⌘\`) działają na zaznaczeniu i na
  `typingAttributes` — pokryte testami `FormattingCommands`; skróty standardowe
  (`⌘B`, `⌘I`, `⌘U`, `⌘+`/`⌘-`, `⌘{`/`⌘|`, `⌥⇧⌘V`) ✅ potwierdzone przez użytkownika
  2026-08-05
- ✅ każda operacja formatowania wyzwala autozapis — ścieżka `didChangeText()` pokryta
  testem licznika `textDidChange`, a mutacje z jej pominięciem łapie nasłuch
  `NSTextStorage.didProcessEditingNotification` (też pod testem)
- ✅ jedno `⌘Z` cofa operację własną w całości — pokryte testem; cofanie operacji
  `NSFontManager` ✅ potwierdzone przez użytkownika 2026-08-05
- ✅ zgodność menu (skróty, wykonawcy, tagi) z tabelą specyfikacji — pod testem `FormatMenu`
- ✅ przekreślenie i `NSTextList` przeżywają serializację RTFD — pod testem
- ✅ wklejenie sformatowanego fragmentu zachowuje formatowanie, łącznie z kolorem tła
  tekstu — potwierdzone przez użytkownika 2026-08-05
- ✅ po przełączeniu na ciemny motyw cały tekst pozostaje czytelny — potwierdzone
  przez użytkownika 2026-08-05
- ✅ znaczniki listy punktowanej rysują się poprawnie — potwierdzone przez użytkownika
  2026-08-05
- ✅ żaden skrót nie działa, gdy panel jest zamknięty (`⌘B` w innej aplikacji) — potwierdzone
  przez użytkownika 2026-08-05

**Weryfikacja ręczna:** otwórz panel, przejdź skróty z tabeli na zaznaczeniu i przy samym
kursorze, cofnij każdą operację jednym `⌘Z`, wklej sformatowany fragment z Safari, sprawdź
`⌘B` w innej aplikacji przy schowanym panelu, przełącz motyw systemu, zrób listę punktowaną
i dopisz do niej akapit Enterem, na końcu `killall -9 OneSheet` sekundę po pogrubieniu
i sprawdź, że pogrubienie przeżyło restart.

**Podsumowanie:** [podsumowania/etap_3_podsumowanie.md](podsumowania/etap_3_podsumowanie.md)

---

## Etap 4 — Integracja z systemem ✅ (zweryfikowany; restart Maca do sprawdzenia przy okazji)

**Cel:** aplikacja zachowuje się jak stały element systemu.

**Zakres**
- podpis ad-hoc w `bundle.sh` (warunek działania `SMAppService`), uzupełniony
  o `--options runtime` zgodnie ze specyfikacją (sekcja 5)
- `GlobalHotKey` przez `RegisterEventHotKey`, domyślnie `⌥⌘N`, z obsługą błędu rejestracji
- menu kontekstowe ikony: „Uruchamiaj przy logowaniu" (stan z `SMAppService.mainApp.status`),
  „Zakończ"
- `SMAppService.mainApp.register()` / `.unregister()`, autostart domyślnie włączany
  przy pierwszym uruchomieniu
- ikona aplikacji `AppIcon.icns` (wersja robocza z generatora `scripts/make_icon.swift`;
  finalna powstaje w etapie 6)

**Definicja ukończenia**
- ✅ `swift build` od zera bez ostrzeżeń, `./scripts/test.sh` — 49 testów przechodzi,
  aplikacja startuje i wczytuje istniejącą notatkę
- ✅ `⌥⌘N` z innej aplikacji otwiera i chowa panel, kursor od razu w tekście,
  bez proszenia o uprawnienia — potwierdzone przez użytkownika 2026-08-05
- ✅ `SMAppService` przyjął podpis ad-hoc: pierwsze uruchomienie kończy się statusem
  `.enabled` (ryzyko ze specyfikacji sekcja 8 nie zmaterializowało się);
  ✅ ikona pojawia się sama po restarcie Maca — potwierdzone przez użytkownika 2026-08-05
  (szczegóły w liście kontrolnej etapu 6)
- ✅ nieudana rejestracja skrótu nie wywraca aplikacji — ścieżka błędu pod testami
  `GlobalHotKey`; przy okazji pomiar: konflikt z inną aplikacją **nie** objawia się
  błędem rejestracji (patrz rejestr decyzji), więc komunikat w menu to zabezpieczenie
  na wypadek awarii samego API
- ✅ aplikacja widoczna w Ustawieniach systemowych → Elementy logowania — potwierdzone
  przez użytkownika 2026-08-05
- ✅ menu kontekstowe: ptaszek autostartu odpowiada stanowi systemu, przełączenie
  działa w obie strony, „Zakończ" kończy aplikację z zapisem notatki — potwierdzone
  przez użytkownika 2026-08-05
- ✅ robocza ikona aplikacji zaakceptowana (finalna powstaje w etapie 6) — potwierdzone
  przez użytkownika 2026-08-05

**Weryfikacja ręczna:** naciśnij `⌥⌘N` w innej aplikacji (panel się otwiera, drugie
naciśnięcie chowa), kliknij ikonę prawym przyciskiem i przejdź obie pozycje menu,
sprawdź listę w Ustawieniach systemowych → Ogólne → Elementy logowania, wyłącz
i włącz autostart z menu, na końcu zrestartuj Maca i sprawdź, że ikona wróciła sama.

**Podsumowanie:** [podsumowania/etap_4_podsumowanie.md](podsumowania/etap_4_podsumowanie.md)

---

## Etap 5 — Hardening ✅ (zweryfikowany)

**Cel:** aplikacja, której można zaufać z jedynym egzemplarzem swoich notatek.

**Zakres**
- test z notatką 50 000 i 200 000 znaków: otwarcie, przewijanie, zapis — testy `LongNoteTests`
  + stanowisko `scripts/longnote_stand.sh` (odizolowany katalog danych, prawdziwa notatka
  nietknięta)
- profilowanie czasu otwarcia panelu (cel <150 ms) — pomiar w `NotePanel.present` (wpis
  w logu) + bramkowana suita `PanelOpenPerfTests` (`ONESHEET_PANEL_PERF=1 ./scripts/test.sh`)
- przegląd wszystkich ścieżek błędu w `NoteStore` — żadna nie może kończyć się utratą danych;
  wnioski i nowe testy w `NoteStoreErrorPathTests`
- zachowanie przy dwóch monitorach i po zmianie rozdzielczości — dopisana korekta ramki
  na `didChangeScreenParametersNotification` (panel otwarty na odłączanym monitorze)
- zachowanie przy przełączaniu Spaces i w trybie pełnoekranowym innej aplikacji —
  konfiguracja z etapu 1, do potwierdzenia ręcznie
- usunięcie martwego kodu, ujednolicenie logowania — przegląd nie znalazł martwego kodu
  ani `print`; poprawiony nieaktualny komentarz w `GlobalHotKey` (sprostowanie z etapu 4)

**Definicja ukończenia**
- ✅ czysta przebudowa od zera bez ostrzeżeń, `./scripts/test.sh` — 59 testów przechodzi
- ✅ zapis/odczyt RTFD zmierzony: 200 000 znaków — 6,2 ms / 7,3 ms; 50 000 — 1,7 ms / 1,9 ms
- ✅ otwarcie panelu z notatką 200 000 znaków i kursorem na końcu: pierwsze 41 ms
  (jednorazowe rozłożenie tekstu do kursora), kolejne 3 ms — budżet 150 ms z zapasem
- ✅ ścieżki błędu pod testami: zapis na katalogu tylko-do-odczytu nie rusza notatki,
  zaległy zapis dokańcza sam `flush()`, osierocony plik roboczy nie blokuje zapisu,
  kopia zapasowa rotuje, oba pliki nieczytelne → pusta kartka bez kasowania czegokolwiek,
  kwarantanna bez kolizji nazw
- ✅ stanowisko długiej notatki działa: aplikacja wczytała wygenerowane 200 000 znaków
  (wpis w logu), katalog użytkownika nietknięty
- kryteria akceptacji z [FUNKCJONALNOSCI.md](FUNKCJONALNOSCI.md): nr 3 i 4 potwierdzone
  w etapach 2–3, nr 2 zmierzone wyżej; nr 1 (ikona po restarcie Maca) — wciąż czeka na
  najbliższy restart; nr 5 (przewijanie 50 000+ bez zacięć) i nr 6 — patrz niżej
- ✅ płynność przewijania notatki 200 000 znaków na stanowisku — potwierdzone przez
  użytkownika 2026-08-05
- ✅ dwa monitory: panel otwierany na drugim ekranie — sprawdzone przez użytkownika
  2026-08-05 przy weryfikacji etapu 6. Wykryło defekt pozycjonowania (panel lądował przy
  krawędzi zamiast pod ikoną), naprawiony przez `PanelGeometry.presentationFrame`;
  pozycja po naprawie potwierdzona
- ✅ Spaces i pełny ekran innej aplikacji — panel pozostaje widoczny; potwierdzone przez
  użytkownika 2026-08-05

**Weryfikacja ręczna:** `./scripts/longnote_stand.sh`, klik w ikonę, przewiń notatkę od
początku do końca (płynność), wpisz coś na końcu; `log stream` pokaże `Panel pokazany
w X ms`. Potem `killall OneSheet && ./scripts/run.sh` (powrót do prawdziwej notatki),
przełącz Spaces z otwartym panelem, wejdź inną aplikacją w pełny ekran, podłącz drugi
monitor: otwórz panel na nim, odłącz kabel, sprawdź, że panel wskoczył na główny ekran.

**Podsumowanie:** [podsumowania/etap_5_podsumowanie.md](podsumowania/etap_5_podsumowanie.md)

---

## Etap 6 — Wykończenie i instalacja ✅ (czeka na weryfikację ręczną)

**Cel:** aplikacja gotowa do codziennego użycia.

**Zakres**
- finalna ikona (belka + Dock/Finder) — belka zostaje przy szablonowym SF Symbol `note.text`
  (decyzja z etapu 0, wygląd potwierdzony); finalna ikona Findera/Elementów logowania
  z przepisanego generatora `scripts/make_icon.swift`: pełna siatka ikon macOS, kształt maski
  z `RoundedRectangle(style: .continuous)`
- `scripts/install.sh` — build release + podmiana kopii w `/Applications` + uruchomienie
- **rozszerzenie zakresu (2026-08-05):** `LaunchAtLogin.reconcileOnLaunch()` — ponowna
  rejestracja autostartu po przeniesieniu pakietu. Bez tego logowanie uruchamiałoby kopię
  z repozytorium: wpis login item trzyma ścieżkę, a `SMAppService.mainApp.status` przeprowadzki
  nie wykrywa (pomiary w rejestrze decyzji i specyfikacji, sekcja 4)
- krótkie `README.md`: instalacja, skróty, gdzie leżą dane, jak zrobić kopię zapasową
- decyzja o notaryzacji: **poza zakresem MVP** — ad-hoc wystarcza na maszynie, na której
  zbudowano; wpis w rejestrze decyzji i w specyfikacji, sekcja 5

**Definicja ukończenia**
- ✅ czysta przebudowa bez ostrzeżeń, `./scripts/test.sh` — 65 testów przechodzi
  (6 nowych: decyzja naprawy rejestracji autostartu)
- ✅ aplikacja zainstalowana przez `./scripts/install.sh` w `/Applications` i uruchomiona
  stamtąd; wpis autostartu w bazie systemu (`sfltool dumpbtm`) wskazuje
  `/Applications/OneSheet.app` — sprawdzone na żywym systemie 2026-08-05
- ✅ finalna ikona zaakceptowana wizualnie (Finder, `/Applications`) — potwierdzone przez
  użytkownika 2026-08-05
- ✅ zaległa weryfikacja z etapu 5: dwa monitory, Spaces, pełny ekran innej aplikacji —
  potwierdzone przez użytkownika 2026-08-05. Po drodze dwie poprawki pozycjonowania panelu
  (zakotwiczenie po zmianie monitora i wyrównanie do lewej krawędzi ikony) — patrz rejestr
  decyzji; pozycja po zmianach zaakceptowana
- ✅ ikona pojawia się sama po restarcie Maca, już z kopii w `/Applications` — potwierdzone
  przez użytkownika 2026-08-05. Restart odbył się na wersji z paskiem formatowania:
  autostart zadziałał, notatka wczytała się w całości, aplikacja wstała prawidłowo.
  Domyka zaległość z etapu 4
- ⬜ tydzień codziennego użycia bez utraty danych i bez ręcznego restartu

**Weryfikacja ręczna:** `./scripts/install.sh`, obejrzyj ikonę w Finderze (`/Applications`)
i w Ustawieniach → Elementy logowania, przejdź smoke test z CLAUDE.md na zainstalowanej
kopii, zrestartuj Maca i sprawdź, że ikona wróciła sama; potem po prostu używaj przez tydzień.

**Podsumowanie:** [podsumowania/etap_6_podsumowanie.md](podsumowania/etap_6_podsumowanie.md)

---

## Zmiany po zamknięciu planu

Plan sześciu etapów jest zakończony. Zmiany wprowadzone później nie są etapami — nie mają
listy kontrolnej ani kolejności — ale obowiązuje je ta sama zasada: każde odstępstwo trafia
do rejestru decyzji, a zmiana warta wyjaśnienia dostaje podsumowanie.

### Pasek formatowania — 2026-08-05

Sześć przycisków nad polem tekstu, scalonych z pasem do przeciągania okna. **Zmiana zakresu:**
`FUNKCJONALNOSCI.md` mówiło wcześniej „bez pasków narzędzi".

- ✅ komplet przycisków, odzwierciedlanie stanu, kliknięcie — 8 testów w `FormatBarTests`
- ✅ geometria i trafienia po scaleniu — pomiar `hitTest` i współrzędnych
- ✅ działanie przycisków, wyśrodkowanie, przeciąganie okna za pasek oraz skalowanie za górną
  krawędź — potwierdzone przez użytkownika 2026-08-05

**Podsumowanie:**
[podsumowania/dodatek_pasek_formatowania_podsumowanie.md](podsumowania/dodatek_pasek_formatowania_podsumowanie.md)

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
| 2026-08-04 | 1 | Zaokrąglenie rogów zostawione systemowi zamiast `cornerRadius = 12` na `NSVisualEffectView` | okno `.titled` jest już przycinane do kształtu okna, a macOS 26 ma własny promień; ręczne 12 pt obcinałoby zawartość wewnątrz zaokrąglonego okna (jasny włos przy krawędzi albo podwójny łuk). Wygląd potwierdzony wizualnie 2026-08-04 — decyzja ostateczna |
| 2026-08-04 | 1 | Geometria panelu wydzielona do `PanelGeometry` | program testowy działa bez serwera okien; bez wydzielenia pozycjonowanie byłoby weryfikowalne wyłącznie okiem |
| 2026-08-04 | 2 | `NoteStore.load()` zwraca `LoadedNote` (treść + stan), nie samo `NSAttributedString` | szkic API w specyfikacji powstał przed decyzją o `state.json`; pozycja kursora jest potrzebna dokładnie w tym samym momencie co treść |
| 2026-08-04 | 2 | Osobne `scheduleSave(_:state:)` i `scheduleStateSave(_:)` | przewijanie długiej notatki generuje dziesiątki zdarzeń na sekundę; wspólna droga oznaczałaby ponowną serializację całego RTFD przy każdym ruchu kółka myszy |
| 2026-08-04 | 2 | Przewinięcie przywracane przy pierwszym pokazaniu panelu, nie przy wczytaniu notatki | TextKit 2 rozkłada tekst leniwie — dopóki panel nie był pokazany, `NSTextView` ma wysokość kilkuset punktów i przewinięcie o 6000 pt zostaje przycięte |
| 2026-08-04 | 2 | **Sprostowanie specyfikacji, sekcja 3.3**: aplikacja `.accessory` **ma** działające `NSMenuItem.keyEquivalent` | zdanie o braku menu głównego było błędne i kosztowało działające `⌘V`, `⌘C`, `⌘X`, `⌘A`, `⌘Z`. Aplikacja nie ma **paska** menu, ale `NSApp.mainMenu` istnieje jako obiekt i `sendEvent(_:)` odpytuje go przez `performKeyEquivalent`. Pomiar: bez menu `⌘A` zaznacza 0 z 15 znaków, z menu — 15 z 15 |
| 2026-08-04 | 2 | Dołożenie `MainMenu` (menu „Edycja") poza pierwotnym zakresem etapu 2 | skróty edycyjne są w zakresie z FUNKCJONALNOSCI sekcja 3, a bez nich nie da się przejść kryterium „wklej fragment z Safari" z klawiatury. Naprawa defektu, nie nowa funkcja |
| 2026-08-04 | 3 | Etap 3 przepisany z lokalnego monitora `keyDown` na rozszerzenie ukrytego menu głównego | konsekwencja sprostowania powyżej. Zysk: standardowe selektory AppKit zamiast własnego kodu, jedno źródło dla skrótów i menu kontekstowego, oraz zniknięcie ryzyka „monitor przechwytuje skróty innych aplikacji" z sekcji 8 specyfikacji |
| 2026-08-05 | 3 | Tło panelu jednolite (`NSWindow.backgroundColor = .textBackgroundColor`, okno nieprzezroczyste) zamiast szkła `NSVisualEffectView` — **zmiana decyzji z etapu 1** | rozmycie przepuszczało zawartość spod okna i psuło czytelność notatki, zwłaszcza w jasnym motywie; zgłoszone przez użytkownika przy weryfikacji etapu 3 |
| 2026-08-05 | 3 | Pozycje formatowania w menu kontekstowym jako podmenu „Formatowanie", nie luzem | systemowe menu kontekstowe `NSTextView` ma kilkanaście pozycji, a AppKit własne grupy (Font, Substitutions) też trzyma w podmenu; źródło pozycji pozostaje jedno (`FormatMenu`) |
| 2026-08-05 | 3 | `usesAdaptiveColorMappingForDarkAppearance = true` — poza literalnym zakresem etapu | kryterium „po przełączeniu na ciemny motyw cały tekst pozostaje czytelny" jest nie do spełnienia dla tekstu wklejonego z jasnych stron (stały czarny kolor); mapowanie odwraca kolory tylko przy rysowaniu, w pliku zostają oryginalne |
| 2026-08-05 | 3 | Autozapis formatowania: obok `textDidChange` nasłuch `NSTextStorage.didProcessEditingNotification` filtrowany do edycji samych atrybutów | operacje `NSFontManager` i cofnięcie formatowania mutują `NSTextStorage` bez gwarancji przejścia przez `didChangeText()`; nasłuch magazynu łapie każdą mutację atrybutów niezależnie od drogi, którą przyszła |
| 2026-08-05 | 4 | **Sprostowanie ryzyka ze specyfikacji, sekcja 8**: „skrót zajęty przez inną aplikację" nie powoduje błędu rejestracji | pomiar: `RegisterEventHotKey` dla `⌥⌘N` w drugim procesie zwraca `noErr`, gdy OneSheet już trzyma tę kombinację — system dopuszcza duplikaty między procesami i sam rozstrzyga doręczanie. `eventHotKeyExistsErr` dotyczy tylko duplikatu w obrębie jednego procesu. Obsługa błędu zostaje jako zabezpieczenie przed awarią samego API |
| 2026-08-05 | 4 | Ikona `AppIcon.icns` generowana skryptem `scripts/make_icon.swift` (AppKit + `iconutil`), nie ręcznie w edytorze graficznym | na maszynie nie ma Xcode ani narzędzi graficznych; `iconutil` i `NSBitmapImageRep` są częścią systemu, a wersja z generatora wystarcza do etapu 6, w którym powstanie finalna ikona |
| 2026-08-05 | 5 | Zmienna środowiskowa `ONESHEET_DATA_DIRECTORY` przekierowuje katalog danych (`NoteFileLayout`) | stanowisko testu długiej notatki nie może ryzykować prawdziwej notatki, a podmiana `HOME` nie działa: na macOS 26 `FileManager` wyznacza katalog domowy z bazy użytkowników i ignoruje zmienną — sprawdzone pomiarem. Do tego `open` nie przekazuje zmiennych środowiskowych, stąd stanowisko uruchamia binarkę bezpośrednio |
| 2026-08-05 | 5 | Korekta ramki panelu przy `NSApplication.didChangeScreenParametersNotification` | dotąd ramka była przycinana tylko przy pokazywaniu panelu; panel stojący otwarty na odłączanym monitorze mógł zostać poza wszystkimi ekranami. Wywoływana jest istniejąca, przetestowana `PanelGeometry.clamped(_:to:)` — zero nowej arytmetyki |
| 2026-08-05 | 5 | Suita `PanelOpenPerfTests` bramkowana zmienną `ONESHEET_PANEL_PERF=1` | tworzy prawdziwe okno (wymaga serwera okien, miga panelem na ekranie); zwykły przebieg `./scripts/test.sh` ma pozostać bezokienny |
| 2026-08-05 | 6 | Bez notaryzacji i podpisu Developer ID | aplikacja jest budowana i używana na tej samej maszynie — Gatekeeper nie sprawdza lokalnych buildów; notaryzacja miałaby sens dopiero przy przenoszeniu gotowego pakietu na inny Mac, a wtedy właściwą drogą jest „sklonuj i zbuduj na miejscu" |
| 2026-08-05 | po 6 | Pasek szybkiego formatowania nad polem tekstu — **zmiana zakresu**, FUNKCJONALNOSCI sekcja 2 mówiła „bez pasków narzędzi" | decyzja użytkownika po testach etapu 6: sześć podstawowych operacji było dostępnych wyłącznie pod skrótami i w podmenu menu kontekstowego, czyli dwa kliknięcia i celowanie w listę. Odrzucone alternatywy: pływający pasek nad zaznaczeniem (wzorzec z przeglądarki, nie z macOS; nie działa przy pustym zaznaczeniu, czyli przy włączaniu cechy przed pisaniem) oraz samo spłaszczenie menu kontekstowego (nie usuwa problemu, tylko go skraca). Granica pozostaje ostra: sześć przycisków, bez rozmiaru czcionki i wyrównania |
| 2026-08-05 | po 6 | Pasek przeciągania i pasek ikon scalone w jeden pas 40 pt; `Panel.dragStripHeight` usunięte | dwa osobne pasy wyglądały jak niedokończony interfejs (zgłoszone przez użytkownika). Pasek formatowania leży teraz na obszarze niewidocznego paska tytułu i sam przejmuje przesuwanie okna przez `performDrag(with:)`. Chrome zmalało z 58 do 40 pt, więc panel zyskał 18 pt na tekst. Ryzyko „pasek przechwyci skalowanie za górną krawędź" sprawdzone ręcznie 2026-08-05 — nie występuje: obszar zmiany rozmiaru obsługuje ramka okna, zanim zdarzenie trafi do widoków |
| 2026-08-05 | po 6 | **Sprostowanie założenia z etapu 1**: widok położony pod niewidocznym paskiem tytułu **dostaje** kliknięcia | komentarz przy `dragStripHeight` twierdził, że pod pasem przeciągania „nie dałoby się kliknąć" i na tej podstawie edytor był odsuwany o 28 pt. Pomiar `hitTest` od widoku ramki okna: przycisk umieszczony 6, 14 i 20 pt od górnej krawędzi (przy pasku tytułu wysokim na 32 pt) jest zwracany prawidłowo, a po scaleniu trafienia dochodzą do wszystkich sześciu ikon. Prawdą jest natomiast, że zwykły `NSView` zwraca w `hitTest` siebie i połyka przeciąganie okna — stąd jawne `performDrag` |
| 2026-08-05 | po 6 | Odrzucone `NSToolbar` w stylu `.unifiedCompact` jako sposób scalenia pasków | byłby to natywny sposób na jeden wysoki pas, ale kosztem przebudowy chrome okna (rezygnacja z `.fullSizeContentView`, delegat toolbara, walidacja pozycji, menu dostosowywania). Pomiar trafień pokazał, że wystarczy przesunąć istniejący pasek na obszar paska tytułu — zero nowej maszynerii |
| 2026-08-05 | po 6 | Pasek nie ma własnej logiki formatowania — bierze akcję i cel z `FormatMenu.makeItems(commands:)`, a stan z nowego `FormattingState` | trzy drogi do tej samej operacji (skrót, menu kontekstowe, przycisk) to trzy okazje do rozjazdu. Przy jednym źródle przycisk nie ma jak wykonać czegoś innego niż skrót, a podświetlenie nie ma jak pokazać czegoś innego, niż zrobi kliknięcie. `FormattingState` powstał z prywatnych predykatów `FormattingCommands` — bez wydzielenia „czy włączone" istniałoby w dwóch kopiach |
| 2026-08-05 | 6 | `LaunchAtLogin.reconcileOnLaunch()` — naprawa rejestracji autostartu po przeniesieniu pakietu (rozszerzenie zakresu etapu) | pomiar na żywym systemie: wpis w bazie Background Task Management trzyma **ścieżkę** pakietu, `SMAppService.mainApp.status` z nowej lokalizacji dalej zwraca `.enabled` (dopasowanie po identyfikatorze), a ponowna `register()` aktualizuje wpis w miejscu (ten sam UUID, nowy URL). Bez naprawy logowanie po instalacji uruchamiałoby kopię z repozytorium. Warunki: tylko kopia w `/Applications`, tylko przy statusie `.enabled` — kopia robocza nie kradnie autostartu, a decyzja użytkownika z Ustawień systemowych zostaje uszanowana |
| 2026-08-05 | 6 | Finalna ikona nadal z generatora, kształt maski przez `SwiftUI.RoundedRectangle(style: .continuous).path(in:)` | jedyne publiczne API oddające dokładnie superelipsę Apple; `NSBezierPath(roundedRect:)` daje rogi kołowe, widocznie „twardsze" przy pełnowymiarowej ikonie. Wersja robocza pływała małą kartką na przezroczystym tle — finalna wypełnia siatkę ikon macOS (824/1024, promień ~22,5%) |
| 2026-08-05 | 6 | Zapamiętana ramka panelu obowiązuje tylko na swoim ekranie; otwarcie na innym monitorze zakotwicza panel na nowo pod ikoną (`PanelGeometry.presentationFrame`) | defekt z weryfikacji dwóch monitorów: `clamped(_:to:)` stosowane bezwarunkowo „dociągało" ramkę z wbudowanego ekranu do najbliższej krawędzi zewnętrznego — panel lądował w rogu zamiast pod klikniętą ikoną. Przycinanie zostaje dla ramki częściowo wystającej (ta sama logika co przy odłączonym monitorze traci sens tylko wtedy, gdy ramka w ogóle nie przecina ekranu docelowego) |
| 2026-08-05 | 6 | Panel zaczepiany pod ikoną **wyrównaniem do jej lewej krawędzi**, nie wyśrodkowaniem względem niej | zgłoszenie użytkownika przy weryfikacji dwóch monitorów: wyśrodkowany panel odsuwa się w prawo od ikony i wygląda jak położony przypadkowo. Ikona ma zostać nad rogiem panelu, tak jak przy menu rozwijanym z belki. Margines to ten sam `gap` 6 pt, który dzieli panel od belki — ikona jest wtedy wizualnie wewnątrz panelu, a nie dokładnie w narożniku |
| 2026-08-04 | — | **Wycofanie decyzji z etapu 0**: własny harness zastąpiony przez swift-testing | ustalenie z etapu 0 było błędne. Command Line Tools **zawierają** swift-testing (`Testing.framework` + plugin makr + `lib_TestingInterop.dylib`); brakowało wyłącznie ścieżek, których SwiftPM szuka w katalogu Xcode. Dokłada je `scripts/test.sh`. Zysk: komunikaty `#expect` z wyliczonymi podwyrażeniami, testy tabelaryczne (`arguments:`) pod etap 2, minus 100 linii własnego kodu. Xcode nadal niepotrzebny |
