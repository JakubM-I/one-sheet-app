import AppKit
import Foundation
import Testing
@testable import OneSheetCore

/// Zachowanie warstwy trwałości przy notatkach 50 000 i 200 000 znaków (etap 5).
///
/// Granice czasowe są celowo luźne (sekundy, nie dziesiątki milisekund): test ma łapać
/// katastrofę — zapis kwadratowy, zwieszenie — a nie mierzyć dokładną wydajność maszyny.
/// Zmierzone czasy lądują w standardowym wyjściu, do odczytania przy uruchomieniu testów.
@Suite("Długie notatki")
final class LongNoteTests {

    let layout: NoteFileLayout

    init() throws {
        layout = NoteFileLayout(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "OneSheetLongNoteTests-\(UUID().uuidString)")
        )
        try layout.createDirectoryIfNeeded()
    }

    deinit {
        try? FileManager.default.removeItem(at: layout.directory)
    }

    @Test("zapis i odczyt zachowują treść i formatowanie", arguments: [50_000, 200_000])
    @MainActor
    func roundTripsLongNote(characterCount: Int) throws {
        let text = LongNoteFactory.make(characterCount: characterCount)
        let clock = ContinuousClock()

        let writeTime = try clock.measure {
            try NoteArchive.writeNote(text, to: layout)
        }

        var loaded = NSAttributedString()
        let readTime = try clock.measure {
            loaded = try NoteArchive.readNote(at: layout.note)
        }

        print("Notatka \(characterCount) znaków: zapis \(writeTime), odczyt \(readTime)")

        #expect(loaded.string == text.string, "treść bajt w bajt")
        let font = loaded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true,
                "pogrubienie pierwszego akapitu przetrwało")

        #expect(writeTime < .seconds(3), "zapis nie może być wąskim gardłem autozapisu")
        #expect(readTime < .seconds(3), "odczyt nie może zauważalnie opóźniać startu")
    }

    @Test("drugi zapis długiej notatki rotuje kopię zapasową bez utraty")
    @MainActor
    func rotatesBackupForLongNote() throws {
        let first = LongNoteFactory.make(characterCount: 200_000)
        try NoteArchive.writeNote(first, to: layout)

        let second = LongNoteFactory.make(characterCount: 200_010)
        try NoteArchive.writeNote(second, to: layout)

        #expect(try NoteArchive.readNote(at: layout.note).length == 200_010)
        #expect(try NoteArchive.readNote(at: layout.backup).length == 200_000)
    }
}
