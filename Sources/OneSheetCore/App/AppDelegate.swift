import AppKit

/// Delegat aplikacji. `public`, bo jest jedynym punktem styku biblioteki `OneSheetCore`
/// z targetem wykonywalnym — reszta kodu pozostaje wewnętrzna.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItemController: StatusItemController?
    private var notePanel: NotePanel?
    private let noteStore = NoteStore()
    private let launchAtLogin = LaunchAtLogin()
    private var globalHotKey: HotKeyRegistering?
    private let outsideClickMonitor = OutsideClickMonitor()

    /// Komunikat o niedostępnym skrócie globalnym — pokazywany w menu kontekstowym.
    /// `nil`, gdy skrót został zarejestrowany albo jest wyłączony w ustawieniach.
    private var hotKeyNotice: String?

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
        connectOutsideClickDismissal(for: panel)
        observeSystemEvents()

        let controller = StatusItemController()
        controller.onPrimaryAction = { [weak self] in
            self?.togglePanel()
        }
        controller.onSecondaryAction = { [weak self] in
            self?.showContextMenu()
        }
        statusItemController = controller

        registerGlobalHotKey()
        launchAtLogin.reconcileOnLaunch()

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
            self?.outsideClickMonitor.stop()
        }
    }

    // MARK: - Chowanie po kliknięciu poza panelem

    private var hidesOnClickOutside: Bool {
        get { UserDefaults.standard.bool(forKey: AppConfiguration.Defaults.hidesOnClickOutside) }
        set { UserDefaults.standard.set(newValue, forKey: AppConfiguration.Defaults.hidesOnClickOutside) }
    }

    /// Monitor słucha tylko wtedy, gdy panel jest widoczny i tryb szybki włączony —
    /// przy schowanym panelu żadne kliknięcie w systemie nie budzi aplikacji.
    /// Zdejmowanie monitora siedzi w `onHide` (`connectAutosave`), bo każda droga
    /// schowania — ikona, `Esc`, skrót, klik poza panelem — przechodzi przez `hide()`.
    private func connectOutsideClickDismissal(for panel: NotePanel) {
        outsideClickMonitor.onOutsideClick = { [weak panel] in
            panel?.hide()
        }
        panel.onPresent = { [weak self] in
            guard let self, hidesOnClickOutside else { return }
            outsideClickMonitor.start()
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

    // MARK: - Integracja z systemem

    /// Skrót działa bez żadnych uprawnień. Nieudana rejestracja (najczęściej kombinacja
    /// zajęta przez inną aplikację) nie wywraca aplikacji — funkcja zostaje wyłączona,
    /// komunikat trafia do menu kontekstowego, a panel dalej otwiera klik w ikonę
    /// (plan awaryjny ze specyfikacji, sekcja 8).
    private func registerGlobalHotKey() {
        if let enabled = UserDefaults.standard.object(forKey: AppConfiguration.Defaults.hotKeyEnabled) as? Bool,
           !enabled {
            Log.app.info("Skrót globalny wyłączony w ustawieniach — pomijam rejestrację")
            return
        }

        let hotKey = GlobalHotKey()
        hotKey.onHotKey = { [weak self] in
            self?.togglePanel()
        }
        do {
            try hotKey.register()
            globalHotKey = hotKey
        } catch {
            hotKeyNotice = "Skrót \(AppConfiguration.HotKey.displayName) niedostępny"
            Log.app.error("Rejestracja skrótu globalnego nieudana: \(String(describing: error), privacy: .public)")
        }
    }

    private func showContextMenu() {
        var model = StatusItemMenu.Model()
        model.launchAtLoginEnabled = launchAtLogin.isEnabled
        if launchAtLogin.requiresApproval {
            model.launchAtLoginNotice = "Czeka na zgodę w Ustawieniach systemowych"
        } else if let failure = launchAtLogin.lastFailureDescription {
            model.launchAtLoginNotice = "Autostart niedostępny: \(failure)"
        }
        model.hotKeyNotice = hotKeyNotice
        model.hidesOnClickOutside = hidesOnClickOutside

        let menu = StatusItemMenu.makeMenu(
            model: model,
            target: self,
            toggleLaunchAtLoginAction: #selector(toggleLaunchAtLogin),
            toggleHidesOnClickOutsideAction: #selector(toggleHidesOnClickOutside)
        )
        statusItemController?.showMenu(menu)
    }

    @objc private func toggleLaunchAtLogin() {
        launchAtLogin.toggle()
    }

    /// Zmiana działa od razu, także na panelu, który właśnie stoi otwarty.
    @objc private func toggleHidesOnClickOutside() {
        hidesOnClickOutside.toggle()
        Log.app.info("Chowanie po kliknięciu poza panelem: \(self.hidesOnClickOutside, privacy: .public)")
        if hidesOnClickOutside, notePanel?.isVisible == true {
            outsideClickMonitor.start()
        } else if !hidesOnClickOutside {
            outsideClickMonitor.stop()
        }
    }
}
