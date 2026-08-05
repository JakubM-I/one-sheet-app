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
- `MainMenu` — menu główne, którego nikt nigdy nie zobaczy (aplikacja `.accessory` nie ma paska
  menu), a które mimo to jest konieczne: to z niego biorą się wszystkie skróty `⌘`.
  Uzasadnienie w sekcji 3.3.

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
- pozycjonowanie przy pierwszym otwarciu: zaczepiony pod ikoną statusu i wyrównany do jej
  lewej krawędzi (ten sam margines 6 pt co poniżej belki), przycięty do widocznego obszaru
  ekranu (`NSScreen.visibleFrame`). **Zmiana 2026-08-05** — pierwotnie wyśrodkowany
  względem ikony; patrz rejestr decyzji
- kolejne otwarcia: obowiązuje zapamiętana ramka, ale tylko na jej ekranie. Otwarcie na
  **innym** ekranie (klik w ikonę na drugim monitorze) zakotwicza panel na nowo pod ikoną,
  z zachowaniem rozmiaru; ramka częściowo wystająca za ekran jest tylko wsuwana do środka
  (`PanelGeometry.presentationFrame`, poprawka z 2026-08-05 — patrz rejestr decyzji)
- tło: jednolite, `NSWindow.backgroundColor = .textBackgroundColor` (dynamiczny kolor tła
  dokumentu, podąża za motywem), zaokrąglenie rogów zostawione systemowi.
  **Zmiana 2026-08-05** — pierwotnie `NSVisualEffectView` z materiałem `.popover`
  i `blendingMode = .behindWindow`; rozmycie psuło czytelność notatki, patrz rejestr decyzji

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

#### Obsługa skrótów klawiszowych — ukryte menu główne

**Sprostowanie (2026-08-04, etap 2).** Wcześniejsza wersja tej sekcji twierdziła, że aplikacja
`.accessory` z panelem nieaktywującym nie ma menu głównego, więc `NSMenuItem.keyEquivalent`
nie zadziała, i na tej podstawie planowała `NSEvent.addLocalMonitorForEvents`. **To była
nieprawda i kosztowała działające `⌘V`.** Aplikacja `.accessory` faktycznie nie ma **paska**
menu, ale `NSApplication.mainMenu` istnieje jako obiekt i `NSApplication.sendEvent(_:)`
odpytuje go przez `performKeyEquivalent(with:)`, zanim odda zdarzenie oknu kluczowemu.
Skróty działają, choć menu jest niewidoczne.

Pomiar na prawdziwym `AppDelegate` z syntetycznymi zdarzeniami klawiatury:

| | bez `mainMenu` | z `mainMenu` |
|---|---|---|
| `⌘A` | zaznacza 0 z 15 znaków | zaznacza 15 z 15 |
| `⌘V` | nic | wkleja z zachowaniem formatowania |
| `⌘Z` / `⇧⌘Z` | nic | cofa i ponawia |

Konsekwencja praktyczna: standardowe skróty edycyjne **nie są** wiązaniami klawiszy
`NSTextView` (nie ma ich w `StandardKeyBinding.dict`) — pochodzą wyłącznie z pozycji menu
„Edycja". Bez menu głównego pole tekstu przyjmuje znaki, ale nie da się w nim wkleić ani cofnąć.
Menu kontekstowe działa niezależnie, bo to inna ścieżka: pozycje wywołują `paste(_:)`
bezpośrednio na polu tekstu.

**Etap 2** dokłada `MainMenu` z samym menu „Edycja" — cofnij, ponów, wytnij, kopiuj, wklej,
usuń, zaznacz wszystko. Pozycje nie mają `target`; puste `target` znaczy „szukaj wykonawcy
w łańcuchu responderów", a tam siedzi `NSTextView`. To on wykonuje akcję i on decyduje przez
`validateUserInterfaceItem(_:)`, czy pozycja jest aktywna (`⌘V` przy pustym schowku nie zrobi nic).

**Etap 3** rozszerza to samo menu o menu „Format". Rozkład na wykonawców:

| Skrót | Akcja pozycji menu | Wykonawca |
|---|---|---|
| `⌘B` / `⌘I` | `addFontTrait:`, `tag` = maska cechy | `NSFontManager.shared` |
| `⌘+` / `⌘-` | `modifyFont:`, `tag` = `NSSizeUpFontAction` / `NSSizeDownFontAction` | `NSFontManager.shared` |
| `⌘U` | `underline:` | łańcuch responderów (`NSTextView`) |
| `⌘{` / `⌘\|` | `alignLeft:` / `alignCenter:` | łańcuch responderów |
| `⌥⇧⌘V` | `pasteAsPlainText:` | łańcuch responderów |
| `⌃⌘K` | przekreślenie — brak standardowego selektora | `FormattingCommands` |
| `⌃⌘L` | `NSTextList` typu `.disc` na akapitach zaznaczenia | `FormattingCommands` |
| `⌃⌘\` | usunięcie atrybutów zaznaczenia do stanu domyślnego | `FormattingCommands` |

Trzy ostatnie nie mają odpowiednika w AppKit i wymagają własnego obiektu docelowego.
Reszta to standardowe selektory — pisanie do nich własnego kodu byłoby powielaniem AppKit-u.

Te same pozycje menu budują menu kontekstowe pola tekstu, więc lista skrótów i lista pozycji
w menu nie mogą się rozjechać.

Każda zmiana atrybutów musi przechodzić przez `textStorage.beginEditing()` /
`endEditing()` i być objęta grupą cofania (`undoManager.beginUndoGrouping()`), żeby jedno `⌘Z`
cofało całą operację.

**Pułapka przy deklarowaniu skrótów z Shiftem.** `⇧⌘Z` deklaruje się **wielką** literą przy
masce samego `.command`:

```swift
menu.addItem(withTitle: "Ponów", action: Selector(("redo:")), keyEquivalent: "Z")
```

Zapis `keyEquivalent: "z"` z maską `[.command, .shift]` wygląda naturalniej, kompiluje się
i **nigdy nie dopasowuje zdarzenia** — sprawdzone pomiarem. Shift jest częścią samego znaku,
nie osobnym modyfikatorem.

**Uboczny efekt, sprawdzony:** system sam dokłada do menu „Edycja" własne pozycje (dyktowanie,
„Emoji & Symbols", AutoFill) wraz z wariantami alternatywnymi — 19 pozycji zamiast
zadeklarowanych 9. Dzieje się to raz, przy budowie menu; po 60 zdarzeniach klawiatury liczba
pozycji nie drgnęła. Menu i tak nie jest wyświetlane.

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

Zmienna środowiskowa `ONESHEET_DATA_DIRECTORY` przekierowuje cały katalog danych — używa
jej wyłącznie stanowisko testowe `scripts/longnote_stand.sh` (etap 5). Podmiana samego
`HOME` nie wystarcza: na macOS 26 `FileManager` wyznacza katalog domowy z bazy
użytkowników i ignoruje tę zmienną.

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
| `registeredBundlePath` | String | ścieżka pakietu z ostatniej udanej rejestracji autostartu (etap 6, sekcja 4) |

## 4. Uruchamianie przy logowaniu

`SMAppService.mainApp.register()` / `.unregister()`. Ograniczenie: API wymaga, by aplikacja była
podpisana i uruchamiana z pakietu `.app` — **nie zadziała dla binarki spod `swift run`**.
Dlatego etap 4 workflow zaczyna się od podpisu ad-hoc (`codesign -s - --force --deep`).
Stan przełącznika czytamy z `SMAppService.mainApp.status`, nie z własnej flagi w `UserDefaults`
(źródłem prawdy jest system; flaga to tylko cache do rysowania menu).

**Przeniesienie pakietu (etap 6, zmierzone 2026-08-05).** Wpis autostartu w bazie Background
Task Management trzyma **ścieżkę** pakietu (`sfltool dumpbtm` → pole URL), więc po instalacji
do `/Applications` logowanie uruchamiałoby starą kopię z repozytorium. Dwa pomiary na żywym
systemie:

1. `SMAppService.mainApp.status` z nowej lokalizacji **nadal zwraca `.enabled`** — dopasowuje
   po identyfikatorze pakietu, więc statusem nie da się wykryć przeprowadzki.
2. Ponowna `register()` z nowej lokalizacji **aktualizuje istniejący wpis w miejscu** — ten sam
   UUID, nowy URL, `Generation` rośnie. Nie powstaje duplikat.

Stąd mechanizm w `LaunchAtLogin.reconcileOnLaunch()`: ścieżka ostatniej udanej rejestracji
jest zapamiętywana w `UserDefaults` (`registeredBundlePath`); gdy przy starcie różni się od
`Bundle.main.bundlePath`, rejestracja jest ponawiana. Naprawa działa wyłącznie dla kopii
w `/Applications` — kopia robocza z repozytorium (np. spod `scripts/run.sh`) nie może
„ukraść" autostartu zainstalowanej aplikacji — i wyłącznie przy statusie `.enabled`, żeby
nie nadpisywać decyzji użytkownika podjętej w Ustawieniach systemowych.

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

`scripts/install.sh` (etap 6): `bundle.sh release` → zatrzymanie działającej instancji →
podmiana `/Applications/OneSheet.app` → `open`. Rejestrację autostartu na nową ścieżkę
przepisuje sama aplikacja przy pierwszym starcie z nowej lokalizacji (sekcja 4).

**Notaryzacja — poza zakresem.** Podpis ad-hoc wystarcza, dopóki aplikacja jest budowana
i używana na tej samej maszynie. Gatekeeper blokowałby dopiero pakiet przeniesiony na inny
komputer — a wtedy potrzebny jest podpis Developer ID (płatne konto) i notaryzacja. MVP
świadomie zostaje przy „sklonuj i zbuduj na miejscu".

## 6. Wydajność

- Cel: otwarcie panelu poniżej 150 ms. Panel i kontroler tworzone raz, przy starcie aplikacji,
  i tylko pokazywane/chowane — nigdy nie budowane od nowa.
- Notatka wczytywana raz przy starcie, trzymana w `NSTextStorage`. Panel nie przeładowuje treści.
- Dla notatek >100 000 znaków TextKit 2 wystarcza bez dodatkowej optymalizacji; jeśli pojawią się
  zacięcia, pierwszym krokiem jest wyłączenie ciągłego sprawdzania pisowni, nie przepisywanie edytora.
- Serializacja RTFD dużego dokumentu może zająć kilkadziesiąt ms — dlatego debounce, a nie zapis
  przy każdym naciśnięciu klawisza.
- **Pomiar (2026-08-05, etap 5):** serializacja 200 000 znaków — zapis 6,2 ms, odczyt 7,3 ms
  (50 000: 1,7 / 1,9 ms). Otwarcie panelu z notatką 200 000 znaków i kursorem na końcu:
  pierwsze 41 ms (jednorazowe rozłożenie tekstu przez TextKit 2 do kursora), kolejne 3 ms.
  Budżet 150 ms ma zapas rzędu wielkości; `NotePanel.present` loguje czas każdego otwarcia.

## 7. Bezpieczeństwo i prywatność

- Aplikacja nie wykonuje żadnych połączeń sieciowych. Brak `NSAppTransportSecurity`, brak URLSession.
- Dane w katalogu użytkownika, chronione uprawnieniami systemu plików; bez własnego szyfrowania
  (świadoma decyzja — patrz zakres).
- Brak telemetrii, brak analityki, brak crash reportingu zewnętrznego.

## 8. Ryzyka i plany awaryjne

| Ryzyko | Skutek | Plan |
|---|---|---|
| Panel nieaktywujący nie przyjmuje klawiatury | nie da się pisać | fallback: `NSApp.activate()` przy otwarciu panelu, kosztem odbierania fokusu innej aplikacji |
| `RegisterEventHotKey` niedostępne / skrót zajęty | brak globalnego skrótu | wykrycie błędu rejestracji, wyłączenie funkcji i wpis w menu kontekstowym; aplikacja działa dalej przez klik w ikonę. **Pomiar 2026-08-05 (etap 4):** rejestracja tej samej kombinacji w drugim procesie zwraca `noErr` — konflikt między aplikacjami nie objawia się błędem; `eventHotKeyExistsErr` dotyczy tylko duplikatu w obrębie procesu. Obsługa zostaje na wypadek awarii samego API |
| `SMAppService` odrzuca podpis ad-hoc | brak autostartu | jawny komunikat w menu; alternatywa: ręczne dodanie w Ustawieniach systemowych |
| ~~Lokalny monitor zdarzeń przechwytuje skróty innych aplikacji~~ | — | **Ryzyko zniknęło** wraz z decyzją o ukrytym menu głównym (sekcja 3.3). `performKeyEquivalent` dotyczy wyłącznie zdarzeń dostarczonych do naszej aplikacji, więc nie ma czego przechwytywać |
| Utrata danych przy awarii w trakcie zapisu | utrata notatki | zapis atomowy + backup + plik `.corrupted` zamiast nadpisania |
