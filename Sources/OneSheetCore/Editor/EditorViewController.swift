import AppKit

/// Pole tekstu wypełniające panel: `NSScrollView` z `NSTextView` w środku.
///
/// Kontroler powstaje raz, przy starcie aplikacji, i żyje tak długo jak panel.
/// Treść notatki mieszka w `NSTextStorage` widoku tekstu — panel niczego nie
/// przeładowuje przy otwieraniu (patrz sekcja 6 specyfikacji: cel <150 ms).
@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate {

    /// Wywoływane po naciśnięciu `Esc` w polu tekstu.
    var onCancel: (() -> Void)?

    /// Zmiana treści notatki.
    var onTextChange: (() -> Void)?

    /// Zmiana samej pozycji kursora lub przewinięcia — treść bez zmian.
    var onStateChange: (() -> Void)?

    /// Widok tekstu. Etap 3 sięga tu po operacje formatowania.
    let textView = NSTextView()

    private let scrollView = NSScrollView()

    /// Blokada zdarzeń w trakcie wczytywania notatki. Bez niej ustawienie treści i kursora
    /// zaraz po starcie wyglądałoby jak edycja użytkownika i uruchamiało zapis tego,
    /// co przed chwilą zostało wczytane.
    private var isRestoring = false

    /// Stan sesji czekający na moment, w którym da się go zastosować.
    /// Patrz `restoreViewportIfNeeded()`.
    private var viewportToRestore: EditorState?

    /// Odróżnia przewinięcie wykonane przez nas od przewinięcia wykonanego przez użytkownika.
    private var isApplyingViewport = false

    override func loadView() {
        configureTextView()
        configureScrollView()
        observeScrolling()
        view = scrollView
    }

    // MARK: - Treść i stan sesji

    /// Żywy `NSTextStorage` pola tekstu, nie jego kopia — `NoteStore` serializuje go
    /// dopiero w chwili zapisu (patrz komentarz przy `NoteStore.pendingText`).
    var content: NSAttributedString { textView.textStorage ?? NSAttributedString() }

    var currentState: EditorState {
        let selection = textView.selectedRange()
        return EditorState(
            selectionLocation: selection.location,
            selectionLength: selection.length,
            scrollOffset: scrollView.contentView.bounds.origin.y
        )
    }

    /// Wstawia wczytaną notatkę i przywraca miejsce, w którym użytkownik skończył.
    func restore(content: NSAttributedString, state: EditorState?) {
        isRestoring = true
        defer { isRestoring = false }

        textView.textStorage?.setAttributedString(content)
        // Wczytanie notatki nie jest edycją — `⌘Z` tuż po starcie nie ma czego cofać.
        textView.undoManager?.removeAllActions()

        guard let state else { return }
        restoreSelection(state)

        // Przewinięcie zostaje na później: w tym momencie panel jeszcze nie był pokazany,
        // więc TextKit nie rozłożył ani jednej linii i nie ma się do czego przewinąć.
        viewportToRestore = state
        observeFirstAppearance()
    }

    /// Zaznaczenie z poprzedniej sesji trzeba przyciąć do długości tekstu: po odtworzeniu
    /// z kopii zapasowej treść bywa krótsza niż wtedy, gdy zapisywano `state.json`,
    /// a `setSelectedRange` poza zakresem to wyjątek, nie ostrzeżenie.
    private func restoreSelection(_ state: EditorState) {
        let length = textView.textStorage?.length ?? 0
        let location = min(max(0, state.selectionLocation), length)
        let selectionLength = min(max(0, state.selectionLength), length - location)
        textView.setSelectedRange(NSRange(location: location, length: selectionLength))
    }

    /// Nasłuch na pierwsze pokazanie panelu — jedyny moment, w którym przewinięcie ma sens.
    ///
    /// `viewDidAppear()` tu nie zadziała: widok edytora jest wstawiany jako podwidok tła
    /// panelu, więc kontroler nie trafia do łańcucha responderów okna (patrz dług techniczny
    /// etapu 1). Zostaje powiadomienie od samego okna.
    private func observeFirstAppearance() {
        guard let window = textView.window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
    }

    @objc private func panelDidBecomeKey() {
        restoreViewportIfNeeded()
    }

    /// Przywraca przewinięcie z poprzedniej sesji. Wykonuje się dokładnie raz.
    ///
    /// Problem: zaraz po wczytaniu treści `NSTextView` ma jeszcze wysokość sprzed rozłożenia
    /// tekstu, więc przewinięcie o 6000 pt zostałoby przycięte do kilkuset. TextKit 2 rozkłada
    /// tekst leniwie — dopóki nikt nie poprosi o konkretny fragment, nie istnieje on w układzie.
    ///
    /// Rozwiązanie w dwóch krokach. `scrollRangeToVisible(_:)` na zapamiętanym zaznaczeniu
    /// zmusza TextKit do rozłożenia tekstu aż do kursora i przewija w jego okolice — to jest
    /// ta część, która działa zawsze. Dopiero potem ustawiamy dokładny offset, o ile dokument
    /// sięga tak daleko.
    ///
    /// Odrzucone: `NSTextLayoutManager.ensureLayout(for:)` na całym dokumencie. Dla notatki
    /// na 200 000 znaków to sekundy pracy przy każdym starcie — a rozkładany jest wtedy również
    /// tekst, którego użytkownik nigdy nie zobaczy.
    private func restoreViewportIfNeeded() {
        guard let state = viewportToRestore else { return }
        viewportToRestore = nil
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: textView.window
        )

        isApplyingViewport = true
        defer { isApplyingViewport = false }

        textView.scrollRangeToVisible(textView.selectedRange())

        // Przycięcie do tego, co da się osiągnąć: rozłożony jest tekst do kursora, więc
        // przewinięcie zapamiętane dalej niż kursor po prostu dosuwa widok najdalej, jak można.
        let clipView = scrollView.contentView
        let reachable = max(0, textView.frame.height - clipView.bounds.height)
        clipView.scroll(to: NSPoint(x: 0, y: min(state.scrollOffset, reachable)))
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Ustawia kursor w tekście. Wywoływane przez panel po pokazaniu okna —
    /// wcześniej `view.window` jest jeszcze `nil` i `makeFirstResponder` nie miałby adresata.
    func focusText() {
        guard let window = view.window else { return }
        if !window.makeFirstResponder(textView) {
            Log.editor.error("Pole tekstu odmówiło przyjęcia fokusu")
        }
        // Druga droga do przywrócenia przewinięcia, na wypadek gdyby panel został pokazany
        // bez stania się oknem kluczowym. Metoda i tak wykona się tylko raz.
        restoreViewportIfNeeded()
    }

    // MARK: - Konfiguracja

    private func configureTextView() {
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        // Pasek wyszukiwania to funkcja spoza zakresu (patrz FUNKCJONALNOSCI.md).
        textView.usesFindBar = false
        // Cudzysłowy typograficzne psują wklejany kod. Zamiana tekstu i sprawdzanie
        // pisowni zostają — są w zakresie jako standardowe usługi systemowe.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.delegate = self

        // Tło rysuje `NSVisualEffectView` panelu. Gdyby widok tekstu malował swoje,
        // przykryłby rozmycie jednolitą płaszczyzną.
        textView.drawsBackground = false
        textView.textContainerInset = AppConfiguration.Editor.textInset
        textView.font = .systemFont(ofSize: AppConfiguration.Editor.fontSize)
        // `.labelColor` jest kolorem dynamicznym — sam przełącza się z motywem systemu.
        textView.textColor = .labelColor
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: AppConfiguration.Editor.fontSize),
            .foregroundColor: NSColor.labelColor,
        ]

        // Klasyczny zestaw dla NSTextView w NSScrollView: szerokość podąża za widokiem,
        // wysokość rośnie z treścią w nieskończoność (przewijanie w pionie).
        textView.frame = NSRect(origin: .zero, size: AppConfiguration.Panel.defaultSize)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: AppConfiguration.Panel.defaultSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    private func configureScrollView() {
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        // AppKit sam dokłada wcięcie pod przezroczysty pasek tytułu okna
        // `.fullSizeContentView`. Tutaj jest zbędne — widok edytora i tak zaczyna się
        // dopiero pod paskiem — a psuje arytmetykę przewijania: „na samej górze" znaczy
        // wtedy `bounds.origin.y == -4`, a nie zero.
        scrollView.automaticallyAdjustsContentInsets = false
    }

    /// Przewinięcie nie ma delegata ani akcji — jedyny sposób, żeby się o nim dowiedzieć,
    /// to powiadomienie o zmianie `bounds` warstwy przewijanej (`NSClipView`).
    private func observeScrolling() {
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @objc private func clipViewDidScroll() {
        guard !isApplyingViewport, !isRestoring else { return }
        onStateChange?()
    }

    // MARK: - NSTextViewDelegate

    /// Przechwycenie `Esc`.
    ///
    /// Samo nadpisanie `cancelOperation(_:)` w oknie nie wystarcza: `NSTextView`
    /// konsumuje `Esc` na podpowiadanie słów (`complete:`) i zdarzenie nigdy nie dochodzi
    /// do panelu. Delegat dostaje polecenie wcześniej niż domyślna implementacja,
    /// więc to jedyne pewne miejsce, żeby je przejąć.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        let isCancel = commandSelector == #selector(NSResponder.cancelOperation(_:))
            || commandSelector == #selector(NSStandardKeyBindingResponding.complete(_:))
        guard isCancel else { return false }

        onCancel?()
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard !isRestoring else { return }
        onTextChange?()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isRestoring else { return }
        onStateChange?()
    }
}
