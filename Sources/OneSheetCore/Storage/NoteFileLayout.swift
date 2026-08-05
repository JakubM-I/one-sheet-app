import Foundation

/// Zestaw ścieżek, pod którymi żyje notatka.
///
/// Istnieje jako osobny typ z jednego powodu: testy muszą móc pracować w katalogu
/// tymczasowym. Gdyby ścieżki były zaszyte w `NoteStore`, każdy test zapisu dotykałby
/// prawdziwej notatki użytkownika — a to jest dokładnie ta rzecz, której nie wolno ryzykować.
struct NoteFileLayout {

    /// Katalog, w którym leżą wszystkie pliki aplikacji.
    let directory: URL

    /// `~/Library/Application Support/OneSheet` — układ produkcyjny.
    ///
    /// Zmienna środowiskowa `ONESHEET_DATA_DIRECTORY` przekierowuje cały katalog danych —
    /// używa jej wyłącznie stanowisko testowe `scripts/longnote_stand.sh` (etap 5).
    /// Podmiana samego `HOME` nie wystarcza: na macOS 26 `FileManager` wyznacza katalog
    /// domowy z bazy użytkowników i ignoruje zmienną środowiskową — sprawdzone pomiarem.
    static func applicationSupport(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NoteFileLayout {
        if let override = environment[AppConfiguration.Storage.directoryOverrideVariable] {
            return NoteFileLayout(directory: URL(filePath: override, directoryHint: .isDirectory))
        }

        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            // Katalog istnieje na każdym Macu; awaryjna ścieżka jest tu wyłącznie po to,
            // by nie musieć rozpakowywać opcjonalnej wartości siłą.
            ?? URL.homeDirectory.appending(path: "Library/Application Support")
        return NoteFileLayout(directory: base.appending(path: AppConfiguration.Storage.directoryName))
    }

    var note: URL { directory.appending(path: AppConfiguration.Storage.noteFileName) }
    var backup: URL { directory.appending(path: AppConfiguration.Storage.backupFileName) }
    var temporary: URL { directory.appending(path: AppConfiguration.Storage.temporaryFileName) }
    var state: URL { directory.appending(path: AppConfiguration.Storage.stateFileName) }

    func createDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Nazwa, pod którą nieczytelny plik notatki zostaje odłożony na bok.
    ///
    /// Znacznik czasu bez separatorów (`20260804T143012`) — dwukropki z ISO 8601 Finder
    /// pokazuje jako ukośniki, a myślniki w dacie i godzinie utrudniają odczyt na pierwszy rzut oka.
    /// Licznik na końcu obsługuje przypadek dwóch uszkodzeń w tej samej sekundzie: nadpisanie
    /// poprzedniej kwarantanny byłoby skasowaniem danych, czyli tym, przed czym ona chroni.
    func quarantine(at date: Date = Date()) -> URL {
        let stamp = date.formatted(
            .iso8601
                .year().month().day()
                .dateSeparator(.omitted)
                .dateTimeSeparator(.standard)
                .time(includingFractionalSeconds: false)
                .timeSeparator(.omitted)
        )
        let base = AppConfiguration.Storage.corruptedFilePrefix + stamp

        var candidate = directory.appending(path: base)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = directory.appending(path: "\(base)-\(counter)")
            counter += 1
        }
        return candidate
    }
}
