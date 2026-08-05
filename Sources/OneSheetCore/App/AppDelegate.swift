import AppKit

/// Delegat aplikacji. `public`, bo jest jedynym punktem styku biblioteki `OneSheetCore`
/// z targetem wykonywalnym — reszta kodu pozostaje wewnętrzna.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItemController: StatusItemController?
    private var notePanel: NotePanel?
    private let noteStore = NoteStore()

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
        let editor = EditorViewController()
        let panel = NotePanel(editorViewController: editor)

        // Niewidoczne, ale bez niego w polu tekstu nie działa ani `⌘V`, ani `⌘B`.
        // Wyjaśnienie w `MainMenu`; instalacja po utworzeniu edytora, bo menu „Format"
        // celuje w jego `FormattingCommands`.
        MainMenu.install(formatting: editor.formattingCommands)
        editor.onCancel = { [weak panel] in
            panel?.hide()
        }
        // Właścicielem edytora jest panel — tu wystarczy referencja do samego panelu.
        notePanel = panel

        // Najpierw treść, dopiero potem callbacki — wczytanie notatki nie ma prawa
        // wyglądać jak edycja użytkownika. (`restore(...)` blokuje zdarzenia również
        // od środka; to druga warstwa tej samej ochrony.)
        loadNote(into: editor)
        connectAutosave(for: editor, panel: panel)
        observeSystemEvents()

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
        noteStore.flush()
        Log.app.info("Aplikacja kończy działanie")
    }

    private func togglePanel() {
        guard let notePanel else { return }
        notePanel.toggle(below: statusItemController?.buttonFrameOnScreen)
    }

    // MARK: - Trwałość notatki

    private func loadNote(into editor: EditorViewController) {
        let loaded = noteStore.load()
        editor.restore(content: loaded.text, state: loaded.state)
        Log.app.info("Notatka wczytana (\(loaded.text.length, privacy: .public) znaków)")
    }

    private func connectAutosave(for editor: EditorViewController, panel: NotePanel) {
        editor.onTextChange = { [weak self, weak editor] in
            guard let self, let editor else { return }
            noteStore.scheduleSave(editor.content, state: editor.currentState)
        }
        editor.onStateChange = { [weak self, weak editor] in
            guard let self, let editor else { return }
            noteStore.scheduleStateSave(editor.currentState)
        }
        panel.onHide = { [weak self] in
            self?.noteStore.flush()
        }
    }

    /// Momenty, w których system daje ostatnią szansę na zapis.
    ///
    /// Powiadomienia `NSWorkspace` chodzą **własnym** centrum powiadomień, nie domyślnym —
    /// zarejestrowanie ich w `NotificationCenter.default` kompiluje się i po cichu nic nie robi.
    private func observeSystemEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(flushNote),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.willPowerOffNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(flushNote),
                name: name,
                object: nil
            )
        }
    }

    @objc private func flushNote() {
        noteStore.flush()
    }

    // MARK: - Miejsca na kolejne etapy

    /// Etap 4: menu z pozycjami „Uruchamiaj przy logowaniu" i „Zakończ".
    private func showContextMenu() {
        Log.app.info("showContextMenu() — menu powstaje w etapie 4")
    }
}
