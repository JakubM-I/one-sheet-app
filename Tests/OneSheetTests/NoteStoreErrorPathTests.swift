import AppKit
import Foundation
import Testing
@testable import OneSheetCore

/// Ścieżki błędu warstwy trwałości — scenariusze, w których coś poszło nie tak,
/// a żaden z nich nie ma prawa skończyć się utratą danych (etap 5, hardening).
///
/// Suita jest klasą dla `deinit` (sprzątanie katalogów), jak `NoteStoreTests`.
@Suite("Ścieżki błędu trwałości")
final class NoteStoreErrorPathTests {

    let layout: NoteFileLayout
    let fileManager = FileManager.default

    init() throws {
        layout = NoteFileLayout(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "OneSheetErrorTests-\(UUID().uuidString)")
        )
        try layout.createDirectoryIfNeeded()
    }

    deinit {
        // Gdyby test nie zdążył przywrócić uprawnień, katalog nie dałby się skasować.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: layout.directory.path(percentEncoded: false)
        )
        try? FileManager.default.removeItem(at: layout.directory)
    }

    // MARK: - Pomocnicze

    func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path(percentEncoded: false))
    }

    func makeDirectoryReadOnly(_ readOnly: Bool) throws {
        try fileManager.setAttributes(
            [.posixPermissions: readOnly ? 0o555 : 0o755],
            ofItemAtPath: layout.directory.path(percentEncoded: false)
        )
    }

    @MainActor
    func save(_ text: String, to store: NoteStore) {
        store.scheduleSave(NSAttributedString(string: text), state: .initial)
        store.flush()
    }

    // MARK: - Nieudany zapis

    @Test("nieudany zapis nie rusza istniejącej notatki")
    @MainActor
    func failedWriteLeavesExistingNoteIntact() throws {
        let store = NoteStore(layout: layout)
        save("pierwsza", to: store)

        try makeDirectoryReadOnly(true)
        save("druga", to: store)
        try makeDirectoryReadOnly(false)

        #expect(try NoteArchive.readNote(at: layout.note).string == "pierwsza",
                "po nieudanym zapisie na dysku jest kompletna poprzednia wersja")
    }

    @Test("treść z nieudanego zapisu czeka i trafia na dysk przy następnej okazji")
    @MainActor
    func failedWriteIsRetriedOnNextFlush() throws {
        let store = NoteStore(layout: layout)
        save("pierwsza", to: store)

        try makeDirectoryReadOnly(true)
        save("druga", to: store)
        try makeDirectoryReadOnly(false)

        // Bez żadnej nowej zmiany — sam `flush()` (schowanie panelu, uśpienie,
        // zakończenie aplikacji) ma dokończyć zaległy zapis.
        store.flush()

        #expect(try NoteArchive.readNote(at: layout.note).string == "druga")
    }

    @Test("plik roboczy po przerwanym zapisie nie blokuje kolejnych zapisów")
    @MainActor
    func leftoverTemporaryFileDoesNotBlockSaving() throws {
        // Tak wygląda dysk po procesie ubitym między zapisem pliku roboczego a podmianą.
        try Data("niedokończony zapis".utf8).write(to: layout.temporary)

        let store = NoteStore(layout: layout)
        save("treść", to: store)

        #expect(try NoteArchive.readNote(at: layout.note).string == "treść")
        #expect(!exists(layout.temporary), "plik roboczy posprzątany przy udanym zapisie")
    }

    // MARK: - Rotacja kopii zapasowej

    @Test("trzeci zapis podmienia kopię zapasową na przedostatnią wersję")
    @MainActor
    func rotatesBackupOnEverySave() throws {
        let store = NoteStore(layout: layout)
        save("pierwsza", to: store)
        save("druga", to: store)
        save("trzecia", to: store)

        #expect(try NoteArchive.readNote(at: layout.note).string == "trzecia")
        #expect(try NoteArchive.readNote(at: layout.backup).string == "druga",
                "kopia zapasowa to zawsze poprzednia poprawnie zapisana wersja")
    }

    // MARK: - Oba pliki nieczytelne

    @Test("uszkodzona notatka i kopia — pusta kartka, oba pliki zachowane")
    @MainActor
    func keepsBothDamagedFilesWhenNothingIsReadable() throws {
        let store = NoteStore(layout: layout)
        save("pierwsza", to: store)
        save("druga", to: store)

        try fileManager.removeItem(at: layout.note)
        try Data("uszkodzona notatka".utf8).write(to: layout.note)
        try fileManager.removeItem(at: layout.backup)
        try Data("uszkodzona kopia".utf8).write(to: layout.backup)

        let loaded = NoteStore(layout: layout).load()

        #expect(loaded.text.length == 0, "aplikacja startuje z pustą kartką zamiast się wywrócić")
        #expect(exists(layout.backup), "nieczytelna kopia zostaje na dysku do ręcznego ratowania")

        let quarantined = try fileManager
            .contentsOfDirectory(atPath: layout.directory.path(percentEncoded: false))
            .filter { $0.hasPrefix(AppConfiguration.Storage.corruptedFilePrefix) }
        #expect(quarantined.count == 1, "nieczytelna notatka w kwarantannie, nie w koszu")
    }

    // MARK: - Przekierowanie katalogu danych

    @Test("zmienna środowiskowa przekierowuje katalog danych, jej brak — nie")
    func honorsDirectoryOverride() {
        let redirected = NoteFileLayout.applicationSupport(
            environment: [AppConfiguration.Storage.directoryOverrideVariable: "/tmp/stanowisko"]
        )
        #expect(redirected.directory == URL(filePath: "/tmp/stanowisko", directoryHint: .isDirectory))

        let production = NoteFileLayout.applicationSupport(environment: [:])
        #expect(production.directory.lastPathComponent == AppConfiguration.Storage.directoryName)
        #expect(production.directory.path(percentEncoded: false)
            .contains("Application Support"), "bez zmiennej środowiskowej — układ produkcyjny")
    }

    // MARK: - Kwarantanna

    @Test("dwa uszkodzenia w tej samej sekundzie nie nadpisują pierwszej kwarantanny")
    func quarantineNamesDoNotCollide() throws {
        let moment = Date(timeIntervalSince1970: 1_775_000_000)

        let first = layout.quarantine(at: moment)
        try Data("pierwsze uszkodzenie".utf8).write(to: first)

        let second = layout.quarantine(at: moment)
        #expect(second != first, "zajęta nazwa dostaje licznik zamiast zostać nadpisana")
        #expect(second.lastPathComponent == first.lastPathComponent + "-2")
    }
}
