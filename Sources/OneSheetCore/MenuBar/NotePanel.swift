import AppKit

/// Okno notatnika rozwijane spod ikony w belce.
///
/// Powstaje raz, przy starcie aplikacji, i nigdy nie jest niszczone — pokazywanie
/// i chowanie to `orderFrontRegardless()` / `orderOut(nil)`. Budowanie okna od nowa
/// przy każdym otwarciu kosztowałoby więcej niż cały budżet 150 ms.
@MainActor
final class NotePanel: NSPanel {

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
        positionBeforeShowing(below: anchor)

        // `makeKeyAndOrderFront(_:)` z aplikacji nieaktywnej potrafi nie wysunąć okna
        // na wierzch — `orderFrontRegardless()` robi to bez względu na stan aktywacji.
        orderFrontRegardless()
        makeKey()
        editorViewController.focusText()

        Log.panel.info("Panel pokazany (klucz: \(self.isKeyWindow, privacy: .public))")
    }

    func hide() {
        orderOut(nil)
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

        // Tło maluje `NSVisualEffectView`; okno musi być przezroczyste, żeby rozmycie
        // sięgało zawartości pod spodem, a rogi okna nie były podbite prostokątem.
        isOpaque = false
        backgroundColor = .clear
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
        let background = NSVisualEffectView()
        background.material = .popover
        // `.behindWindow` rozmywa to, co jest **pod** oknem. `.withinWindow` rozmywałoby
        // własną zawartość panelu, czyli tekst notatki.
        background.blendingMode = .behindWindow
        // `.active` wymusza pełne rozmycie także wtedy, gdy aplikacja jest nieaktywna —
        // a nasza jest nieaktywna niemal zawsze.
        background.state = .active
        contentView = background

        let editorView = editorViewController.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(editorView)
        NSLayoutConstraint.activate([
            // Górny odstęp to niewidoczny pasek tytułu: pod nim tekst byłby zasłonięty
            // przez obszar przeciągania i nie dałoby się w niego kliknąć.
            editorView.topAnchor.constraint(
                equalTo: background.topAnchor,
                constant: AppConfiguration.Panel.dragStripHeight
            ),
            editorView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            editorView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
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
            // Ramka z poprzedniej sesji mogła pochodzić z monitora, którego już nie ma.
            let corrected = PanelGeometry.clamped(frame, to: visibleFrame)
            if corrected != frame {
                Log.panel.info("Zapamiętana ramka wykraczała poza ekran — skorygowana")
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
}
