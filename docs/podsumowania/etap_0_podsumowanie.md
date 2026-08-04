# Etap 0 — Szkielet i pakowanie — podsumowanie

**Data ukończenia:** 2026-08-04
**Status:** ukończony z odstępstwami (dwa — opisane w sekcji 4)

## 1. Co powstało

Aplikacja uruchamia się jako proces tła i tworzy własną ikonę w górnej belce systemowej.
Kliknięcie ikony — lewym i prawym przyciskiem osobno — trafia do systemowego dziennika.
Nie ma jeszcze żadnego okna; to szkielet, na którym stanie panel z etapu 1.

Powstała też infrastruktura, bez której nie da się dalej pracować: budowanie pakietu `.app`
z samych Command Line Tools oraz działający sposób uruchamiania testów.

## 2. Nowe pliki i ich rola

| Plik | Odpowiedzialność |
|---|---|
| `Package.swift` | trzy targety: biblioteka, program, testy |
| `Sources/OneSheet/main.swift` | punkt wejścia — cztery linie uruchamiające pętlę zdarzeń |
| `Sources/OneSheetCore/App/AppDelegate.swift` | cykl życia aplikacji, spinanie komponentów |
| `Sources/OneSheetCore/App/AppConfiguration.swift` | wszystkie stałe konfiguracyjne w jednym miejscu |
| `Sources/OneSheetCore/App/Log.swift` | kategorie `os.Logger` |
| `Sources/OneSheetCore/MenuBar/StatusItemController.swift` | ikona w belce i rozróżnianie kliknięć |
| `Resources/Info.plist` | metadane pakietu, w tym `LSUIElement` |
| `scripts/bundle.sh` | składanie `OneSheet.app` z binarki |
| `scripts/run.sh` | bundle + restart aplikacji |
| `scripts/test.sh` | uruchomienie programu testowego |
| `Tests/OneSheetTests/TestHarness.swift` | własny mini-framework testowy — *skasowany 2026-08-04, patrz sprostowanie w sekcji 4* |
| `Tests/OneSheetTests/main.swift` | rejestr testów — *jw.* |

## 3. Jak to działa — mechanizmy

### Dlaczego binarka to za mało i po co jest `bundle.sh`

- **Problem:** `swift build` produkuje plik wykonywalny. Uruchomiony wprost z terminala nie ma
  `Info.plist`, a więc system nie wie, że to aplikacja bez ikony w Docku, nie zna jej
  identyfikatora ani wersji. `SMAppService` (autostart, etap 4) w ogóle odmówi współpracy
  z czymś, co nie jest pakietem.
- **Rozwiązanie:** `scripts/bundle.sh` ręcznie buduje katalog o strukturze, której oczekuje macOS:

  ```
  OneSheet.app/Contents/
  ├── Info.plist
  ├── MacOS/OneSheet        ← binarka
  └── Resources/            ← ikona (etap 6)
  ```

  Na koniec `codesign --force --sign -` składa podpis ad-hoc (myślnik zamiast nazwy certyfikatu).
  To nie jest podpis deweloperski — wystarcza do uruchamiania lokalnie, ale nie do przenoszenia
  aplikacji na inny Mac.
- **Dlaczego tak:** normalnie robi to Xcode. Skoro go nie ma, robimy to jawnie — przy okazji
  widać dokładnie, z czego składa się aplikacja macOS.
- **Na co uważać:** `open` uruchamia kopię zarejestrowaną w LaunchServices, niekoniecznie tę
  świeżo zbudowaną. Stąd flaga `-n` w `run.sh` (wymuś nową instancję) i `sleep 0.5` po `killall`,
  bo system potrzebuje chwili na zwolnienie poprzedniego procesu.

### Aplikacja bez ikony w Docku — dwa niezależne przełączniki

- **Problem:** aplikacja ma żyć tylko w belce.
- **Rozwiązanie:** ustawiamy to w dwóch miejscach jednocześnie:
  - `LSUIElement = true` w `Info.plist` — czyta to system **przed** uruchomieniem procesu,
    dzięki czemu ikona nigdy nie mignie w Docku;
  - `NSApp.setActivationPolicy(.accessory)` w kodzie — działa też wtedy, gdy binarka zostanie
    uruchomiona z pominięciem pakietu.
- **Na co uważać:** `.accessory` oznacza również **brak menu głównego**. To nie jest drobiazg —
  konsekwencje wychodzą w etapie 3 (skróty `⌘B` nie mogą przyjść z `NSMenuItem`, bo nie ma menu)
  i już teraz (nie ma `⌘Q`, aplikację zatrzymuje się przez `killall OneSheet`).

### Ikona w belce: `NSStatusItem`

- **Problem:** dodać ikonę do belki i odróżnić kliknięcie lewym od prawego.
- **Rozwiązanie:** `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)` tworzy
  pozycję; jej `button` dostaje obraz i akcję. Kluczowe drobiazgi:

  ```swift
  button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: ...)
  button.image?.isTemplate = true                        // system sam koloruje ikonę
  button.sendAction(on: [.leftMouseUp, .rightMouseUp])   // bez tego prawy klik nie dochodzi
  ```

  Rodzaj kliknięcia nie jest przekazywany w argumencie akcji — trzeba go odczytać
  z `NSApp.currentEvent` już w trakcie obsługi.
- **Dlaczego `isTemplate`:** obraz szablonowy traktowany jest jak maska — system sam dobiera
  kolor do jasnego/ciemnego motywu i do podświetlenia belki. Bez tego ikona byłaby czarnym
  kwadratem na ciemnym tle.
- **Na co uważać:** `NSStatusItem` musi mieć żywą referencję. Gdy zostanie zwolniony, ikona
  po prostu znika z belki — bez żadnego błędu. Dlatego trzyma go `AppDelegate`.

### Punkt wejścia bez `@main`

- **Problem:** SwiftPM potrzebuje punktu startu, a AppKit — pętli zdarzeń.
- **Rozwiązanie:** plik `main.swift` z kodem najwyższego poziomu:

  ```swift
  let application = NSApplication.shared
  let applicationDelegate = AppDelegate()
  application.delegate = applicationDelegate
  application.run()
  ```

- **Dlaczego tak, a nie `@main` / `NSApplicationMain`:** `NSApplication.delegate` jest referencją
  **słabą**. Gdyby delegat był lokalną zmienną, zostałby zwolniony natychmiast po ustawieniu
  i aplikacja przestałaby reagować. Zmienna najwyższego poziomu żyje do końca procesu.
- **Bonus:** w Swift 6 kod najwyższego poziomu w `main.swift` jest domyślnie na `@MainActor`,
  więc tworzenie obiektów AppKit jest tu bezpieczne bez żadnych adnotacji.

### Logowanie zamiast `print`

- **Rozwiązanie:** `os.Logger` z subsystemem równym identyfikatorowi pakietu.
- **Dlaczego:** aplikacja uruchomiona przez `open` nie ma terminala — `print` idzie donikąd.
  Wpisy `Logger` trafiają do dziennika systemowego i są widoczne niezależnie od sposobu startu.
- **Na co uważać (dwie pułapki, obie wdepnięte przy weryfikacji):**
  1. `log` to **wbudowane polecenie zsh**. `log show ...` zwraca `too many arguments`.
     Konieczna jest pełna ścieżka `/usr/bin/log`.
  2. Wpisy poziomu `.info` **nie są domyślnie wyświetlane** ani zapisywane na dysk.
     Bez flagi `--info` polecenie zwraca pustkę, co wygląda jak brak logowania.

  Działające polecenie:

  ```
  /usr/bin/log stream --info --predicate 'subsystem == "com.kubam.OneSheet"'
  ```

## 4. Decyzje i odstępstwa od planu

### Odstępstwo 1: własny harness testowy zamiast `swift test`

> **Sprostowanie z 2026-08-04 (po etapie 1): ta diagnoza była błędna i decyzja została wycofana.**
> Command Line Tools **zawierają** swift-testing. `no such module 'Testing'` nie znaczyło „nie ma
> biblioteki", tylko „kompilator nie dostał ścieżki do niej" — SwiftPM szuka jej w katalogu Xcode,
> a CLT trzymają ją w `Library/Developer/Frameworks/`. Po dołożeniu ścieżek w `scripts/test.sh`
> `swift test` działa i harness został skasowany. Szczegóły w rejestrze decyzji
> [WORKFLOW.md](../WORKFLOW.md). Poniższy opis zostawiony jako zapis tego, co wiedzieliśmy
> w etapie 0 — nauka na przyszłość: „moduł nie istnieje" i „linker go nie widzi" to ten sam
> komunikat błędu.

Command Line Tools **nie zawierają** frameworku XCTest ani biblioteki swift-testing — obie są
częścią Xcode. Sprawdzone jedno po drugim: `import XCTest` → `no such module 'XCTest'`,
`import Testing` → `no such module 'Testing'`. W SDK jest wyłącznie prywatny
`XCTestSupport.framework`, nieprzydatny do pisania testów.

Rozważane wyjścia:
- instalacja pełnego Xcode (~10 GB) — odrzucone, poza ustaleniami projektu;
- swift-testing jako zależność SwiftPM — odrzucone, łamie zasadę zera zależności, a generator
  programu testowego na macOS i tak sięga po XCTest;
- **własny harness** — wybrane.

Harness ma ~100 linii: `suite`, `test`, `expect`, `expectEqual`, licznik i kod wyjścia.
Nieudana asercja rzuca wyjątek zamiast przerywać proces, więc jeden zły test nie ukrywa
wyników pozostałych. Koszt: testy trzeba rejestrować ręcznie w `main.swift`, nie ma
równoległości ani integracji z IDE. Przy kilkunastu testach warstwy zapisu to akceptowalne.

### Odstępstwo 2: podział na `OneSheetCore` + `OneSheet`

Specyfikacja zakładała jeden target `OneSheet`. Okazało się to niewykonalne: **symbole targetu
wykonywalnego nie są eksportowane do linkowania**. Program testowy kompilował się poprawnie
(`@testable import` widzi deklaracje), ale linker kończył pracę błędem:

```
Undefined symbols for architecture arm64:
  "OneSheet.AppConfiguration.bundleIdentifier..." referenced from: _OneSheetTests_main
```

Rozwiązanie to standardowy układ dla aplikacji Swift: cała logika w bibliotece `OneSheetCore`,
target wykonywalny to czterolinijkowy `main.swift`, testy zależą od biblioteki. Publiczny
w bibliotece jest wyłącznie `AppDelegate` — reszta pozostaje wewnętrzna i jest dostępna
testom przez `@testable import`.

**Konsekwencja na przyszłość:** kod dopisany do `Sources/OneSheet/` będzie nietestowalny.
Zasada trafiła do CLAUDE.md.

## 5. Testy

**Automatyczne** — 4 testy, wszystkie przechodzą (`./scripts/test.sh`).

Sprawdzają zgodność `Info.plist` z konfiguracją w kodzie: identyfikator pakietu, nazwę binarki,
`LSUIElement` i minimalną wersję systemu. To nie jest test dla samego testu — rozjazd
identyfikatora między plistem a `AppConfiguration` nie daje żadnego błędu kompilacji, a cicho
psuje autostart w etapie 4. Podobnie literówka w `CFBundleExecutable` objawia się dopiero jako
odmowa uruchomienia gotowego pakietu.

**Sprawdzone automatycznie:**
- `swift build` — bez ostrzeżeń i błędów
- aplikacja startuje i utrzymuje się w pamięci (`pgrep -x OneSheet`)
- działa jako proces tła: zapytanie do System Events o `background only` zwraca `true`,
  co potwierdza brak ikony w Docku i nieobecność w `⌘Tab`
- w dzienniku pojawiają się wpisy `Ikona statusu utworzona (symbol: note.text)`
  oraz `Aplikacja uruchomiona` — czyli `NSStatusItem` powstał bez błędu

**Wymaga weryfikacji przez Ciebie** (zrzut ekranu jest zablokowany brakiem uprawnienia
Screen Recording, więc wyglądu nie sprawdzę):
1. ikona `note.text` jest widoczna w prawej części belki;
2. wygląda poprawnie w jasnym i ciemnym motywie (przełącz w Ustawieniach → Wygląd);
3. przy otwartym podglądzie logów kliknięcie lewym daje wpis `togglePanel()`,
   a prawym — `showContextMenu()`.

Polecenie do punktu 3, w osobnym oknie terminala:

```bash
/usr/bin/log stream --info --predicate 'subsystem == "com.kubam.OneSheet"'
```

## 6. Napotkane problemy

| Problem | Przyczyna | Rozwiązanie |
|---|---|---|
| `no such module 'XCTest'` | CLT nie zawierają XCTest | własny harness (odstępstwo 1) |
| `no such module 'Testing'` | CLT nie zawierają swift-testing | jw. |
| Błąd linkowania programu testowego | symbole targetu wykonywalnego nie są eksportowane | podział na bibliotekę (odstępstwo 2) |
| `log show` → `too many arguments` | `log` jest wbudowanym poleceniem zsh | pełna ścieżka `/usr/bin/log` |
| Puste logi mimo działającej aplikacji | poziom `.info` nie jest domyślnie pokazywany | flaga `--info` |
| Brak zrzutu ekranu belki | brak uprawnienia Screen Recording dla procesu | weryfikacja wizualna po stronie człowieka |

Ostrzeżenie linkera o `SwiftUICore.tbd` pojawiło się przy nieudanej próbie linkowania i zniknęło
po podziale na targety. Nie wymaga działania.

## 7. Dług techniczny

- Brak ikony aplikacji (`AppIcon.icns`) — `bundle.sh` obsługuje jej brak, powstanie w etapie 6.
- Brak sposobu zamknięcia aplikacji z interfejsu — pozycja „Zakończ" powstaje w etapie 4,
  do tego czasu `killall OneSheet`.
- Podpis ad-hoc bez `--options runtime` — hardened runtime dokładamy w etapie 4, razem
  z `SMAppService`, gdzie faktycznie zaczyna mieć znaczenie.
- `AppDelegate.togglePanel()` i `showContextMenu()` tylko logują — to zamierzone zaślepki
  z adnotacją, w którym etapie zostaną wypełnione.

## 8. Co dalej

Etap 1 buduje `NotePanel` i podpina go pod `onPrimaryAction`. Dwie rzeczy z tego etapu na niego
wpływają. Po pierwsze, brak menu głównego wynikający z `.accessory` — panel musi przyjmować
klawiaturę bez aktywowania aplikacji, a to jest główne ryzyko etapu 1, zapisane
w specyfikacji. Po drugie, w maszynie są dwa ekrany o różnej rozdzielczości
(2560×1664 Retina i 3440×1440), więc pozycjonowanie panelu pod ikoną trzeba od razu sprawdzić
na obu, a nie dopiero w etapie 5.
