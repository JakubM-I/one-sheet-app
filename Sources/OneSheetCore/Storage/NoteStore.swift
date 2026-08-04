import AppKit

/// Jedyny właściciel notatki na dysku. Decyduje **kiedy** zapisać i **co zrobić z błędem**;
/// samo dotykanie plików robi `NoteArchive`.
///
/// Cały typ jest na `@MainActor`, bo dostęp do `NSTextStorage` poza wątkiem głównym nie jest
/// bezpieczny. Serializacja RTFD też dzieje się na main — dla notatki mieszczącej się na ekranie
/// to ułamek milisekundy, a zysk jest taki, że treść nigdy nie zmienia się w trakcie zapisu.
@MainActor
final class NoteStore {

    /// Wynik wczytania: treść zawsze, stan sesji tylko jeśli był zapisany.
    struct LoadedNote {
        let text: NSAttributedString
        let state: EditorState?
    }

    private let layout: NoteFileLayout
    private let debounceInterval: TimeInterval
    private let hardSaveLimit: TimeInterval

    /// Referencja do żywego `NSTextStorage`, a nie jego kopia.
    ///
    /// Kopiowanie całej notatki przy każdym naciśnięciu klawisza kosztowałoby tyle, ile
    /// próbuje oszczędzić debounce. Skoro i tak wszystko dzieje się na wątku głównym,
    /// treść nie może się zmienić „w trakcie" zapisu — zapisujemy po prostu stan aktualny.
    private var pendingText: NSAttributedString?
    private var pendingState: EditorState?

    private var saveTask: Task<Void, Never>?

    /// Moment pierwszej zmiany, która jeszcze nie trafiła na dysk. Od niego liczy się
    /// twardy limit; `nil` oznacza, że dysk jest zgodny z pamięcią.
    private var firstUnsavedChange: Date?

    init(
        layout: NoteFileLayout = .applicationSupport(),
        debounceInterval: TimeInterval = AppConfiguration.Storage.debounceInterval,
        hardSaveLimit: TimeInterval = AppConfiguration.Storage.hardSaveLimit
    ) {
        self.layout = layout
        self.debounceInterval = debounceInterval
        self.hardSaveLimit = hardSaveLimit
    }

    // MARK: - Odczyt

    /// Wczytuje notatkę. Nie rzuca **nigdy** — brak notatki i uszkodzona notatka to dwa
    /// różne problemy, ale żaden z nich nie jest powodem, by aplikacja się nie uruchomiła.
    func load() -> LoadedNote {
        LoadedNote(text: loadText(), state: NoteArchive.readState(at: layout.state))
    }

    /// Kolejność prób: `note.rtfd` → `note.rtfd.backup` → pusty dokument.
    /// Każde zejście o poziom niżej jest błędem w logu, nie cichym zdarzeniem.
    private func loadText() -> NSAttributedString {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: layout.note.path(percentEncoded: false)) {
            do {
                return try NoteArchive.readNote(at: layout.note)
            } catch {
                Log.storage.error("Notatka nieczytelna: \(error.localizedDescription, privacy: .public)")
                quarantineDamagedNote()
            }
        } else {
            Log.storage.info("Brak pliku notatki — start z pustą kartką")
        }

        if fileManager.fileExists(atPath: layout.backup.path(percentEncoded: false)) {
            do {
                let recovered = try NoteArchive.readNote(at: layout.backup)
                Log.storage.error("Treść odtworzona z kopii zapasowej")
                return recovered
            } catch {
                Log.storage.error("Kopia zapasowa również nieczytelna: \(error.localizedDescription, privacy: .public)")
            }
        }

        return NSAttributedString()
    }

    /// Uszkodzony plik odkładamy na bok pod nazwą z datą — nigdy nie kasujemy i nigdy
    /// nie nadpisujemy. To ostatnia kopia treści, której nie udało się odczytać *nam*;
    /// nie znaczy to, że nie odczyta jej człowiek z TextEdit.
    private func quarantineDamagedNote() {
        let destination = layout.quarantine()
        do {
            try FileManager.default.moveItem(at: layout.note, to: destination)
            Log.storage.error("Uszkodzony plik odłożony jako \(destination.lastPathComponent, privacy: .public)")
        } catch {
            // Notatka zostaje tam, gdzie była. Następny zapis ją podmieni, a kopia zapasowa
            // z tego zapisu i tak zachowa uszkodzoną wersję.
            Log.storage.error("Nie udało się odłożyć uszkodzonego pliku: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Zapis

    /// Zgłasza zmianę treści. Zapis nastąpi po `debounceInterval` ciszy, ale nie później
    /// niż `hardSaveLimit` od pierwszej niezapisanej zmiany.
    func scheduleSave(_ text: NSAttributedString, state: EditorState) {
        pendingText = text
        pendingState = state
        scheduleWrite()
    }

    /// Zgłasza samą zmianę pozycji kursora lub przewinięcia.
    ///
    /// Osobna droga, bo przewijanie długiej notatki generuje dziesiątki zdarzeń na sekundę,
    /// a każde z nich przez `scheduleSave` oznaczałoby ponowną serializację całego RTFD.
    func scheduleStateSave(_ state: EditorState) {
        pendingState = state
        scheduleWrite()
    }

    /// Zapisuje natychmiast i synchronicznie, jeśli jest co zapisywać.
    ///
    /// Wywoływane przy zakończeniu aplikacji, uśpieniu i wylogowaniu — momentach, w których
    /// nikt nie zaczeka na `await`. Po `flush()` dysk zgadza się z pamięcią albo w logu
    /// jest błąd; trzeciej możliwości nie ma.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        writePendingChanges()
    }

    private func scheduleWrite() {
        let now = Date()
        let firstChange = firstUnsavedChange ?? now
        firstUnsavedChange = firstChange

        saveTask?.cancel()

        // Dwa terminy, wygrywa wcześniejszy: „700 ms ciszy" i „5 s od pierwszej zmiany".
        // Bez tego drugiego ktoś, kto pisze bez przerwy, nie zapisałby nic przez godzinę.
        let deadline = min(
            now.addingTimeInterval(debounceInterval),
            firstChange.addingTimeInterval(hardSaveLimit)
        )
        let delay = max(0, deadline.timeIntervalSince(now))

        saveTask = Task { [weak self] in
            // `try?` połyka wyłącznie przerwanie snu przez anulowanie — sprawdzamy je linijkę niżej.
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.writePendingChanges()
        }
    }

    private func writePendingChanges() {
        if let text = pendingText {
            do {
                try NoteArchive.writeNote(text, to: layout)
                pendingText = nil
            } catch {
                // Świadomie nie czyścimy `pendingText`: nieudany zapis ma zostać powtórzony
                // przy następnej zmianie. Istniejąca notatka na dysku pozostaje nietknięta.
                Log.storage.error("Zapis notatki nieudany: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let state = pendingState {
            do {
                try NoteArchive.writeState(state, to: layout)
                pendingState = nil
            } catch {
                Log.storage.error("Zapis stanu sesji nieudany: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Zegar twardego limitu zeruje się dopiero, gdy nic już nie czeka. Gdyby zerował się
        // po samym zapisie stanu, każde przewinięcie po nieudanym zapisie treści wyglądałoby
        // jak „pierwsza zmiana" i odsuwało ponowną próbę.
        if pendingText == nil, pendingState == nil {
            firstUnsavedChange = nil
        }
    }
}
