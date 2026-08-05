import AppKit

/// Menu główne aplikacji — nigdy niewyświetlane, a mimo to konieczne.
///
/// W AppKit standardowe skróty edycyjne (`⌘V`, `⌘C`, `⌘X`, `⌘A`, `⌘Z`) **nie są** wiązaniami
/// klawiszy `NSTextView`. Nie ma ich w `StandardKeyBinding.dict` — pochodzą wyłącznie
/// z `keyEquivalent` pozycji menu „Edycja". Aplikacja bez menu głównego dostaje więc pole
/// tekstu, w którym nie da się wkleić ani cofnąć, choć menu kontekstowe działa (to inna
/// ścieżka: pozycje wywołują `paste(_:)` bezpośrednio na polu tekstu).
///
/// Aplikacja `.accessory` nie ma paska menu, więc tego menu nikt nigdy nie zobaczy.
/// `NSApplication.sendEvent(_:)` mimo to odpytuje je przez `performKeyEquivalent(with:)`,
/// zanim odda zdarzenie oknu kluczowemu — i to wystarczy, żeby skróty działały.
/// Sprawdzone pomiarem: bez menu `⌘A` zaznacza 0 z 15 znaków, z menu — 15 z 15.
///
/// Pozycje nie mają celu (`target`). Puste `target` znaczy „szukaj wykonawcy w łańcuchu
/// responderów", a tam siedzi `NSTextView` — to on wykonuje `paste(_:)` i to on decyduje
/// przez `validateUserInterfaceItem(_:)`, czy pozycja jest w danej chwili aktywna
/// (np. `⌘V` przy pustym schowku nie zrobi nic).
@MainActor
enum MainMenu {

    /// Menu „Format" celuje w przekazany `FormattingCommands` (trzy operacje bez
    /// standardowego selektora), więc instalacja wymaga istniejącego edytora.
    static func install(formatting: FormattingCommands) {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        editItem.submenu = makeEditMenu()
        mainMenu.addItem(editItem)

        let formatItem = NSMenuItem()
        formatItem.submenu = FormatMenu.makeMenu(commands: formatting)
        mainMenu.addItem(formatItem)

        NSApp.mainMenu = mainMenu
    }

    private static func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edycja")

        // `undo:` i `redo:` nie są zadeklarowane w żadnym protokole widocznym ze Swifta —
        // obsługuje je `NSWindow`, przekazując do `undoManager` pierwszego respondera.
        // Stąd selektor budowany z napisu zamiast `#selector(...)`.
        menu.addItem(withTitle: "Cofnij", action: Selector(("undo:")), keyEquivalent: "z")

        // `⇧⌘Z` deklaruje się **wielką** literą przy masce samego `.command`, a nie małą
        // literą z maską `[.command, .shift]`. Ten drugi zapis wygląda naturalniej, kompiluje
        // się i po prostu nigdy nie dopasowuje zdarzenia — sprawdzone pomiarem: `canRedo`
        // pozostawało `true` po naciśnięciu skrótu. Shift jest częścią samego znaku.
        menu.addItem(withTitle: "Ponów", action: Selector(("redo:")), keyEquivalent: "Z")

        menu.addItem(.separator())

        menu.addItem(withTitle: "Wytnij", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Kopiuj", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Wklej", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Usuń", action: #selector(NSText.delete(_:)), keyEquivalent: "")

        menu.addItem(.separator())

        menu.addItem(withTitle: "Zaznacz wszystko", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        return menu
    }
}
