import AppKit

/// Jedno źródło pozycji formatowania. Menu „Format" w ukrytym menu głównym (skróty
/// klawiszowe) i menu kontekstowe pola tekstu (dostęp myszą) budują pozycje tą samą
/// metodą — lista skrótów i lista pozycji nie mają jak się rozjechać.
///
/// Tam, gdzie AppKit ma gotowy selektor, pozycja celuje w niego zamiast we własny kod:
/// - `addFontTrait:` i `modifyFont:` wykonuje `NSFontManager.shared`; maska cechy albo
///   rodzaj zmiany siedzi w `tag` pozycji, a sama zmiana przechodzi przez
///   `changeFont(_:)` pola tekstu — działa na zaznaczeniu i na `typingAttributes`,
///   z przełączaniem włącz/wyłącz włącznie,
/// - `underline:`, `alignLeft:`, `alignCenter:` i `pasteAsPlainText:` mają cel pusty,
///   czyli „szukaj wykonawcy w łańcuchu responderów" — wykonawcą jest `NSTextView`.
/// Trzy operacje bez odpowiednika w AppKit celują w `FormattingCommands`.
@MainActor
enum FormatMenu {

    static func makeMenu(commands: FormattingCommands) -> NSMenu {
        let menu = NSMenu(title: "Format")
        for item in makeItems(commands: commands) {
            menu.addItem(item)
        }
        return menu
    }

    /// Pozycje w kolejności z tabeli „Formatowanie treści" w FUNKCJONALNOSCI.md.
    ///
    /// Skróty ze znakiem z Shifta (`⌘{`, `⌘|`, `⌥⇧⌘V`) deklarują ten znak wprost
    /// w `keyEquivalent`, bez `.shift` w masce — Shift jest częścią samego znaku.
    /// Zapis z `.shift` w masce kompiluje się i nigdy nie dopasowuje zdarzenia
    /// (pułapka opisana w `MainMenu` przy `⇧⌘Z`).
    static func makeItems(commands: FormattingCommands) -> [NSMenuItem] {
        [
            item("Pogrubienie", #selector(NSFontManager.addFontTrait(_:)), key: "b",
                 target: NSFontManager.shared, tag: Int(NSFontTraitMask.boldFontMask.rawValue)),
            item("Kursywa", #selector(NSFontManager.addFontTrait(_:)), key: "i",
                 target: NSFontManager.shared, tag: Int(NSFontTraitMask.italicFontMask.rawValue)),
            item("Podkreślenie", #selector(NSText.underline(_:)), key: "u"),
            item("Przekreślenie", #selector(FormattingCommands.toggleStrikethrough(_:)),
                 key: "k", modifiers: [.command, .control], target: commands),
            .separator(),
            item("Większa czcionka", #selector(NSFontManager.modifyFont(_:)), key: "+",
                 target: NSFontManager.shared, tag: Int(NSFontAction.sizeUpFontAction.rawValue)),
            item("Mniejsza czcionka", #selector(NSFontManager.modifyFont(_:)), key: "-",
                 target: NSFontManager.shared, tag: Int(NSFontAction.sizeDownFontAction.rawValue)),
            .separator(),
            item("Lista punktowana", #selector(FormattingCommands.toggleBulletedList(_:)),
                 key: "l", modifiers: [.command, .control], target: commands),
            item("Wyrównaj do lewej", #selector(NSText.alignLeft(_:)), key: "{"),
            item("Wyśrodkuj", #selector(NSText.alignCenter(_:)), key: "|"),
            .separator(),
            item("Usuń formatowanie", #selector(FormattingCommands.removeFormatting(_:)),
                 key: "\\", modifiers: [.command, .control], target: commands),
            item("Wklej bez formatowania", #selector(NSTextView.pasteAsPlainText(_:)),
                 key: "V", modifiers: [.command, .option]),
        ]
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil,
        tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        item.tag = tag
        return item
    }
}
