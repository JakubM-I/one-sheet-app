import Carbon.HIToolbox
import Foundation

/// Jedyne miejsce ze stałymi konfiguracyjnymi aplikacji.
/// Zasada: żadna „magiczna" wartość nie żyje rozsypana po kodzie.
enum AppConfiguration {

    /// Identyfikator pakietu. Musi być zgodny z `CFBundleIdentifier` w `Info.plist` —
    /// rozjazd zepsuje `SMAppService` (autostart) w etapie 4.
    static let bundleIdentifier = "com.kubam.OneSheet"

    /// Subsystem dla `os.Logger`. Podgląd na żywo:
    /// `log stream --predicate 'subsystem == "com.kubam.OneSheet"'`
    static let loggingSubsystem = bundleIdentifier

    enum StatusItem {
        /// SF Symbol rysowany w belce. Renderowany jako szablon, więc system sam
        /// dobiera kolor do motywu i przezroczystości belki.
        static let symbolName = "note.text"

        /// Opis dla VoiceOver — ikona bez etykiety tekstowej musi go mieć.
        static let accessibilityDescription = "one-sheet — notatnik"
    }

    enum Panel {
        /// Rozmiar przy pierwszym uruchomieniu. Później wygrywa rozmiar zapamiętany
        /// przez AppKit pod `frameAutosaveName`.
        static let defaultSize = NSSize(width: 380, height: 480)

        /// Poniżej tego rozmiaru panel przestaje być użyteczny jako pole tekstu.
        static let minimumSize = NSSize(width: 260, height: 200)

        /// Klucz, pod którym AppKit trzyma ramkę okna w `UserDefaults`
        /// (jako `NSWindow Frame NotePanel`).
        static let frameAutosaveName = "NotePanel"

        /// Odstęp między dolną krawędzią ikony w belce a górną krawędzią panelu.
        static let gapBelowStatusItem: CGFloat = 6

        /// Wysokość niewidocznego paska tytułu. Panel nie jest przesuwalny za tło
        /// (kolizja z zaznaczaniem tekstu), więc to jedyny uchwyt do przeciągania —
        /// i dlatego edytor musi zaczynać się dopiero pod nim.
        static let dragStripHeight: CGFloat = 28
    }

    enum HotKey {
        /// Globalny skrót otwierania panelu: `⌥⌘N`. Kody i maski pochodzą z Carbon
        /// (`kVK_ANSI_N`, `optionKey`, `cmdKey`) — to inne stałe niż `NSEvent.ModifierFlags`
        /// i nie wolno ich mieszać.
        static let keyCode = UInt32(kVK_ANSI_N)
        static let modifiers = UInt32(optionKey | cmdKey)

        /// Sygnatura zdarzeń hot-key tej aplikacji — four-char code `OnSh`.
        /// Carbon dostarcza zdarzenia wszystkim zainstalowanym uchwytom w procesie,
        /// więc uchwyt musi umieć rozpoznać własne.
        static let signature: OSType = 0x4F6E5368

        /// Zapis do pokazania użytkownikowi, np. w komunikacie o zajętym skrócie.
        static let displayName = "⌥⌘N"
    }

    enum Defaults {
        /// Zamiar użytkownika co do autostartu. Stanu **nie** czytamy z tej flagi
        /// (źródłem prawdy jest `SMAppService.mainApp.status`) — flaga odnotowuje
        /// głównie to, że pierwsze uruchomienie już włączyło autostart.
        static let launchAtLogin = "launchAtLogin"

        /// Wyłącznik skrótu globalnego. Brak wartości znaczy „włączony".
        static let hotKeyEnabled = "hotKeyEnabled"

        /// Ścieżka pakietu, z której ostatnio udała się rejestracja autostartu.
        /// Wpis login item w systemie trzyma ścieżkę, nie identyfikator — po przeniesieniu
        /// aplikacji (instalacja do `/Applications`) porównanie z tą wartością wykrywa
        /// przeprowadzkę i wyzwala ponowną rejestrację. Szczegóły w `LaunchAtLogin`.
        static let registeredBundlePath = "registeredBundlePath"
    }

    enum Editor {
        /// Margines wewnętrzny między krawędzią pola a tekstem.
        static let textInset = NSSize(width: 12, height: 12)

        /// Domyślny rozmiar czcionki notatki.
        static let fontSize: CGFloat = 14
    }

    enum Storage {
        /// Katalog aplikacji wewnątrz `~/Library/Application Support`.
        static let directoryName = "OneSheet"

        /// Bieżąca treść notatki. RTFD jest pakietem katalogowym, nie pojedynczym plikiem.
        static let noteFileName = "note.rtfd"

        /// Poprzednia poprawnie zapisana wersja. Nazwę przekazujemy `replaceItemAt(...)`,
        /// które samo odkłada tu stary plik przy podmianie.
        static let backupFileName = "note.rtfd.backup"

        /// Miejsce, w którym powstaje nowa wersja przed podmianą. Stała nazwa, a nie losowa:
        /// w katalogu ma się nigdy nie zbierać więcej niż jeden plik roboczy.
        static let temporaryFileName = "note.rtfd.writing"

        /// Pozycja kursora i przewinięcia — metadane sesji, trzymane osobno od treści.
        static let stateFileName = "state.json"

        /// Przedrostek nazwy, pod którą odkładamy nieczytelny plik notatki.
        /// Nigdy go nie kasujemy — użytkownik ma prawo spróbować go odzyskać sam.
        static let corruptedFilePrefix = "note.rtfd.corrupted-"

        /// Zmienna środowiskowa przekierowująca katalog danych — wyłącznie dla stanowiska
        /// testowego (`scripts/longnote_stand.sh`). Uzasadnienie w `NoteFileLayout`.
        static let directoryOverrideVariable = "ONESHEET_DATA_DIRECTORY"

        /// Cisza po ostatniej zmianie, po której treść trafia na dysk.
        static let debounceInterval: TimeInterval = 0.7

        /// Górna granica odsuwania zapisu. Bez niej nieprzerwane pisanie odsuwałoby
        /// debounce w nieskończoność i notatka nigdy nie trafiłaby na dysk.
        static let hardSaveLimit: TimeInterval = 5
    }
}
