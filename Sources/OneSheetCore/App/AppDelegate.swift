import AppKit

/// Delegat aplikacji. `public`, bo jest jedynym punktem styku biblioteki `OneSheetCore`
/// z targetem wykonywalnym — reszta kodu pozostaje wewnętrzna.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItemController: StatusItemController?
    private var notePanel: NotePanel?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // `.accessory`: brak ikony w Docku, brak udziału w `⌘Tab`, brak menu głównego.
        // Ustawiamy to również w kodzie, a nie tylko przez `LSUIElement` w Info.plist —
        // dzięki temu binarka uruchomiona spoza pakietu `.app` zachowuje się tak samo.
        NSApp.setActivationPolicy(.accessory)

        // Panel i edytor powstają przy starcie, a nie przy pierwszym kliknięciu:
        // otwarcie ma być samym pokazaniem gotowego okna (specyfikacja, sekcja 6).
        // Okno nie jest tu pokazywane, więc start nie odbiera fokusu innej aplikacji.
        let editorViewController = EditorViewController()
        let panel = NotePanel(editorViewController: editorViewController)
        editorViewController.onCancel = { [weak panel] in
            panel?.hide()
        }
        notePanel = panel

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

    private func togglePanel() {
        guard let notePanel else { return }
        notePanel.toggle(below: statusItemController?.buttonFrameOnScreen)
    }

    // MARK: - Miejsca na kolejne etapy

    /// Etap 4: menu z pozycjami „Uruchamiaj przy logowaniu" i „Zakończ".
    private func showContextMenu() {
        Log.app.info("showContextMenu() — menu powstaje w etapie 4")
    }
}
