import AppKit

/// Pole tekstu notatki. Jedyny powód istnienia podklasy: menu kontekstowe z pozycjami
/// formatowania budowanymi z tego samego źródła co menu główne (`FormatMenu`).
final class NoteTextView: NSTextView {

    /// Cel trzech operacji bez standardowego selektora. Słaba referencja — właścicielem
    /// jest `EditorViewController`, ten sam obiekt celuje też z pozycji menu głównego.
    weak var formattingCommands: FormattingCommands?

    /// Standardowe menu kontekstowe `NSTextView` (kopiuj, wklej, pisownia…) plus podmenu
    /// „Formatowanie". Podmenu zamiast luzem doklejonych pozycji, bo systemowe menu jest
    /// już długie, a AppKit swoje grupy (Font, Substitutions) też trzyma w podmenu.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let formattingCommands else { return menu }

        let formatting = NSMenuItem(title: "Formatowanie", action: nil, keyEquivalent: "")
        formatting.submenu = FormatMenu.makeMenu(commands: formattingCommands)
        menu.addItem(.separator())
        menu.addItem(formatting)
        return menu
    }
}
