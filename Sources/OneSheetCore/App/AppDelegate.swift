import AppKit

/// Delegat aplikacji. `public`, bo jest jedynym punktem styku biblioteki `OneSheetCore`
/// z targetem wykonywalnym — reszta kodu pozostaje wewnętrzna.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItemController: StatusItemController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // `.accessory`: brak ikony w Docku, brak udziału w `⌘Tab`, brak menu głównego.
        // Ustawiamy to również w kodzie, a nie tylko przez `LSUIElement` w Info.plist —
        // dzięki temu binarka uruchomiona spoza pakietu `.app` zachowuje się tak samo.
        NSApp.setActivationPolicy(.accessory)

        let controller = StatusItemController()
        controller.onPrimaryAction = { [weak self] in
            self?.togglePanel()
        }
        controller.onSecondaryAction = { [weak self] in
            self?.showContextMenu()
        }
        statusItemController = controller

        Log.app.info("Aplikacja uruchomiona")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        Log.app.info("Aplikacja kończy działanie")
    }

    // MARK: - Miejsca na kolejne etapy

    /// Etap 1: otwarcie/zamknięcie panelu z notatnikiem.
    private func togglePanel() {
        Log.app.info("togglePanel() — panel powstaje w etapie 1")
    }

    /// Etap 4: menu z pozycjami „Uruchamiaj przy logowaniu" i „Zakończ".
    private func showContextMenu() {
        Log.app.info("showContextMenu() — menu powstaje w etapie 4")
    }
}
