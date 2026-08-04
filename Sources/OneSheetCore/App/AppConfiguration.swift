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
}
