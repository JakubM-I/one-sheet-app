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

    /// Widok tekstu. Kolejne etapy sięgają tu po `NSTextStorage` (zapis)
    /// i po operacje formatowania.
    let textView = NSTextView()

    private let scrollView = NSScrollView()

    override func loadView() {
        configureTextView()
        configureScrollView()
        view = scrollView
    }

    /// Ustawia kursor w tekście. Wywoływane przez panel po pokazaniu okna —
    /// wcześniej `view.window` jest jeszcze `nil` i `makeFirstResponder` nie miałby adresata.
    func focusText() {
        guard let window = view.window else { return }
        if !window.makeFirstResponder(textView) {
            Log.editor.error("Pole tekstu odmówiło przyjęcia fokusu")
        }
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
}
