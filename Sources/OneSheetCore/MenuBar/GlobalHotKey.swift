import AppKit
import Carbon.HIToolbox

/// Globalny skrót klawiszowy przez Carbon `RegisterEventHotKey`.
///
/// Dlaczego Carbon, a nie AppKit: `NSEvent.addGlobalMonitorForEvents` wymaga uprawnień
/// Accessibility i tylko podgląda zdarzenia (nie konsumuje ich — inne aplikacje też by
/// dostały `⌥⌘N`). `RegisterEventHotKey` działa bez żadnych uprawnień, konsumuje
/// naciśnięcie i pozostaje wspieranym API na macOS 26.
@MainActor
final class GlobalHotKey: HotKeyRegistering {

    enum RegistrationError: Error {
        case handlerInstallation(OSStatus)
        /// Uwaga: kombinacja zajęta przez **inną aplikację** nie kończy się tym błędem —
        /// system dopuszcza duplikaty między procesami i zwraca `noErr` (pomiar z etapu 4,
        /// rejestr decyzji). `eventHotKeyExistsErr` (-9878) dotyczy wyłącznie duplikatu
        /// w obrębie tego samego procesu; ta ścieżka to zabezpieczenie na wypadek
        /// awarii samego API.
        case registration(OSStatus)
    }

    var onHotKey: (@MainActor () -> Void)?

    /// Identyfikator instancji w zdarzeniach Carbon. Uchwyt zdarzeń dostaje **wszystkie**
    /// zdarzenia hot-key procesu, więc bez rozróżnienia dwie instancje (np. aplikacja
    /// i testy w jednym procesie) wywoływałyby nawzajem swoje akcje.
    let identifier: UInt32

    private let keyCode: UInt32
    private let modifiers: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private static var nextIdentifier: UInt32 = 1

    init(
        keyCode: UInt32 = AppConfiguration.HotKey.keyCode,
        modifiers: UInt32 = AppConfiguration.HotKey.modifiers
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        identifier = Self.nextIdentifier
        Self.nextIdentifier += 1
    }

    func register() throws {
        guard hotKeyRef == nil else { return }

        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            // `passUnretained` — Carbon nie zarządza pamięcią; kontrakt „wyrejestruj
            // przed zwolnieniem" jest zapisany w protokole.
            let status = InstallEventHandler(
                GetEventDispatcherTarget(),
                Self.eventHandler,
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )
            guard status == noErr else {
                eventHandlerRef = nil
                throw RegistrationError.handlerInstallation(status)
            }
        }

        var registered: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: AppConfiguration.HotKey.signature, id: identifier),
            GetEventDispatcherTarget(),
            0,
            &registered
        )
        guard status == noErr, let registered else {
            throw RegistrationError.registration(status)
        }
        hotKeyRef = registered
        Log.menuBar.info("Globalny skrót zarejestrowany (kod \(self.keyCode, privacy: .public))")
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    /// Wywołanie zwrotne C — bez domknięć i bez kontekstu, stąd droga przez `userData`.
    /// Carbon dostarcza zdarzenia w pętli zdarzeń wątku głównego, co pozwala na
    /// `MainActor.assumeIsolated` (w razie złamania tego założenia — trap, nie cichy wyścig).
    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        var eventHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventHotKeyID
        )
        guard status == noErr else { return status }

        // Surowy wskaźnik nie jest `Sendable`, więc do domknięcia aktora wchodzi jako
        // liczba. To nie obchodzi izolacji: wskaźnik i tak pochodzi z tego samego wątku,
        // na którym `assumeIsolated` zaraz wykona domknięcie.
        let address = UInt(bitPattern: userData)
        let handled = MainActor.assumeIsolated { () -> Bool in
            guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return false }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(pointer).takeUnretainedValue()
            guard eventHotKeyID.signature == AppConfiguration.HotKey.signature,
                  eventHotKeyID.id == hotKey.identifier
            else { return false }
            hotKey.onHotKey?()
            return true
        }
        return handled ? noErr : OSStatus(eventNotHandledErr)
    }
}
