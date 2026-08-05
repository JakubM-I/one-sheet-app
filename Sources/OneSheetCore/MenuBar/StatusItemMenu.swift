import AppKit

/// Menu kontekstowe ikony w belce (prawy przycisk / `⌃`-klik).
///
/// Budowane od nowa przy każdym otwarciu: stan autostartu może się zmienić poza
/// aplikacją (Ustawienia systemowe), więc trzymanie gotowego `NSMenu` oznaczałoby
/// rysowanie nieaktualnego ptaszka. Konstrukcja jest sterowana czystym modelem,
/// żeby dała się sprawdzić testem bez belki systemowej i bez okien.
@MainActor
enum StatusItemMenu {

    /// Stan świata w chwili otwarcia menu — wszystko, czego potrzeba do narysowania pozycji.
    struct Model {
        /// Autostart faktycznie włączony w systemie (`SMAppService.status == .enabled`).
        var launchAtLoginEnabled = false

        /// Linia informacyjna pod przełącznikiem autostartu: odrzucona rejestracja
        /// albo oczekiwanie na zgodę w Ustawieniach systemowych. `nil` — bez linii.
        var launchAtLoginNotice: String?

        /// Komunikat o niedostępnym skrócie globalnym; `nil`, gdy skrót działa.
        var hotKeyNotice: String?
    }

    static func makeMenu(model: Model, target: AnyObject?, toggleLaunchAtLoginAction: Selector) -> NSMenu {
        let menu = NSMenu()

        let launchItem = NSMenuItem(
            title: "Uruchamiaj przy logowaniu",
            action: toggleLaunchAtLoginAction,
            keyEquivalent: ""
        )
        launchItem.target = target
        launchItem.state = model.launchAtLoginEnabled ? .on : .off
        menu.addItem(launchItem)

        if let notice = model.launchAtLoginNotice {
            menu.addItem(makeNotice(notice))
        }
        if let notice = model.hotKeyNotice {
            menu.addItem(.separator())
            menu.addItem(makeNotice(notice))
        }

        menu.addItem(.separator())

        // Bez celu — akcja idzie łańcuchem responderów, który dla menu ikony statusu
        // kończy się na `NSApplication`. Zapis flush wykonuje `applicationWillTerminate`.
        menu.addItem(
            withTitle: "Zakończ",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )

        return menu
    }

    /// Pozycja czysto informacyjna: bez akcji, więc `NSMenu` (przy domyślnym
    /// `autoenablesItems`) trzyma ją stale wyszarzoną i nieklikalną.
    private static func makeNotice(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
