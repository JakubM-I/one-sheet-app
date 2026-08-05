import AppKit
import Testing
@testable import OneSheetCore

/// Strażnik zgodności menu „Format" z tabelą skrótów ze specyfikacji (sekcja 3.3).
/// Menu jest niewidoczne, więc rozjazd skrótu z tabelą nie rzuciłby się w oczy —
/// wyszedłby dopiero jako „skrót nie działa" u użytkownika.
@Suite("Menu Format")
@MainActor
struct FormatMenuTests {

    @Test("skróty pozycji zgadzają się z tabelą ze specyfikacji")
    func keyEquivalentsMatchSpecTable() {
        let items = FormatMenu.makeItems(commands: FormattingCommands()).filter { !$0.isSeparatorItem }

        let expected: [(title: String, key: String, modifiers: NSEvent.ModifierFlags)] = [
            ("Pogrubienie", "b", .command),
            ("Kursywa", "i", .command),
            ("Podkreślenie", "u", .command),
            ("Przekreślenie", "k", [.command, .control]),
            ("Większa czcionka", "+", .command),
            ("Mniejsza czcionka", "-", .command),
            ("Lista punktowana", "l", [.command, .control]),
            ("Wyrównaj do lewej", "{", .command),
            ("Wyśrodkuj", "|", .command),
            ("Usuń formatowanie", "\\", [.command, .control]),
            // Shift siedzi w wielkiej literze, nie w masce — patrz pułapka w `MainMenu`.
            ("Wklej bez formatowania", "V", [.command, .option]),
        ]

        #expect(items.count == expected.count)
        for (item, entry) in zip(items, expected) {
            #expect(item.title == entry.title)
            #expect(item.keyEquivalent == entry.key, "\(entry.title)")
            #expect(item.keyEquivalentModifierMask == entry.modifiers, "\(entry.title)")
        }
    }

    @Test("każda pozycja celuje w zaprojektowanego wykonawcę")
    func targetsMatchDesign() {
        let commands = FormattingCommands()
        let items = FormatMenu.makeItems(commands: commands).filter { !$0.isSeparatorItem }

        let custom = items.filter { $0.target === commands }
        #expect(custom.map(\.title) == ["Przekreślenie", "Lista punktowana", "Usuń formatowanie"])

        let fontManager = items.filter { $0.target === NSFontManager.shared }
        #expect(fontManager.map(\.title) == ["Pogrubienie", "Kursywa", "Większa czcionka", "Mniejsza czcionka"])
        #expect(fontManager.map(\.tag) == [
            Int(NSFontTraitMask.boldFontMask.rawValue),
            Int(NSFontTraitMask.italicFontMask.rawValue),
            Int(NSFontAction.sizeUpFontAction.rawValue),
            Int(NSFontAction.sizeDownFontAction.rawValue),
        ])

        // Reszta idzie łańcuchem responderów do `NSTextView` — cel musi zostać pusty.
        let responderChain = items.filter { $0.target == nil }
        #expect(responderChain.map(\.title) == [
            "Podkreślenie", "Wyrównaj do lewej", "Wyśrodkuj", "Wklej bez formatowania",
        ])
    }

    @Test("menu główne zawiera menu Format zbudowane z tych samych pozycji")
    func mainMenuMirrorsSharedItems() {
        let commands = FormattingCommands()
        let menu = FormatMenu.makeMenu(commands: commands)
        let titles = FormatMenu.makeItems(commands: commands).filter { !$0.isSeparatorItem }.map(\.title)
        #expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == titles)
    }
}
