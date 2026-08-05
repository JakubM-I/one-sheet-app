import AppKit

/// Trzy operacje formatowania, dla których AppKit nie ma gotowych selektorów:
/// przekreślenie, lista punktowana i usunięcie formatowania. Obiekt jest celem (`target`)
/// odpowiednich pozycji menu „Format" — pozostałe pozycje celują w `NSFontManager.shared`
/// albo idą łańcuchem responderów prosto do `NSTextView` (patrz `FormatMenu`).
///
/// Każda mutacja przechodzi przez `shouldChangeText(in:replacementString:)` /
/// `didChangeText()`. To nie biurokracja, tylko trzy gwarancje naraz:
/// - `shouldChangeText` z `replacementString: nil` rejestruje w `undoManager` stan atrybutów
///   całego zakresu, więc jedno `⌘Z` cofa całą operację,
/// - `didChangeText()` wysyła `textDidChange` do delegata, na którym wisi autozapis —
///   goła mutacja `NSTextStorage` by go ominęła i pogrubienie przepadałoby przy restarcie,
/// - pole tekstu może edycji odmówić (np. gdy nie jest edytowalne) i wtedy nic nie ruszamy.
@MainActor
final class FormattingCommands: NSObject {

    weak var textView: NSTextView?

    /// Stan „bez formatowania" — te same atrybuty, z którymi startuje puste pole tekstu.
    /// Kolor to dynamiczny `.labelColor`, więc tekst po operacji dalej reaguje na zmianę motywu.
    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: AppConfiguration.Editor.fontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: NSParagraphStyle.default,
        ]
    }

    // MARK: - Akcje menu

    /// `⌃⌘K`. Zaznaczenie częściowo przekreślone traktujemy jak nieprzekreślone:
    /// pierwsze naciśnięcie ujednolica (przekreśla całość), drugie zdejmuje.
    @objc func toggleStrikethrough(_ sender: Any?) {
        guard let textView else { return }
        let selection = textView.selectedRange()

        guard selection.length > 0 else {
            toggleTypingStrikethrough(in: textView)
            return
        }

        let adding = !isStruckEverywhere(in: textView, range: selection)
        mutate(textView, in: selection) { storage in
            if adding {
                storage.addAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: selection
                )
            } else {
                storage.removeAttribute(.strikethroughStyle, range: selection)
            }
        }
    }

    /// `⌃⌘L`. `NSTextList` typu `.disc` na akapitach objętych zaznaczeniem.
    /// TextKit 2 rysuje znaczniki sam, na podstawie stylu akapitu — w treści notatki
    /// nie pojawia się żaden znak punktora.
    @objc func toggleBulletedList(_ sender: Any?) {
        guard let textView, let storage = textView.textStorage else { return }
        let paragraphs = (storage.string as NSString).paragraphRange(for: textView.selectedRange())
        let adding = !isBulletedEverywhere(in: textView, paragraphs: paragraphs)

        // Jeden obiekt listy dla całej operacji — akapity z osobnymi `NSTextList`
        // byłyby osobnymi listami jednopunktowymi, nie punktami jednej listy.
        let lists = adding ? [NSTextList(markerFormat: .disc, options: 0)] : []

        if paragraphs.length > 0 {
            mutate(textView, in: paragraphs) { storage in
                enumerateParagraphs(of: storage, in: paragraphs) { paragraph in
                    let style = mutableParagraphStyle(of: storage, at: paragraph.location)
                    style.textLists = lists
                    storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
                }
            }
        }

        // `typingAttributes` zawsze: dla pustego akapitu to jedyna droga (nie ma znaków,
        // na których atrybut mógłby wisieć), a dla pełnych — kontynuacja listy po Enterze.
        var attributes = textView.typingAttributes
        let typingStyle = mutableCopy(of: attributes[.paragraphStyle] as? NSParagraphStyle)
        typingStyle.textLists = lists
        attributes[.paragraphStyle] = typingStyle
        textView.typingAttributes = attributes
    }

    /// `⌃⌘\`. Sprowadza zaznaczenie do stanu domyślnego. Wklejone załączniki przeżywają:
    /// `setAttributes` zdjąłby też atrybut `.attachment` i obrazek zamieniłby się
    /// w znak zastępczy — a dane użytkownika są święte, nawet te spoza budowanych funkcji.
    @objc func removeFormatting(_ sender: Any?) {
        guard let textView else { return }
        let selection = textView.selectedRange()

        guard selection.length > 0 else {
            textView.typingAttributes = Self.defaultAttributes
            return
        }

        mutate(textView, in: selection) { storage in
            var attachments: [(NSRange, Any)] = []
            storage.enumerateAttribute(.attachment, in: selection) { value, range, _ in
                if let value {
                    attachments.append((range, value))
                }
            }
            storage.setAttributes(Self.defaultAttributes, range: selection)
            for (range, value) in attachments {
                storage.addAttribute(.attachment, value: value, range: range)
            }
        }
    }

    // MARK: - Wspólna droga mutacji

    /// Patrz komentarz typu: undo, autozapis i prawo weta pola tekstu w jednym miejscu.
    /// Grupa cofania jest otwierana jawnie — `shouldChangeText` rejestruje undo od razu,
    /// więc grupa musi już wtedy istnieć.
    private func mutate(_ textView: NSTextView, in range: NSRange, _ body: (NSTextStorage) -> Void) {
        guard let storage = textView.textStorage else { return }

        textView.undoManager?.beginUndoGrouping()
        defer { textView.undoManager?.endUndoGrouping() }

        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        body(storage)
        storage.endEditing()
        textView.didChangeText()
    }

    // MARK: - Przekreślenie: stan bieżący

    private func isStruckEverywhere(in textView: NSTextView, range: NSRange) -> Bool {
        guard let storage = textView.textStorage else { return false }
        var struckEverywhere = true
        storage.enumerateAttribute(.strikethroughStyle, in: range) { value, _, stop in
            if (value as? Int ?? 0) == 0 {
                struckEverywhere = false
                stop.pointee = true
            }
        }
        return struckEverywhere
    }

    private func toggleTypingStrikethrough(in textView: NSTextView) {
        var attributes = textView.typingAttributes
        if (attributes[.strikethroughStyle] as? Int ?? 0) == 0 {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        } else {
            attributes.removeValue(forKey: .strikethroughStyle)
        }
        textView.typingAttributes = attributes
    }

    // MARK: - Lista: stan bieżący i akapity

    private func isBulletedEverywhere(in textView: NSTextView, paragraphs: NSRange) -> Bool {
        guard let storage = textView.textStorage, paragraphs.length > 0 else {
            let style = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
            return !(style?.textLists.isEmpty ?? true)
        }

        var bulletedEverywhere = true
        enumerateParagraphs(of: storage, in: paragraphs) { paragraph in
            let style = storage.attribute(
                .paragraphStyle, at: paragraph.location, effectiveRange: nil
            ) as? NSParagraphStyle
            if style?.textLists.isEmpty ?? true {
                bulletedEverywhere = false
            }
        }
        return bulletedEverywhere
    }

    /// Przechodzi po pełnych akapitach pokrywających `range` — także wtedy, gdy zaznaczenie
    /// zaczyna się lub kończy w środku akapitu. Styl akapitu jest atrybutem całego akapitu,
    /// więc operacje akapitowe nie mogą honorować granic zaznaczenia co do znaku.
    private func enumerateParagraphs(of storage: NSTextStorage, in range: NSRange, _ body: (NSRange) -> Void) {
        let string = storage.string as NSString
        var location = range.location
        while location < NSMaxRange(range) {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            guard paragraph.length > 0 else { break }
            body(paragraph)
            location = NSMaxRange(paragraph)
        }
    }

    private func mutableParagraphStyle(of storage: NSTextStorage, at location: Int) -> NSMutableParagraphStyle {
        let existing = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        return mutableCopy(of: existing)
    }

    private func mutableCopy(of style: NSParagraphStyle?) -> NSMutableParagraphStyle {
        (style ?? .default).mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
    }
}

// MARK: - Walidacja pozycji menu

extension FormattingCommands: NSMenuItemValidation {

    /// Skróty mają być martwe przy schowanym panelu. Zdarzenia klawiatury i tak nie trafiają
    /// do aplikacji bez okna kluczowego, ale jawna walidacja zamyka również ścieżkę
    /// programową (`performActionForItem(at:)`) i wyszarza pozycje w menu kontekstowym,
    /// gdyby pole tekstu przestało być edytowalne.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let textView, let window = textView.window else { return false }
        return window.isVisible && textView.isEditable
    }
}
