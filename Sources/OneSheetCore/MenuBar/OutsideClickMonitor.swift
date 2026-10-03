import AppKit

/// Wykrywa kliknięcia myszą poza aplikacją — podstawa trybu „chowaj po kliknięciu poza notatką".
///
/// Monitor globalny (`NSEvent.addGlobalMonitorForEvents`) dostaje wyłącznie zdarzenia
/// dostarczane **innym** procesom. Kliknięcia w panel, w menu kontekstowe edytora i w naszą
/// własną ikonę w belce (jej okno należy do naszego procesu) tu nie trafiają — dzięki temu
/// klik w ikonę obsługuje sam `toggle`, a monitor nie chowa panelu drugi raz.
///
/// Dla zdarzeń myszy monitor globalny nie wymaga zgody Accessibility; wymaga jej dopiero
/// przy zdarzeniach klawiatury, których tu nie słuchamy.
@MainActor
final class OutsideClickMonitor {

    var onOutsideClick: (() -> Void)?

    var isRunning: Bool { token != nil }

    /// Nieprzezroczysty obiekt zwracany przez AppKit — jedyny uchwyt do zdjęcia monitora.
    private var token: Any?

    /// Idempotentne: drugi monitor oznaczałby dwa schowania na jedno kliknięcie.
    func start() {
        guard token == nil else { return }
        token = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // AppKit woła blok monitora na głównym wątku, ale sygnatura tego nie gwarantuje.
            MainActor.assumeIsolated {
                Log.panel.info("Kliknięcie poza aplikacją")
                self?.onOutsideClick?()
            }
        }
        if token == nil {
            Log.panel.error("Nie udało się zainstalować monitora kliknięć poza panelem")
        } else {
            Log.panel.info("Monitor kliknięć poza panelem włączony")
        }
    }

    func stop() {
        guard let token else { return }
        NSEvent.removeMonitor(token)
        self.token = nil
        Log.panel.info("Monitor kliknięć poza panelem wyłączony")
    }
}
