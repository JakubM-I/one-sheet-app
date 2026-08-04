# Specyfikacja techniczna — one-sheet

## 1. Podstawy

| Parametr | Wartość |
|---|---|
| Nazwa produktu | one-sheet |
| Nazwa bundla | `OneSheet.app` |
| Bundle ID | `com.kubam.OneSheet` |
| Platforma | macOS 26.0+ (Tahoe), arm64 |
| Język | Swift 6.3, tryb ścisłej współbieżności |
| UI | AppKit (`NSStatusItem`, `NSPanel`, `NSTextView`) |
| System budowania | Swift Package Manager + skrypt pakujący |
| Zależności zewnętrzne | brak |
| Sandbox | wyłączony (aplikacja lokalna, niedystrybuowana przez App Store) |

## 2. Dlaczego AppKit, a nie SwiftUI

SwiftUI `TextEditor` nie daje dostępu do tekstu sformatowanego, list, atrybutów akapitu ani do
`NSTextStorage`. `MenuBarExtra` nie pozwala kontrolować pozycji i skalowania panelu ani zachowania
przy utracie aktywności. Cała aplikacja to w praktyce jedno pole tekstu — warstwa SwiftUI byłaby
opakowaniem `NSViewRepresentable` wokół `NSTextView`, czyli kosztem bez korzyści.

**Decyzja:** czysty AppKit, `NSApplicationDelegate`, bez `@main` z SwiftUI.

## 3. Architektura

Cztery moduły, jednokierunkowa zależność: `App → MenuBar → Editor → Storage`.

```
AppDelegate ─────────► StatusItemController
   │                        │  klik / skrót globalny
   │                        ▼
   │                   NotePanel (NSPanel)
   │                        │
   │                        ▼
   │                   EditorViewController
   │                        │  NSTextViewDelegate.textDidChange
   │                        ▼
   └──── flush() ────► NoteStore ──────► dysk (atomowo)
        (terminate,                       ~/Library/Application Support/
         sleep, resign)                   OneSheet/note.rtfd
```

### 3.1 `App/`

- `AppDelegate` — cykl życia, rejestracja obserwatorów systemowych, wymuszanie zapisu.
- `AppConfiguration` — stałe: identyfikatory, domyślny skrót, opóźnienie autozapisu, ścieżki.
  Wszystkie „magiczne liczby" projektu żyją w jednym miejscu.
- Polityka aktywacji: `NSApp.setActivationPolicy(.accessory)` + `LSUIElement = true`
  w `Info.plist`. Brak ikony w Docku, brak udziału w `⌘Tab`.

### 3.2 `MenuBar/`

- `StatusItemController` — tworzy `NSStatusItem` o zmiennej długości, ustawia obraz
  z SF Symbol `note.text` z `isTemplate = true`. Rozróżnia klik lewym (toggle panelu)
  i prawym / `⌃`+klik (menu kontekstowe).
- `NotePanel : NSPanel` — okno panelu.
- `GlobalHotKey` — rejestracja skrótu przez Carbon `RegisterEventHotKey`.

#### Wybór okna: `NSPanel`, nie `NSPopover`

`NSPopover` daje ładny dymek ze strzałką, ale użytkownik nie może go skalować ani przesunąć,
a przy wklejaniu długich treści to blokujące ograniczenie. Wybieramy `NSPanel` z konfiguracją:

- `styleMask`: `[.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel]`
- `titlebarAppearsTransparent = true`, `titleVisibility = .hidden` — wygląd bez paska tytułu,
  ale z zachowaniem skalowania i przeciągania za górną krawędź
- `isFloatingPanel = true`, `level = .floating`, **`hidesOnDeactivate = false`** — panel ma
  przeżyć przełączenie na inną aplikację; chowa go wyłącznie świadoma akcja użytkownika
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` — panel jest widoczny na
  każdym biurku i nie znika przy przejściu innej aplikacji w tryb pełnoekranowy
- `isMovableByWindowBackground = false` (kolizja z zaznaczaniem tekstu); przesuwanie tylko
  za górny pas 28 pt
- `becomesKeyOnlyIfNeeded = false` — panel musi przyjmować klawiaturę bez aktywowania aplikacji
- rozmiar i pozycja przez `setFrameAutosaveName("NotePanel")`, domyślnie 380×480 pt
- pozycjonowanie przy pierwszym otwarciu: wyśrodkowany pod ikoną statusu, z marginesem 6 pt
  poniżej belki, przycięty do widocznego obszaru ekranu (`NSScreen.visibleFrame`)
- tło: `NSVisualEffectView` z materiałem `.popover`, `blendingMode = .behindWindow`,
  zaokrąglenie 12 pt

Zamykanie — **wyłącznie trzy świadome akcje**: `Esc` (przez `cancelOperation(_:)`), ponowne
kliknięcie ikony w belce, globalny skrót. Nie obsługujemy `windowDidResignKey` ani
`windowDidResignMain` jako zamknięcia; panel może stać otwarty obok innych aplikacji dowolnie
długo. Zamknięcie = `orderOut(nil)`, panel nie jest niszczony ani odtwarzany.

Konsekwencja dla zapisu: schowanie panelu przestaje być wiarygodnym momentem zrzutu na dysk —
notatnik potrafi być otwarty tygodniami. Głównym zabezpieczeniem staje się debounce
i `flush()` na `willResignActive` (sekcja 3.4), a nie zamknięcie panelu.

#### Skrót globalny

`NSEvent.addGlobalMonitorForEvents` wymaga uprawnień Accessibility — odpada. Używamy
`RegisterEventHotKey` z Carbon (`HIToolbox`), które działa bez żadnych uprawnień i jest wciąż
wspieranym API na macOS 26. Domyślnie `⌥⌘N` (`kVK_ANSI_N` + `optionKey | cmdKey`).
Kod trzymany za protokołem `HotKeyRegistering`, aby dało się go podmienić bez ruszania reszty.

### 3.3 `Editor/`

- `EditorViewController` — `NSScrollView` + `NSTextView` na całej powierzchni, wcięcie 12 pt.
- Konfiguracja `NSTextView`: `isRichText = true`, `allowsUndo = true`,
  `isAutomaticQuoteSubstitutionEnabled = false` (cudzysłowy typograficzne psują wklejany kod),
  `isContinuousSpellCheckingEnabled = true`, `usesFindBar = false`,
  `textContainer.widthTracksTextView = true`.
- Czcionka domyślna: `NSFont.systemFont(ofSize: 14)`; `typingAttributes` uzupełniane o
  `foregroundColor = .labelColor`, aby tekst reagował na zmianę motywu.
- Menu kontekstowe: nadpisany `menu(for:)` — do standardowego menu doklejane są pozycje
  formatowania z sekcji „Formatowanie treści" w opisie funkcjonalności.

#### Obsługa skrótów formatowania

Aplikacja z polityką `.accessory` i panelem nieaktywującym nie ma menu głównego, więc
`NSMenuItem.keyEquivalent` nie zadziała. Rozwiązanie: `FormattingCommands` instaluje
`NSEvent.addLocalMonitorForEvents(matching: .keyDown)` aktywny wyłącznie, gdy kluczowym oknem
jest `NotePanel`. Monitor mapuje kombinacje na wywołania:

| Skrót | Wywołanie |
|---|---|
| `⌘B` / `⌘I` | `NSFontManager.shared.addFontTrait(_:)` z `boldFontMask` / `italicFontMask` |
| `⌘U` | `textView.underline(_:)` |
| `⌃⌘K` | ręczna zmiana `.strikethroughStyle` w `NSTextStorage` |
| `⌘+` / `⌘-` | `NSFontManager.modifyFont` z `NSSizeUpFontAction` / `NSSizeDownFontAction` |
| `⌃⌘L` | `NSTextList` typu `.disc` na akapitach zaznaczenia |
| `⌘{` / `⌘\|` | `alignLeft(_:)` / `alignCenter(_:)` |
| `⌃⌘\` | usunięcie atrybutów zaznaczenia do stanu domyślnego |
| `⌥⇧⌘V` | `pasteAsPlainText(_:)` |

Każda zmiana atrybutów musi przechodzić przez `textStorage.beginEditing()` /
`endEditing()` i być objęta grupą cofania (`undoManager.beginUndoGrouping()`), żeby jedno `⌘Z`
cofało całą operację.

### 3.4 `Storage/`

`NoteStore` — jedyny właściciel stanu na dysku. API:

```swift
@MainActor final class NoteStore {
    func load() -> NSAttributedString      // nigdy nie rzuca; przy błędzie próbuje backupu, potem pusty
    func scheduleSave(_ text: NSAttributedString)   // debounce
    func flush()                            // synchroniczny zapis, jeśli są zmiany
}
```

#### Lokalizacja i format

```
~/Library/Application Support/OneSheet/
├── note.rtfd          # bieżąca treść (pakiet katalogowy)
├── note.rtfd.backup   # poprzednia poprawnie zapisana wersja
└── state.json         # pozycja kursora i przewinięcia
```

Format: **RTFD** (`NSAttributedString.fileWrapper(from:documentAttributes:)` z
`.documentType: .rtfd`). Uzasadnienie: RTF gubi wklejone załączniki, a ich cicha utrata jest
gorsza niż nieużywana zdolność formatu. RTFD to nadzbiór — obrazek wklejony przypadkiem
przetrwa, choć nie budujemy wokół tego żadnych funkcji.

Pozycja kursora i przewinięcia trafia do osobnego `state.json`, żeby nie mieszać metadanych
sesji z treścią użytkownika.

#### Algorytm zapisu

1. Serializacja `NSAttributedString` → `FileWrapper` (na wątku głównym; dostęp do
   `NSAttributedString` nie jest bezpieczny poza main).
2. Zapis `FileWrapper` do pliku tymczasowego w tym samym katalogu (ten sam wolumin — warunek
   atomowej podmiany).
3. `FileManager.replaceItemAt(_:withItemAt:backupItemName:options:)` — atomowa podmiana
   z automatycznym utworzeniem `note.rtfd.backup`.
4. Przy niepowodzeniu: log błędu, zachowanie pliku tymczasowego do diagnostyki, ponowna próba
   przy następnym zapisie. **Nigdy** nie kasujemy istniejącej notatki po nieudanym zapisie.

Debounce: `Task` z `Task.sleep(for: .milliseconds(700))`, anulowany przy każdej kolejnej zmianie.
Dodatkowo twardy limit — jeśli od pierwszej niezapisanej zmiany minęło 5 s, zapis wykonuje się
bez względu na trwające pisanie (ochrona przed ciągłym odsuwaniem zapisu przy szybkim pisaniu).

#### Wymuszony zapis (`flush`)

Wyzwalany z `AppDelegate` na: `applicationWillTerminate`, `NSApplication.willResignActiveNotification`,
`NSWorkspace.willSleepNotification`, `NSWorkspace.willPowerOffNotification` oraz przy każdym
schowaniu panelu. `flush` jest synchroniczny — przy zamykaniu systemu nie ma czasu na asynchronię.

#### Odczyt awaryjny

Kolejność prób: `note.rtfd` → `note.rtfd.backup` → pusty dokument. Każde zejście o poziom niżej
jest logowane jako `error`, a uszkodzony plik przenoszony do `note.rtfd.corrupted-<timestamp>`
zamiast być nadpisanym.

### 3.5 Ustawienia trwałe

`UserDefaults` (`com.kubam.OneSheet`), wyłącznie:

| Klucz | Typ | Domyślnie |
|---|---|---|
| `NSWindow Frame NotePanel` | String | zarządzane przez AppKit |
| `launchAtLogin` | Bool | `true` po pierwszym uruchomieniu |
| `hotKeyEnabled` | Bool | `true` |

## 4. Uruchamianie przy logowaniu

`SMAppService.mainApp.register()` / `.unregister()`. Ograniczenie: API wymaga, by aplikacja była
podpisana i uruchamiana z pakietu `.app` — **nie zadziała dla binarki spod `swift run`**.
Dlatego etap 4 workflow zaczyna się od podpisu ad-hoc (`codesign -s - --force --deep`).
Stan przełącznika czytamy z `SMAppService.mainApp.status`, nie z własnej flagi w `UserDefaults`
(źródłem prawdy jest system; flaga to tylko cache do rysowania menu).

## 5. Budowanie i pakowanie

`swift build` produkuje samą binarkę — a `NSStatusItem`, `LSUIElement` i `SMAppService` wymagają
pakietu `.app` z `Info.plist`. Stąd dwuetapowy proces.

`scripts/bundle.sh`:

1. `swift build -c release --arch arm64`
2. Utworzenie struktury `OneSheet.app/Contents/{MacOS,Resources}`
3. Kopia binarki → `Contents/MacOS/OneSheet`
4. Kopia `Sources/OneSheet/Resources/Info.plist` → `Contents/Info.plist`
5. Kopia `AppIcon.icns` → `Contents/Resources/`
6. `codesign --force --sign - --options runtime OneSheet.app`

Kluczowe wpisy `Info.plist`: `LSUIElement = true`, `LSMinimumSystemVersion = 26.0`,
`CFBundleIdentifier = com.kubam.OneSheet`, `NSHumanReadableCopyright`, `CFBundleIconFile = AppIcon`.

`Package.swift`: jeden `.executableTarget(name: "OneSheet")`, platforma `.macOS("26.0")`,
`swiftSettings: [.swiftLanguageMode(.v6)]`.

## 6. Wydajność

- Cel: otwarcie panelu poniżej 150 ms. Panel i kontroler tworzone raz, przy starcie aplikacji,
  i tylko pokazywane/chowane — nigdy nie budowane od nowa.
- Notatka wczytywana raz przy starcie, trzymana w `NSTextStorage`. Panel nie przeładowuje treści.
- Dla notatek >100 000 znaków TextKit 2 wystarcza bez dodatkowej optymalizacji; jeśli pojawią się
  zacięcia, pierwszym krokiem jest wyłączenie ciągłego sprawdzania pisowni, nie przepisywanie edytora.
- Serializacja RTFD dużego dokumentu może zająć kilkadziesiąt ms — dlatego debounce, a nie zapis
  przy każdym naciśnięciu klawisza.

## 7. Bezpieczeństwo i prywatność

- Aplikacja nie wykonuje żadnych połączeń sieciowych. Brak `NSAppTransportSecurity`, brak URLSession.
- Dane w katalogu użytkownika, chronione uprawnieniami systemu plików; bez własnego szyfrowania
  (świadoma decyzja — patrz zakres).
- Brak telemetrii, brak analityki, brak crash reportingu zewnętrznego.

## 8. Ryzyka i plany awaryjne

| Ryzyko | Skutek | Plan |
|---|---|---|
| Panel nieaktywujący nie przyjmuje klawiatury | nie da się pisać | fallback: `NSApp.activate()` przy otwarciu panelu, kosztem odbierania fokusu innej aplikacji |
| `RegisterEventHotKey` niedostępne / skrót zajęty | brak globalnego skrótu | wykrycie błędu rejestracji, wyłączenie funkcji i wpis w menu kontekstowym; aplikacja działa dalej przez klik w ikonę |
| `SMAppService` odrzuca podpis ad-hoc | brak autostartu | jawny komunikat w menu; alternatywa: ręczne dodanie w Ustawieniach systemowych |
| Lokalny monitor zdarzeń przechwytuje skróty innych aplikacji | konflikty | monitor aktywny tylko gdy `NotePanel` jest oknem kluczowym; zdarzenia nieobsłużone przepuszczane bez zmian |
| Utrata danych przy awarii w trakcie zapisu | utrata notatki | zapis atomowy + backup + plik `.corrupted` zamiast nadpisania |
