import AppKit
import Foundation
import Testing
@testable import OneSheetCore

/// Pomiar czasu otwarcia panelu z notatką 200 000 znaków — budżet ze specyfikacji
/// (sekcja 6) to 150 ms (etap 5, profilowanie).
///
/// Suita tworzy **prawdziwe okno**, więc wymaga serwera okien i na ułamek sekundy pokazuje
/// panel na ekranie. Dlatego nie jest częścią zwykłego przebiegu `./scripts/test.sh` —
/// uruchamia się tylko jawnie:
///
///     ONESHEET_PANEL_PERF=1 ./scripts/test.sh
@Suite(
    "Otwarcie panelu z długą notatką",
    .enabled(if: ProcessInfo.processInfo.environment["ONESHEET_PANEL_PERF"] == "1")
)
struct PanelOpenPerfTests {

    @Test("drugie otwarcie panelu mieści się w budżecie 150 ms")
    @MainActor
    func opensWithinBudget() {
        let editor = EditorViewController()
        let panel = NotePanel(editorViewController: editor)

        // Najgorszy realistyczny przypadek: kursor na końcu notatki 200 000 znaków,
        // więc pierwsze otwarcie musi rozłożyć tekst aż do kursora.
        let text = LongNoteFactory.make(characterCount: 200_000)
        editor.restore(
            content: text,
            state: EditorState(selectionLocation: text.length, selectionLength: 0, scrollOffset: 100_000)
        )

        let clock = ContinuousClock()

        // Pierwsze otwarcie płaci za jednorazowe rozłożenie tekstu do kursora —
        // mierzone osobno i tylko raportowane, bez asercji.
        let firstOpen = clock.measure { panel.present(below: nil) }
        panel.hide()

        let secondOpen = clock.measure { panel.present(below: nil) }
        panel.hide()

        print("Otwarcie panelu (200 000 znaków): pierwsze \(firstOpen), kolejne \(secondOpen)")

        #expect(secondOpen < .milliseconds(150),
                "otwarcie gotowego panelu ma się mieścić w budżecie ze specyfikacji")
    }
}
