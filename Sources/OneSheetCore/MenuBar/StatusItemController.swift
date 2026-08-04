import AppKit

/// Ikona aplikacji w górnej belce systemowej.
///
/// `NSStatusItem` musi być trzymany przy życiu przez cały czas działania aplikacji —
/// zwolnienie referencji usuwa ikonę z belki. Właścicielem jest `AppDelegate`.
@MainActor
final class StatusItemController {

    /// Wywoływane lewym kliknięciem — otwarcie lub schowanie panelu.
    var onPrimaryAction: (() -> Void)?

    /// Wywoływane prawym kliknięciem lub `⌃`+kliknięciem — w etapie 4 menu kontekstowe.
    var onSecondaryAction: (() -> Void)?

    /// Prostokąt ikony we współrzędnych ekranu — punkt zaczepienia panelu.
    ///
    /// `NSStatusItem.button` żyje we własnym oknie systemowym, tworzonym przez belkę.
    /// Droga do współrzędnych ekranu prowadzi więc przez to okno; `nil` oznacza,
    /// że pozycji w belce nie udało się utworzyć.
    var buttonFrameOnScreen: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private let statusItem: NSStatusItem

    init() {
        // `variableLength` — szerokość dopasowuje się do zawartości. Przy stałej wartości
        // ikona bywa przycięta na monitorach o innym współczynniku skalowania.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            // Zdarza się wyłącznie, gdy w belce brakuje miejsca i system odmówi utworzenia
            // pozycji. Aplikacja jest wtedy bezużyteczna, ale nie ma powodu jej wywracać.
            Log.menuBar.error("Nie udało się utworzyć przycisku pozycji w belce")
            return
        }

        button.image = NSImage(
            systemSymbolName: AppConfiguration.StatusItem.symbolName,
            accessibilityDescription: AppConfiguration.StatusItem.accessibilityDescription
        )
        // Szablon = system sam koloruje ikonę pod jasny/ciemny motyw i podświetlenie belki.
        button.image?.isTemplate = true

        button.target = self
        button.action = #selector(handleClick)
        // Domyślnie przycisk reaguje tylko na lewy przycisk. Prawy musimy włączyć jawnie,
        // inaczej `handleClick` nigdy nie zobaczy zdarzenia `rightMouseUp`.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        Log.menuBar.info("Ikona statusu utworzona (symbol: \(AppConfiguration.StatusItem.symbolName, privacy: .public))")
    }

    @objc private func handleClick() {
        // Rodzaj kliknięcia nie jest przekazywany w akcji — trzeba go odczytać
        // z bieżącego zdarzenia aplikacji.
        guard let event = NSApp.currentEvent else { return }

        // `⌃`+lewy przycisk to systemowy odpowiednik prawego kliknięcia.
        let isSecondary = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)

        if isSecondary {
            Log.menuBar.info("Kliknięcie prawym przyciskiem w ikonę")
            onSecondaryAction?()
        } else {
            Log.menuBar.info("Kliknięcie lewym przyciskiem w ikonę")
            onPrimaryAction?()
        }
    }
}
