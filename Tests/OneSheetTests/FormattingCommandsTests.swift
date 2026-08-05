import AppKit
import Testing
@testable import OneSheetCore

/// Testy operacji formatowania bez standardowego selektora AppKit. Wszystko działa na
/// `NSTextView` bez okna — atrybuty, zaznaczenie i undo to model, nie rysowanie.
///
/// Delegat-atrapa jest tu konieczny z dwóch powodów: `NSTextView` bez okna nie ma żadnego
/// `UndoManager` (normalnie dostaje go od `NSWindow`), a licznik `textDidChange` sprawdza
/// jedyny sygnał, na którym wisi autozapis.
@Suite("Operacje formatowania")
@MainActor
struct FormattingCommandsTests {

    @MainActor
    final class EditorDelegateStub: NSObject, NSTextViewDelegate {
        let undo = UndoManager()
        private(set) var textChangeCount = 0

        override init() {
            super.init()
            // Bez pętli zdarzeń nikt nie zamknie grupy otwieranej automatycznie —
            // grupy otwiera i zamyka jawnie `FormattingCommands`.
            undo.groupsByEvent = false
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }
        func textDidChange(_ notification: Notification) { textChangeCount += 1 }
    }

    struct Editor {
        let textView: NSTextView
        let commands: FormattingCommands
        let delegate: EditorDelegateStub

        var storage: NSTextStorage { textView.textStorage ?? NSTextStorage() }

        func selectAll() {
            textView.setSelectedRange(NSRange(location: 0, length: storage.length))
        }
    }

    func makeEditor(_ text: String) -> Editor {
        let textView = NSTextView()
        let delegate = EditorDelegateStub()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.delegate = delegate
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: FormattingCommands.defaultAttributes)
        )
        let commands = FormattingCommands()
        commands.textView = textView
        return Editor(textView: textView, commands: commands, delegate: delegate)
    }

    func strikethrough(in editor: Editor, at location: Int) -> Int {
        editor.storage.attribute(.strikethroughStyle, at: location, effectiveRange: nil) as? Int ?? 0
    }

    func textLists(in editor: Editor, at location: Int) -> [NSTextList] {
        let style = editor.storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        return style?.textLists ?? []
    }

    // MARK: - Przekreślenie

    @Test("przekreślenie zaznaczenia da się nałożyć i zdjąć")
    func strikethroughTogglesOnSelection() {
        let editor = makeEditor("do przekreślenia")
        editor.selectAll()

        editor.commands.toggleStrikethrough(nil)
        #expect(strikethrough(in: editor, at: 0) == NSUnderlineStyle.single.rawValue)
        #expect(strikethrough(in: editor, at: editor.storage.length - 1) == NSUnderlineStyle.single.rawValue)

        editor.commands.toggleStrikethrough(nil)
        #expect(strikethrough(in: editor, at: 0) == 0)
    }

    @Test("zaznaczenie przekreślone częściowo najpierw jest ujednolicane")
    func strikethroughUnifiesMixedSelection() {
        let editor = makeEditor("pół na pół")
        editor.storage.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: 3)
        )
        editor.selectAll()

        editor.commands.toggleStrikethrough(nil)
        #expect(strikethrough(in: editor, at: 9) == NSUnderlineStyle.single.rawValue,
                "pierwsze naciśnięcie przekreśla całość, nie odwraca po kawałku")
    }

    @Test("bez zaznaczenia przełączane są atrybuty pisania")
    func strikethroughTogglesTypingAttributes() {
        let editor = makeEditor("tekst")
        editor.textView.setSelectedRange(NSRange(location: 2, length: 0))

        editor.commands.toggleStrikethrough(nil)
        #expect(editor.textView.typingAttributes[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)

        editor.commands.toggleStrikethrough(nil)
        #expect(editor.textView.typingAttributes[.strikethroughStyle] == nil)
    }

    // MARK: - Lista punktowana

    @Test("lista obejmuje całe akapity, także zaznaczone częściowo")
    func bulletListCoversWholeParagraphs() {
        let editor = makeEditor("pierwszy akapit\ndrugi akapit\ntrzeci akapit")
        // Od środka pierwszego akapitu do środka drugiego.
        editor.textView.setSelectedRange(NSRange(location: 4, length: 16))

        editor.commands.toggleBulletedList(nil)

        #expect(!textLists(in: editor, at: 0).isEmpty, "początek pierwszego akapitu, przed zaznaczeniem")
        #expect(!textLists(in: editor, at: 20).isEmpty, "drugi akapit")
        #expect(textLists(in: editor, at: 30).isEmpty, "trzeci akapit zostaje poza listą")
    }

    @Test("akapity jednej operacji są punktami jednej listy, drugie naciśnięcie ją zdejmuje")
    func bulletListSharesOneListAndToggles() {
        let editor = makeEditor("raz\ndwa")
        editor.selectAll()

        editor.commands.toggleBulletedList(nil)
        let first = textLists(in: editor, at: 0)
        let second = textLists(in: editor, at: 4)
        #expect(first.count == 1)
        #expect(first.first === second.first, "wspólny obiekt NSTextList, nie dwie listy jednopunktowe")
        #expect(first.first?.markerFormat == .disc)

        editor.commands.toggleBulletedList(nil)
        #expect(textLists(in: editor, at: 0).isEmpty)
        #expect(textLists(in: editor, at: 4).isEmpty)
    }

    @Test("lista ląduje też w atrybutach pisania — kontynuacja w nowym akapicie")
    func bulletListUpdatesTypingAttributes() {
        let editor = makeEditor("akapit")
        editor.selectAll()

        editor.commands.toggleBulletedList(nil)
        let style = editor.textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(style?.textLists.isEmpty == false)

        editor.commands.toggleBulletedList(nil)
        let cleared = editor.textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(cleared?.textLists.isEmpty ?? true)
    }

    // MARK: - Usunięcie formatowania

    @Test("usunięcie formatowania wraca do stanu domyślnego")
    func removeFormattingRestoresDefaults() throws {
        let editor = makeEditor("sformatowane")
        let all = NSRange(location: 0, length: editor.storage.length)
        editor.storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 22), range: all)
        editor.storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: all)
        editor.storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: all)
        editor.selectAll()

        editor.commands.removeFormatting(nil)

        let font = try #require(editor.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == AppConfiguration.Editor.fontSize)
        #expect(!font.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(strikethrough(in: editor, at: 0) == 0)
        #expect(editor.storage.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
        #expect(editor.storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .labelColor)
    }

    @Test("usunięcie formatowania nie kasuje wklejonego załącznika")
    func removeFormattingPreservesAttachments() {
        let editor = makeEditor("")
        let text = NSMutableAttributedString(string: "obrazek: ", attributes: FormattingCommands.defaultAttributes)
        text.append(NSAttributedString(attachment: NSTextAttachment()))
        editor.storage.setAttributedString(text)
        editor.selectAll()

        editor.commands.removeFormatting(nil)

        let attachment = editor.storage.attribute(.attachment, at: 9, effectiveRange: nil)
        #expect(attachment != nil, "atrybut załącznika przeżywa reset atrybutów")
    }

    @Test("usunięcie formatowania bez zaznaczenia resetuje atrybuty pisania")
    func removeFormattingResetsTypingAttributes() {
        let editor = makeEditor("tekst")
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        editor.commands.toggleStrikethrough(nil)

        editor.commands.removeFormatting(nil)
        #expect(editor.textView.typingAttributes[.strikethroughStyle] == nil)
    }

    // MARK: - Undo i autozapis

    @Test("jedno cofnięcie zdejmuje całą operację, nie jej kawałek")
    func singleUndoRevertsWholeOperation() {
        let editor = makeEditor("raz\ndwa\ntrzy")
        editor.selectAll()

        editor.commands.toggleStrikethrough(nil)
        #expect(strikethrough(in: editor, at: 0) != 0)
        #expect(strikethrough(in: editor, at: 8) != 0)

        editor.delegate.undo.undo()
        #expect(strikethrough(in: editor, at: 0) == 0)
        #expect(strikethrough(in: editor, at: 8) == 0, "cały zakres wraca jednym ⌘Z")
    }

    @Test("każda operacja zgłasza zmianę treści — na tym wisi autozapis")
    func everyOperationSignalsTextChange() {
        let editor = makeEditor("raz\ndwa")
        editor.selectAll()

        editor.commands.toggleStrikethrough(nil)
        #expect(editor.delegate.textChangeCount == 1)

        editor.commands.toggleBulletedList(nil)
        #expect(editor.delegate.textChangeCount == 2)

        editor.commands.removeFormatting(nil)
        #expect(editor.delegate.textChangeCount == 3)
    }

    @Test("mutacja samych atrybutów z pominięciem didChangeText też uruchamia autozapis")
    func attributeOnlyMutationTriggersAutosave() {
        // Pełny kontroler edytora: to jego nasłuch `NSTextStorage.didProcessEditingNotification`
        // jest siatką bezpieczeństwa dla operacji `NSFontManager` i cofania formatowania.
        let editorController = EditorViewController()
        _ = editorController.view
        editorController.restore(
            content: NSAttributedString(string: "tekst", attributes: FormattingCommands.defaultAttributes),
            state: nil
        )

        var changes = 0
        editorController.onTextChange = { changes += 1 }

        editorController.textView.textStorage?.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: 5)
        )
        #expect(changes == 1, "goła mutacja NSTextStorage nie ma prawa ominąć zapisu")
    }

    // MARK: - Trwałość

    @Test("przekreślenie i lista punktowana przeżywają serializację RTFD")
    func formattingSurvivesRTFDRoundTrip() throws {
        let editor = makeEditor("do przekreślenia\npunkt listy")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 16))
        editor.commands.toggleStrikethrough(nil)
        editor.textView.setSelectedRange(NSRange(location: 17, length: 5))
        editor.commands.toggleBulletedList(nil)

        let data = try editor.storage.data(
            from: NSRange(location: 0, length: editor.storage.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
        let read = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        )

        #expect((read.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int ?? 0) != 0)
        let style = read.attribute(.paragraphStyle, at: 17, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.textLists.isEmpty == false)
    }
}
