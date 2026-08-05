import AppKit

/// Odczyt bieżącego formatowania. Jedno źródło odpowiedzi na pytanie „czy to jest włączone" —
/// pytają stąd zarówno operacje przełączające (`FormattingCommands`), jak i pasek nad polem
/// tekstu (`FormatBar`). Rozjazd między podświetleniem przycisku a działaniem skrótu byłby
/// błędem, którego użytkownik nie umie sobie wytłumaczyć, więc logika jest tylko tutaj.
///
/// Zasada dla zaznaczenia: cecha jest włączona wyłącznie wtedy, gdy obejmuje **cały** zakres.
/// Zaznaczenie w połowie pogrubione liczy się jako niepogrubione — pierwsze naciśnięcie
/// ujednolica, drugie zdejmuje. Pusty zakres pyta `typingAttributes`, bo nie ma wtedy znaków,
/// na których atrybut mógłby wisieć.
@MainActor
enum FormattingState {

    /// Atrybut typu włącznik: podkreślenie, przekreślenie. Brak atrybutu i wartość zero
    /// znaczą to samo — AppKit używa obu zapisów wymiennie.
    static func isSet(_ key: NSAttributedString.Key, in textView: NSTextView, range: NSRange) -> Bool {
        guard let storage = textView.textStorage, range.length > 0 else {
            return (textView.typingAttributes[key] as? Int ?? 0) != 0
        }

        var everywhere = true
        storage.enumerateAttribute(key, in: range) { value, _, stop in
            if (value as? Int ?? 0) == 0 {
                everywhere = false
                stop.pointee = true
            }
        }
        return everywhere
    }

    /// Cecha kroju (pogrubienie, kursywa). Pytamy `NSFontManager` o tę samą maskę, którą
    /// posługuje się `addFontTrait:` — czyli tę, którą zmieni kliknięcie przycisku.
    static func hasTrait(_ trait: NSFontTraitMask, in textView: NSTextView, range: NSRange) -> Bool {
        let manager = NSFontManager.shared

        guard let storage = textView.textStorage, range.length > 0 else {
            guard let font = textView.typingAttributes[.font] as? NSFont else { return false }
            return manager.traits(of: font).contains(trait)
        }

        var everywhere = true
        storage.enumerateAttribute(.font, in: range) { value, _, stop in
            guard let font = value as? NSFont, manager.traits(of: font).contains(trait) else {
                everywhere = false
                stop.pointee = true
                return
            }
        }
        return everywhere
    }

    /// Lista punktowana. Znacznik nie jest znakiem w treści, tylko `NSTextList` w stylu
    /// akapitu — pytamy więc akapity, nie tekst.
    static func isBulleted(in textView: NSTextView, paragraphs: NSRange) -> Bool {
        guard let storage = textView.textStorage, paragraphs.length > 0 else {
            let style = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
            return !(style?.textLists.isEmpty ?? true)
        }

        var everywhere = true
        enumerateParagraphs(of: storage, in: paragraphs) { paragraph in
            let style = storage.attribute(
                .paragraphStyle, at: paragraph.location, effectiveRange: nil
            ) as? NSParagraphStyle
            if style?.textLists.isEmpty ?? true {
                everywhere = false
            }
        }
        return everywhere
    }

    /// Przechodzi po pełnych akapitach pokrywających `range` — także wtedy, gdy zaznaczenie
    /// zaczyna się lub kończy w środku akapitu. Styl akapitu jest atrybutem całego akapitu,
    /// więc operacje akapitowe nie mogą honorować granic zaznaczenia co do znaku.
    static func enumerateParagraphs(
        of storage: NSTextStorage,
        in range: NSRange,
        _ body: (NSRange) -> Void
    ) {
        let string = storage.string as NSString
        var location = range.location
        while location < NSMaxRange(range) {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            guard paragraph.length > 0 else { break }
            body(paragraph)
            location = NSMaxRange(paragraph)
        }
    }
}
