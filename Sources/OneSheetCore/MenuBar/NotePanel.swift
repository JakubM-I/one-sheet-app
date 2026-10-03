import AppKit

/// Okno notatnika rozwijane spod ikony w belce.
///
/// Powstaje raz, przy starcie aplikacji, i nigdy nie jest niszczone — pokazywanie
/// i chowanie to `orderFrontRegardless()` / `orderOut(nil)`. Budowanie okna od nowa
/// przy każdym otwarciu kosztowałoby więcej niż cały budżet 150 ms.
@MainActor
final class NotePanel: NSPanel {

    /// Wywoływane po schowaniu panelu. Nie jest to jedyny moment zapisu — panel potrafi
    /// stać otwarty tygodniami — ale jest to moment, w którym zapis na pewno wypada zrobić.
    var onHide: (() -> Void)?

    /// Wywoływane po pokazaniu panelu, gdy jest już oknem kluczowym.
    var onPresent: (() -> Void)?

    private let editorViewController: EditorViewController

    /// Czy okno ma już ustaloną pozycję — z `UserDefaults` albo z pierwszego otwarcia.
    /// Dopóki `false`, panel przy otwarciu zaczepia się pod ikoną w belce.
    private var hasResolvedFrame = false

    init(editorViewController: EditorViewController) {
        self.editorViewController = editorViewController

        super.init(
            contentRect: NSRect(origin: .zero, size: AppConfiguration.Panel.defaultSize),
            // `.titled` + `.fullSizeContentView` + przezroczysty pasek tytułu: okno wygląda
            // jak kartka bez ramki, ale zachowuje skalowanie i przeciąganie za górną krawędź.
            // `.nonactivatingPanel` pozwala przyjmować klawiaturę bez aktywowania aplikacji.
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        configureContent()
        restoreFrame()
        observeScreenChanges()
    }

    // Panel musi móc zostać oknem kluczowym, inaczej nie przyjmie klawiatury.
    // Oknem głównym (`main`) być nie powinien — aplikacja `.accessory` nie ma menu głównego,
    // a status okna głównego wpływa na rysowanie paska tytułu innych okien.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Pokazywanie i chowanie

    func toggle(below anchor: NSRect?) {
        if isVisible {
            hide()
        } else {
            present(below: anchor)
        }
    }

    func present(below anchor: NSRect?) {
        // Pomiar całej drogi od wywołania do gotowości na pisanie — budżet ze specyfikacji
        // (sekcja 6) to 150 ms. Wpis w logu pozwala złapać regresję bez profilera.
        let start = ContinuousClock.now

        positionBeforeShowing(below: anchor)

        // `makeKeyAndOrderFront(_:)` z aplikacji nieaktywnej potrafi nie wysunąć okna
        // na wierzch — `orderFrontRegardless()` robi to bez względu na stan aktywacji.
        orderFrontRegardless()
        makeKey()
        editorViewController.focusText()
        onPresent?()

        let elapsed = start.duration(to: .now)
        let milliseconds = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        Log.panel.info("""
            Panel pokazany w \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms \
            (klucz: \(self.isKeyWindow, privacy: .public))
            """)
    }

    func hide() {
        orderOut(nil)
        onHide?()
        Log.panel.info("Panel schowany")
    }

    /// `Esc`, gdy pierwszym responderem nie jest pole tekstu.
    /// Ścieżkę z polem tekstu obsługuje `EditorViewController` — `NSTextView` konsumuje `Esc`.
    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    // MARK: - Konfiguracja okna

    private func configureWindow() {
        title = "one-sheet"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none

        // Panel ma stać otwarty obok innych aplikacji dowolnie długo. Chowa go wyłącznie
        // świadoma akcja użytkownika, więc żadnej reakcji na utratę aktywności.
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false

        // Widoczny na każdym biurku i nieznikający, gdy inna aplikacja wchodzi w pełny ekran.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Przeciąganie za tło kolidowałoby z zaznaczaniem tekstu — zostaje górny pas.
        isMovableByWindowBackground = false

        // Jednolite tło zamiast efektu szkła (rejestr decyzji, 2026-08-05): rozmycie
        // przepuszczało zawartość spod okna i psuło czytelność notatki, zwłaszcza
        // w jasnym motywie. `.textBackgroundColor` to dynamiczny kolor tła dokumentu —
        // biały w jasnym motywie, grafitowy w ciemnym; zaokrąglenie rogów zostaje
        // przy systemie, jak w każdym oknie `.titled`.
        isOpaque = true
        backgroundColor = .textBackgroundColor
        hasShadow = true

        // Panel jest tworzony raz i tylko chowany. Bez tego zamknięcie okna zwolniłoby
        // obiekt, a kolejne otwarcie sięgnęło po zwolnioną pamięć.
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        minSize = AppConfiguration.Panel.minimumSize

        // Kropki sterujące psułyby wygląd kartki, a i tak nie mają tu zastosowania:
        // panelu się nie minimalizuje ani nie rozwija na pełny ekran.
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    private func configureContent() {
        // Zwykły widok-kontener — tło rysuje samo okno (`backgroundColor` wyżej).
        let container = NSView()
        contentView = container

        let editorView = editorViewController.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(editorView)
        NSLayoutConstraint.activate([
            // Bez odstępu na pasek tytułu: jego obszar zajmuje teraz pasek formatowania,
            // który sam przejmuje przeciąganie okna (`FormatBar.mouseDown`).
            editorView.topAnchor.constraint(equalTo: container.topAnchor),
            editorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            editorView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    // MARK: - Ramka okna

    /// AppKit sam zapisuje ramkę do `UserDefaults` po każdej zmianie rozmiaru i pozycji,
    /// ale odtworzenie jej trzeba wywołać ręcznie — `setFrameAutosaveName(_:)` samo
    /// niczego nie wczytuje (robi to tylko dla okien z NIB-a).
    private func restoreFrame() {
        guard setFrameAutosaveName(AppConfiguration.Panel.frameAutosaveName) else {
            Log.panel.error("Nazwa autozapisu ramki odrzucona — pozycja nie przeżyje restartu")
            return
        }
        hasResolvedFrame = setFrameUsingName(AppConfiguration.Panel.frameAutosaveName)
    }

    private func positionBeforeShowing(below anchor: NSRect?) {
        guard let visibleFrame = targetScreen(for: anchor)?.visibleFrame else { return }

        if hasResolvedFrame {
            // Ramka z poprzedniej sesji mogła pochodzić z innego monitora — podłączonego
            // (wtedy panel wraca pod klikniętą ikonę) albo już odłączonego.
            let corrected = PanelGeometry.presentationFrame(
                saved: frame,
                anchor: anchor,
                visibleFrame: visibleFrame,
                gap: AppConfiguration.Panel.gapBelowStatusItem
            )
            if corrected != frame {
                Log.panel.info("Zapamiętana ramka nie pasowała do ekranu docelowego — skorygowana")
                setFrame(corrected, display: false)
            }
        } else {
            setFrame(
                PanelGeometry.initialFrame(
                    size: frame.size,
                    anchor: anchor,
                    visibleFrame: visibleFrame,
                    gap: AppConfiguration.Panel.gapBelowStatusItem
                ),
                display: false
            )
            hasResolvedFrame = true
        }
    }

    /// Ekran, na którym siedzi ikona w belce (przy dwóch monitorach belka jest na obu).
    /// Bez ikony — ekran z aktywnym oknem, a w ostateczności pierwszy z listy.
    private func targetScreen(for anchor: NSRect?) -> NSScreen? {
        guard let anchor else { return NSScreen.main ?? NSScreen.screens.first }
        return NSScreen.screens.first { $0.frame.intersects(anchor) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    // MARK: - Zmiany układu ekranów

    /// Odłączenie monitora lub zmiana rozdzielczości przy **schowanym** panelu jest już
    /// obsłużona — `positionBeforeShowing` przycina ramkę przy każdym pokazaniu. Ta ścieżka
    /// domyka drugą połowę: panel stojący otwarty na monitorze, który właśnie zniknął,
    /// nie może zostać poza wszystkimi ekranami.
    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersDidChange() {
        guard isVisible else { return }
        // `screen` bywa `nil`, gdy okno wisi poza wszystkimi ekranami — czyli dokładnie
        // w przypadku, przed którym się bronimy. Wtedy przyciągamy do ekranu głównego.
        guard let visibleFrame = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return
        }
        let corrected = PanelGeometry.clamped(frame, to: visibleFrame)
        if corrected != frame {
            Log.panel.info("Zmiana układu ekranów — ramka panelu wsunięta w widoczny obszar")
            setFrame(corrected, display: true)
        }
    }
}
