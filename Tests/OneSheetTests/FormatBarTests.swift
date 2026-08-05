import AppKit
import Testing
@testable import OneSheetCore

/// Testy paska szybkiego formatowania. Pasek jest widokiem, ale wszystko, co tu sprawdzamy,
/// to model: czy komplet przycisków powstał, czy podświetlenie zgadza się z tekstem pod
/// kursorem i czy kliknięcie dochodzi do tego samego kodu co skrót klawiszowy.
///
/// Najważniejszy jest test kompletu. Gdy pozycja menu zmieni akcję albo `tag`, pasek nie
/// wywraca się — po cichu pomija przycisk i zostaje wpis w logu, którego nikt nie czyta.
@Suite("Pasek formatowania")
@MainActor
struct FormatBarTests {

    @MainActor
    struct Bar {
        let bar: FormatBar
        let textView: NSTextView
        let commands: FormattingCommands

        var storage: NSTextStorage { textView.textStorage ?? NSTextStorage() }

        func selectAll() {
            textView.setSelectedRange(NSRange(location: 0, length: storage.length))
        }

        /// Przyciski w kolejności ułożenia. Szukamy po drzewie widoków, żeby test nie
        /// zaglądał do prywatnych pól — to samo, co widzi użytkownik.
        var buttons: [NSButton] {
            var found: [NSButton] = []
            var queue = bar.subviews
            while let view = queue.first {
                queue.removeFirst()
                if let button = view as? NSButton {
                    found.append(button)
                }
                queue.append(contentsOf: view.subviews)
            }
            return found
        }

        func button(_ label: String) -> NSButton? {
            buttons.first { $0.accessibilityLabel() == label }
        }
    }

    func makeBar(_ text: String) -> Bar {
        // `NSApp.sendAction` z `runCommand(_:)` wymaga istniejącej instancji aplikacji.
        _ = NSApplication.shared

        let textView = NSTextView()
        textView.isRichText = true
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: FormattingCommands.defaultAttributes)
        )

        let commands = FormattingCommands()
        commands.textView = textView

        let bar = FormatBar(textView: textView, formattingCommands: commands)
        return Bar(bar: bar, textView: textView, commands: commands)
    }

    // MARK: - Komplet przycisków

    @Test("pasek buduje komplet sześciu przycisków")
    func hasEveryButton() {
        let bar = makeBar("tekst")
        let labels = bar.buttons.compactMap { $0.accessibilityLabel() }

        #expect(labels == [
            "Pogrubienie",
            "Kursywa",
            "Podkreślenie",
            "Przekreślenie",
            "Lista punktowana",
            "Usuń formatowanie",
        ])
    }

    @Test("każdy przycisk ma ikonę i podpowiedź ze skrótem")
    func hasImageAndTooltip() {
        let bar = makeBar("tekst")

        for button in bar.buttons {
            #expect(button.image != nil, "przycisk bez symbolu SF: \(button.accessibilityLabel() ?? "?")")
            #expect(button.toolTip?.contains("⌘") == true)
        }
    }

    // MARK: - Odzwierciedlanie stanu

    @Test("pogrubienie zaznaczenia podświetla przycisk")
    func reflectsBold() {
        let bar = makeBar("tekst")
        let range = NSRange(location: 0, length: bar.storage.length)
        let bold = NSFontManager.shared.convert(
            .systemFont(ofSize: AppConfiguration.Editor.fontSize),
            toHaveTrait: .boldFontMask
        )

        #expect(bar.button("Pogrubienie")?.state == .off)

        bar.storage.addAttribute(.font, value: bold, range: range)
        bar.selectAll()
        bar.bar.refresh()

        #expect(bar.button("Pogrubienie")?.state == .on)
        #expect(bar.button("Kursywa")?.state == .off)
    }

    @Test("zaznaczenie pogrubione tylko w połowie nie podświetla przycisku")
    func partialBoldStaysOff() {
        let bar = makeBar("tekst")
        let bold = NSFontManager.shared.convert(
            .systemFont(ofSize: AppConfiguration.Editor.fontSize),
            toHaveTrait: .boldFontMask
        )

        bar.storage.addAttribute(.font, value: bold, range: NSRange(location: 0, length: 2))
        bar.selectAll()
        bar.bar.refresh()

        #expect(bar.button("Pogrubienie")?.state == .off)
    }

    @Test("przekreślenie i lista punktowana też są odzwierciedlane")
    func reflectsStrikethroughAndList() {
        let bar = makeBar("tekst")
        bar.selectAll()

        bar.commands.toggleStrikethrough(nil)
        bar.commands.toggleBulletedList(nil)
        bar.bar.refresh()

        #expect(bar.button("Przekreślenie")?.state == .on)
        #expect(bar.button("Lista punktowana")?.state == .on)
    }

    @Test("„usuń formatowanie\" nigdy nie jest przełącznikiem")
    func removeFormattingHasNoState() {
        let bar = makeBar("tekst")
        bar.selectAll()
        bar.commands.toggleStrikethrough(nil)
        bar.bar.refresh()

        #expect(bar.button("Usuń formatowanie")?.state == .off)
    }

    // MARK: - Kliknięcie

    @Test("kliknięcie przycisku wykonuje tę samą operację co skrót")
    func clickPerformsCommand() {
        let bar = makeBar("tekst")
        bar.selectAll()

        bar.button("Przekreślenie")?.performClick(nil)

        let style = bar.storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
        #expect(style == NSUnderlineStyle.single.rawValue)
        #expect(bar.button("Przekreślenie")?.state == .on)
    }

    @Test("przyciski nie odbierają fokusu polu tekstu")
    func buttonsRefuseFirstResponder() {
        let bar = makeBar("tekst")

        for button in bar.buttons {
            #expect(button.refusesFirstResponder)
        }
    }
}
