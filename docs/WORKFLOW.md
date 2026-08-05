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
  (`⌘B`, `⌘I`, `⌘U`, `⌘+`/`⌘-`, `⌘{`/`⌘|`, `⌥⇧⌘V`) ⬜ wymagają ręcznego sprawdzenia
- ✅ każda operacja formatowania wyzwala autozapis — ścieżka `didChangeText()` pokryta
  testem licznika `textDidChange`, a mutacje z jej pominięciem łapie nasłuch
  `NSTextStorage.didProcessEditingNotification` (też pod testem)
- ✅ jedno `⌘Z` cofa operację własną w całości — pokryte testem; cofanie operacji
  `NSFontManager` ⬜ do sprawdzenia ręcznie
- ✅ zgodność menu (skróty, wykonawcy, tagi) z tabelą specyfikacji — pod testem `FormatMenu`
- ✅ przekreślenie i `NSTextList` przeżywają serializację RTFD — pod testem
- ✅ wklejenie sformatowanego fragmentu zachowuje formatowanie, łącznie z kolorem tła
  tekstu — potwierdzone przez użytkownika 2026-08-05
- ✅ po przełączeniu na ciemny motyw cały tekst pozostaje czytelny — potwierdzone
  przez użytkownika 2026-08-05
- ✅ znaczniki listy punktowanej rysują się poprawnie — potwierdzone przez użytkownika
  2026-08-05
- ⬜ żaden skrót nie działa, gdy panel jest zamknięty (sprawdź `⌘B` w innej aplikacji) — ręcznie

**Weryfikacja ręczna:** otwórz panel, przejdź skróty z tabeli na zaznaczeniu i przy samym
kursorze, cofnij każdą operację jednym `⌘Z`, wklej sformatowany fragment z Safari, sprawdź
`⌘B` w innej aplikacji przy schowanym panelu, przełącz motyw systemu, zrób listę punktowaną
i dopisz do niej akapit Enterem, na końcu `killall -9 OneSheet` sekundę po pogrubieniu
i sprawdź, że pogrubienie przeżyło restart.

**Podsumowanie:** [podsumowania/etap_3_podsumowanie.md](podsumowania/etap_3_podsumowanie.md)

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
| 2026-08-04 | — | **Wycofanie decyzji z etapu 0**: własny harness zastąpiony przez swift-testing | ustalenie z etapu 0 było błędne. Command Line Tools **zawierają** swift-testing (`Testing.framework` + plugin makr + `lib_TestingInterop.dylib`); brakowało wyłącznie ścieżek, których SwiftPM szuka w katalogu Xcode. Dokłada je `scripts/test.sh`. Zysk: komunikaty `#expect` z wyliczonymi podwyrażeniami, testy tabelaryczne (`arguments:`) pod etap 2, minus 100 linii własnego kodu. Xcode nadal niepotrzebny |
