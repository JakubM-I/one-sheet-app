import AppKit

/// Pasek z sześcioma najczęstszymi operacjami formatowania, tuż nad polem tekstu.
///
/// Przyciski nie mają własnej logiki formatowania. Cel i akcję każdego z nich bierzemy
/// z `FormatMenu.makeItems(commands:)` — z tego samego źródła, z którego powstaje menu
/// kontekstowe i skróty klawiszowe. Kliknięcie przycisku wykonuje dokładnie ten kod,
/// co odpowiedni skrót, bo nie ma tu drugiej ścieżki, która mogłaby się rozjechać.
///
/// Stan („B" podświetlone, gdy kursor stoi w pogrubionym tekście) czytamy z `FormattingState`,
/// czyli znów tam, gdzie decyduje o nim samo przełączanie.
@MainActor
final class FormatBar: NSView {

    /// Czego szukamy w menu i jak sprawdzić, czy dana operacja jest w tej chwili włączona.
    ///
    /// Kluczem jest para (akcja, `tag`), a nie sama akcja: pogrubienie i kursywa dzielą
    /// selektor `addFontTrait:` i różnią się wyłącznie maską cechy zapisaną w `tag`.
    private struct Command {
        let symbolName: String
        let action: Selector
        let tag: Int
        /// `nil` dla przycisków, które nie są przełącznikami — „usuń formatowanie"
        /// nie ma stanu włączonego, jest jednorazowym działaniem.
        let isActive: (@MainActor (NSTextView) -> Bool)?
    }

    /// Gotowy przycisk wraz z celem, do którego ma trafić jego akcja. Cel jest zapamiętany
    /// przy budowie, bo `NSMenuItem` nie żyje dłużej niż wywołanie `FormatMenu.makeItems`.
    private struct Binding {
        let button: NSButton
        let action: Selector
        /// `nil` znaczy „szukaj wykonawcy w łańcuchu responderów" — tak samo jak w menu.
        let target: AnyObject?
        let isActive: (@MainActor (NSTextView) -> Bool)?
    }

    private weak var textView: NSTextView?
    private var bindings: [Binding] = []

    /// Włos oddzielający pasek od treści.
    private let separator = NSView()

    /// Ochrona przed wielokrotnym odczytem atrybutów w jednym obrocie pętli zdarzeń.
    private var isRefreshScheduled = false

    init(textView: NSTextView, formattingCommands: FormattingCommands) {
        self.textView = textView
        super.init(frame: .zero)

        bindings = Self.makeBindings(formattingCommands: formattingCommands)
        for binding in bindings {
            binding.button.target = self
            binding.button.action = #selector(runCommand(_:))
        }

        configureLayout()
        observe(textView)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FormatBar powstaje wyłącznie w kodzie")
    }

    // MARK: - Zestaw przycisków

    private static func makeCommands() -> [Command] {
        [
            Command(
                symbolName: "bold",
                action: #selector(NSFontManager.addFontTrait(_:)),
                tag: Int(NSFontTraitMask.boldFontMask.rawValue),
                isActive: { textView in
                    FormattingState.hasTrait(.boldFontMask, in: textView, range: textView.selectedRange())
                }
            ),
            Command(
                symbolName: "italic",
                action: #selector(NSFontManager.addFontTrait(_:)),
                tag: Int(NSFontTraitMask.italicFontMask.rawValue),
                isActive: { textView in
                    FormattingState.hasTrait(.italicFontMask, in: textView, range: textView.selectedRange())
                }
            ),
            Command(
                symbolName: "underline",
                action: #selector(NSText.underline(_:)),
                tag: 0,
                isActive: { textView in
                    FormattingState.isSet(.underlineStyle, in: textView, range: textView.selectedRange())
                }
            ),
            Command(
                symbolName: "strikethrough",
                action: #selector(FormattingCommands.toggleStrikethrough(_:)),
                tag: 0,
                isActive: { textView in
                    FormattingState.isSet(.strikethroughStyle, in: textView, range: textView.selectedRange())
                }
            ),
            Command(
                symbolName: "list.bullet",
                action: #selector(FormattingCommands.toggleBulletedList(_:)),
                tag: 0,
                isActive: { textView in
                    guard let storage = textView.textStorage else { return false }
                    let paragraphs = (storage.string as NSString)
                        .paragraphRange(for: textView.selectedRange())
                    return FormattingState.isBulleted(in: textView, paragraphs: paragraphs)
                }
            ),
            Command(
                symbolName: "eraser",
                action: #selector(FormattingCommands.removeFormatting(_:)),
                tag: 0,
                isActive: nil
            ),
        ]
    }

    private static func makeBindings(formattingCommands: FormattingCommands) -> [Binding] {
        let items = FormatMenu.makeItems(commands: formattingCommands)

        return makeCommands().compactMap { command in
            guard let item = items.first(where: { $0.action == command.action && $0.tag == command.tag }) else {
                // Nie przerywamy budowy paska: brak jednej pozycji to brak jednego przycisku,
                // a nie aplikacja bez edytora. Pozostałe drogi do formatowania i tak działają.
                Log.editor.error("""
                    Pozycja menu dla \(command.symbolName, privacy: .public) nie znaleziona — \
                    przycisk pominięty
                    """)
                return nil
            }

            return Binding(
                button: makeButton(for: command, item: item),
                action: command.action,
                target: item.target,
                isActive: command.isActive
            )
        }
    }

    private static func makeButton(for command: Command, item: NSMenuItem) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .accessoryBar
        // Przełączniki trzymają stan włączenia; „usuń formatowanie" wraca sam do spoczynku.
        button.setButtonType(command.isActive == nil ? .momentaryPushIn : .pushOnPushOff)
        // Obwódka tylko pod kursorem — pasek ma być rzędem ikon, nie rzędem klawiszy.
        button.showsBorderOnlyWhileMouseInside = true
        // Bez tego kliknięcie zabrałoby fokus polu tekstu i zniknęłoby zaznaczenie,
        // które użytkownik właśnie chce sformatować.
        button.refusesFirstResponder = true

        if let image = NSImage(systemSymbolName: command.symbolName, accessibilityDescription: item.title) {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            Log.editor.error("Brak symbolu \(command.symbolName, privacy: .public) — przycisk opisowy")
            button.title = item.title
            button.imagePosition = .noImage
        }

        // Podpowiedź uczy skrótu, więc pasek z czasem staje się zbędny — o to chodzi.
        button.toolTip = "\(item.title) (\(shortcutDescription(of: item)))"
        button.setAccessibilityLabel(item.title)

        // `tag` należy do `NSFontManager` — to z niego `addFontTrait:` czyta maskę cechy.
        button.tag = item.tag
        return button
    }

    /// Zapis skrótu w kolejności przyjętej przez Apple: `⌃⌥⇧⌘`.
    private static func shortcutDescription(of item: NSMenuItem) -> String {
        var description = ""
        let modifiers = item.keyEquivalentModifierMask
        if modifiers.contains(.control) { description += "⌃" }
        if modifiers.contains(.option) { description += "⌥" }
        if modifiers.contains(.shift) { description += "⇧" }
        if modifiers.contains(.command) { description += "⌘" }
        return description + item.keyEquivalent.uppercased()
    }

    // MARK: - Wykonanie

    /// Przycisk nie wywołuje akcji wprost — przekazuje ją tam, gdzie celuje pozycja menu.
    ///
    /// Pozycja z pustym celem (`underline:`) znaczy „szukaj wykonawcy w łańcuchu responderów",
    /// a `NSApp.sendAction(_:to:from:)` z `to: nil` robi dokładnie to samo. Nadawcą zostaje
    /// przycisk, bo `NSFontManager.addFontTrait(_:)` czyta maskę cechy z jego `tag`.
    /// Przejście przez tę metodę daje też jedyny pewny moment na odświeżenie stanu przy
    /// pustym zaznaczeniu — zmieniają się wtedy same `typingAttributes`.
    @objc private func runCommand(_ sender: NSButton) {
        guard let binding = bindings.first(where: { $0.button === sender }) else { return }
        NSApp.sendAction(binding.action, to: binding.target, from: sender)
        refresh()
    }

    // MARK: - Przeciąganie okna

    /// Pasek jest jednocześnie uchwytem do przesuwania panelu.
    ///
    /// Leży na obszarze niewidocznego paska tytułu, a zwykły `NSView` zwraca w `hitTest`
    /// samego siebie — gdyby nie ta metoda, pasek połknąłby przeciąganie i okna nie dałoby
    /// się ruszyć. Przyciski obsługują swoje kliknięcia same i tu nie docierają, więc
    /// chwycić można wszędzie poza ikoną.
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    // MARK: - Stan

    /// Odświeżenie po zdarzeniu, które mogło zmienić formatowanie pod kursorem.
    ///
    /// Jedno naciśnięcie klawisza potrafi wysłać trzy powiadomienia naraz (zmiana treści,
    /// zaznaczenia i atrybutów wpisywania), a odczyt atrybutów przy dużym zaznaczeniu nie
    /// jest darmowy — dlatego wykonujemy go raz, po opróżnieniu bieżącej kolejki zdarzeń.
    @objc private func scheduleRefresh() {
        guard !isRefreshScheduled else { return }
        isRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.isRefreshScheduled = false
            self?.refresh()
        }
    }

    /// Wewnętrzna, a nie prywatna, bo poza pętlą zdarzeń (w testach) nie ma kto wykonać
    /// odłożonego odświeżenia z `scheduleRefresh()`.
    func refresh() {
        guard let textView else { return }
        let isEditable = textView.isEditable

        for binding in bindings {
            binding.button.isEnabled = isEditable
            guard let isActive = binding.isActive else { continue }
            binding.button.state = isActive(textView) ? .on : .off
        }
    }

    /// Trzy drogi, którymi formatowanie pod kursorem może się zmienić: ruch kursora,
    /// edycja treści lub atrybutów oraz przełączenie cechy przy pustym zaznaczeniu
    /// (wtedy zmieniają się wyłącznie `typingAttributes`).
    private func observe(_ textView: NSTextView) {
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(scheduleRefresh),
            name: NSTextView.didChangeSelectionNotification, object: textView
        )
        center.addObserver(
            self, selector: #selector(scheduleRefresh),
            name: NSTextView.didChangeTypingAttributesNotification, object: textView
        )
        if let storage = textView.textStorage {
            center.addObserver(
                self, selector: #selector(scheduleRefresh),
                name: NSTextStorage.didProcessEditingNotification, object: storage
            )
        }
    }

    // MARK: - Układ

    private func configureLayout() {
        let stack = NSStackView(views: bindings.map(\.button))
        stack.orientation = .horizontal
        stack.spacing = AppConfiguration.Editor.formatBarSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // Bez włosa ikony wyglądają jak zawieszone nad pierwszą linijką notatki —
        // tło paska i tło tekstu to jeden kolor.
        //
        // Zwykły widok, a nie `NSBox` z `boxType = .separator`: ten ostatni ma własną
        // wysokość 5 pt i wystawałby 2 pt na pole tekstu, przechwytując tam kliknięcia.
        separator.wantsLayer = true
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        updateSeparatorColor()

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Wyśrodkowanie ustępuje marginesom: przy oknie zwężonym do minimum przyciski
            // dosuwają się do krawędzi, zamiast wyjść poza nie.
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: AppConfiguration.Editor.formatBarInset
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -AppConfiguration.Editor.formatBarInset
            ),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSeparatorColor()
    }

    /// `separatorColor` jest kolorem dynamicznym, ale `cgColor` zapamiętuje jedną konkretną
    /// wartość — przy przełączeniu motywu trzeba go rozwiązać na nowo, w kontekście
    /// bieżącego wyglądu. Reszta paska (ikony, tekst) robi to sama.
    private func updateSeparatorColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }
}
