import AppKit
import Foundation
import Testing
@testable import OneSheetCore

/// Testy warstwy trwałości. Każdy dostaje własny katalog tymczasowy — nic tu nie dotyka
/// prawdziwej notatki w `~/Library/Application Support/OneSheet`.
///
/// Suita jest klasą, nie strukturą, wyłącznie dla `deinit`: swift-testing nie ma odpowiednika
/// `tearDown`, a katalogi trzeba po sobie posprzątać.
@Suite("Trwałość notatki")
final class NoteStoreTests {

    let layout: NoteFileLayout
    let fileManager = FileManager.default

    init() throws {
        layout = NoteFileLayout(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "OneSheetTests-\(UUID().uuidString)")
        )
        try layout.createDirectoryIfNeeded()
    }

    deinit {
        try? FileManager.default.removeItem(at: layout.directory)
    }

    // MARK: - Pomocnicze

    func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Zawartość katalogu bez plików ukrytych — do sprawdzania, że nic zbędnego nie zostało.
    func directoryContents() throws -> Set<String> {
        Set(try fileManager.contentsOfDirectory(atPath: layout.directory.path(percentEncoded: false)))
    }

    func quarantinedFiles() throws -> [String] {
        try directoryContents()
            .filter { $0.hasPrefix(AppConfiguration.Storage.corruptedFilePrefix) }
            .sorted()
    }

    /// Tekst z pogrubionym fragmentem — sprawdza nie tylko znaki, ale i atrybuty.
    func formattedText() -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: "zwykły i pogrubiony",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        text.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 14),
            range: NSRange(location: 9, length: 10)
        )
        return text
    }

    /// Podmienia notatkę na śmieci. Tak wygląda uszkodzenie, przed którym bronimy się kopią.
    func damageNote() throws {
        try fileManager.removeItem(at: layout.note)
        try Data("to nie jest RTFD".utf8).write(to: layout.note)
    }

    // MARK: - Odczyt

    @Test("pusty katalog daje pustą notatkę, a nie błąd")
    @MainActor
    func loadsEmptyNoteOnFirstRun() {
        let loaded = NoteStore(layout: layout).load()
        #expect(loaded.text.length == 0)
        #expect(loaded.state == nil)
    }

    @Test("treść i formatowanie przeżywają zapis i ponowny odczyt")
    @MainActor
    func roundTripsFormatting() throws {
        let store = NoteStore(layout: layout)
        store.scheduleSave(formattedText(), state: .initial)
        store.flush()

        let loaded = NoteStore(layout: layout).load()
        #expect(loaded.text.string == "zwykły i pogrubiony")

        let font = loaded.text.attribute(.font, at: 12, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true, "pogrubienie przetrwało")

        let plainFont = loaded.text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(plainFont?.fontDescriptor.symbolicTraits.contains(.bold) == false)
    }

    @Test("pusta notatka też jest zapisywana — skasowanie treści to zmiana jak każda")
    @MainActor
    func savesEmptyNote() throws {
        let store = NoteStore(layout: layout)
        store.scheduleSave(NSAttributedString(string: "coś"), state: .initial)
        store.flush()
        store.scheduleSave(NSAttributedString(), state: .initial)
        store.flush()

        #expect(NoteStore(layout: layout).load().text.length == 0)
    }

    // MARK: - Atomowość i kopia zapasowa

    @Test("drugi zapis odkłada poprzednią wersję jako kopię zapasową")
    @MainActor
    func keepsPreviousVersionAsBackup() throws {
        let store = NoteStore(layout: layout)

        store.scheduleSave(NSAttributedString(string: "pierwsza"), state: .initial)
        store.flush()
        #expect(!exists(layout.backup), "po pierwszym zapisie nie ma jeszcze czego kopiować")

        store.scheduleSave(NSAttributedString(string: "druga"), state: .initial)
        store.flush()

        #expect(try NoteArchive.readNote(at: layout.note).string == "druga")
        #expect(try NoteArchive.readNote(at: layout.backup).string == "pierwsza")
    }

    @Test("po udanym zapisie nie zostaje plik roboczy")
    @MainActor
    func leavesNoTemporaryFile() throws {
        let store = NoteStore(layout: layout)
        store.scheduleSave(NSAttributedString(string: "treść"), state: .initial)
        store.flush()
        store.scheduleSave(NSAttributedString(string: "treść 2"), state: .initial)
        store.flush()

        #expect(!exists(layout.temporary))
        #expect(try directoryContents() == [
            AppConfiguration.Storage.noteFileName,
            AppConfiguration.Storage.backupFileName,
            AppConfiguration.Storage.stateFileName,
        ])
    }

    // MARK: - Odczyt awaryjny

    @Test("uszkodzona notatka jest odtwarzana z kopii zapasowej")
    @MainActor
    func recoversFromBackup() throws {
        let store = NoteStore(layout: layout)
        store.scheduleSave(NSAttributedString(string: "wersja zapisana"), state: .initial)
        store.flush()
        store.scheduleSave(NSAttributedString(string: "wersja nowsza"), state: .initial)
        store.flush()

        try damageNote()

        #expect(NoteStore(layout: layout).load().text.string == "wersja zapisana")
    }

    @Test("uszkodzony plik trafia do kwarantanny, nie do kosza")
    @MainActor
    func quarantinesDamagedNoteInsteadOfDeleting() throws {
        let store = NoteStore(layout: layout)
        store.scheduleSave(NSAttributedString(string: "treść"), state: .initial)
        store.flush()

        try damageNote()
        _ = NoteStore(layout: layout).load()

        let quarantined = try quarantinedFiles()
        #expect(quarantined.count == 1)

        let rescued = try #require(quarantined.first)
        let content = try Data(contentsOf: layout.directory.appending(path: rescued))
        #expect(String(decoding: content, as: UTF8.self) == "to nie jest RTFD",
                "uszkodzony plik zachowany bajt w bajt")
    }

    @Test("uszkodzona notatka bez kopii zapasowej daje pustą kartkę, nie wywrotkę")
    @MainActor
    func fallsBackToEmptyDocument() throws {
        try Data("śmieci".utf8).write(to: layout.note)

        #expect(NoteStore(layout: layout).load().text.length == 0)
        #expect(try quarantinedFiles().count == 1)
    }

    @Test("brak notatki przy istniejącej kopii — treść wraca z kopii")
    @MainActor
    func recoversWhenNoteIsMissingEntirely() throws {
        let store = NoteStore(layout: layout)
        store.scheduleSave(NSAttributedString(string: "ocalona"), state: .initial)
        store.flush()
        store.scheduleSave(NSAttributedString(string: "nowsza"), state: .initial)
        store.flush()

        try fileManager.removeItem(at: layout.note)

        #expect(NoteStore(layout: layout).load().text.string == "ocalona")
    }

    // MARK: - Stan sesji

    @Test("pozycja kursora i przewinięcia przeżywa restart")
    @MainActor
    func roundTripsEditorState() {
        let state = EditorState(selectionLocation: 42, selectionLength: 7, scrollOffset: 128.5)
        let store = NoteStore(layout: layout)
        store.scheduleStateSave(state)
        store.flush()

        #expect(NoteStore(layout: layout).load().state == state)
    }

    @Test("zmiana samej pozycji nie przepisuje notatki")
    @MainActor
    func stateSaveDoesNotTouchNoteFile() throws {
        let store = NoteStore(layout: layout)
        store.scheduleStateSave(EditorState(selectionLocation: 3, selectionLength: 0, scrollOffset: 0))
        store.flush()

        #expect(exists(layout.state))
        #expect(!exists(layout.note), "przewijanie nie ma prawa serializować treści")
    }

    @Test("uszkodzony state.json jest ignorowany, treść wczytuje się normalnie")
    @MainActor
    func ignoresDamagedState() throws {
        let store = NoteStore(layout: layout)
        store.scheduleSave(NSAttributedString(string: "treść"), state: .initial)
        store.flush()
        try Data("{".utf8).write(to: layout.state)

        let loaded = NoteStore(layout: layout).load()
        #expect(loaded.text.string == "treść")
        #expect(loaded.state == nil)
    }

    // MARK: - Terminy zapisu

    @Test("zapis nie następuje natychmiast, tylko po ciszy")
    @MainActor
    func debouncesSave() async throws {
        let store = NoteStore(layout: layout, debounceInterval: 0.2, hardSaveLimit: 5)
        store.scheduleSave(NSAttributedString(string: "tekst"), state: .initial)

        #expect(!exists(layout.note), "zaraz po zmianie na dysku jeszcze nic nie ma")

        try await Task.sleep(for: .milliseconds(500))
        #expect(try NoteArchive.readNote(at: layout.note).string == "tekst")
    }

    @Test("kolejna zmiana odsuwa zapis")
    @MainActor
    func restartsDebounceOnEveryChange() async throws {
        let store = NoteStore(layout: layout, debounceInterval: 0.3, hardSaveLimit: 5)

        store.scheduleSave(NSAttributedString(string: "a"), state: .initial)
        try await Task.sleep(for: .milliseconds(150))
        store.scheduleSave(NSAttributedString(string: "ab"), state: .initial)
        try await Task.sleep(for: .milliseconds(150))

        #expect(!exists(layout.note), "łącznie 300 ms, ale bez 300 ms ciszy")

        try await Task.sleep(for: .milliseconds(350))
        #expect(try NoteArchive.readNote(at: layout.note).string == "ab")
    }

    @Test("twardy limit zapisuje mimo nieprzerwanego pisania")
    @MainActor
    func hardLimitSavesDuringContinuousTyping() async throws {
        let store = NoteStore(layout: layout, debounceInterval: 0.3, hardSaveLimit: 0.6)

        // Zmiana co 100 ms: sam debounce (300 ms ciszy) nie wypaliłby ani razu.
        for index in 1...9 {
            store.scheduleSave(NSAttributedString(string: String(repeating: "x", count: index)), state: .initial)
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(exists(layout.note), "twardy limit 600 ms wymusił zapis w trakcie pisania")
    }

    @Test("flush anuluje zaplanowany zapis i robi go od razu")
    @MainActor
    func flushWritesImmediately() throws {
        let store = NoteStore(layout: layout, debounceInterval: 60, hardSaveLimit: 60)
        store.scheduleSave(NSAttributedString(string: "natychmiast"), state: .initial)
        store.flush()

        #expect(try NoteArchive.readNote(at: layout.note).string == "natychmiast")
    }

    @Test("flush bez zmian nie tworzy żadnych plików")
    @MainActor
    func flushWithoutChangesIsNoOp() throws {
        NoteStore(layout: layout).flush()
        #expect(try directoryContents().isEmpty)
    }
}
