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

    enum Editor {
        /// Margines wewnętrzny między krawędzią pola a tekstem.
        static let textInset = NSSize(width: 12, height: 12)

        /// Domyślny rozmiar czcionki notatki.
        static let fontSize: CGFloat = 14
    }
}
