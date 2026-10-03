import Testing
@testable import OneSheetCore

/// Samego kliknięcia w inną aplikację nie da się zasymulować w teście — zdarzenia
/// syntetyczne trafiają do naszego procesu, a monitor globalny ich nie widzi.
/// Pod testem jest więc cykl życia monitora; zachowanie sprawdza się ręcznie.
@Suite("Monitor kliknięć poza panelem")
@MainActor
struct OutsideClickMonitorTests {

    @Test("nowy monitor nie słucha")
    func idleByDefault() {
        #expect(OutsideClickMonitor().isRunning == false)
    }

    @Test("start i stop przełączają stan, powtórzenia są nieszkodliwe")
    func lifecycle() {
        let monitor = OutsideClickMonitor()
        monitor.stop()
        #expect(monitor.isRunning == false)

        monitor.start()
        monitor.start()
        #expect(monitor.isRunning)

        monitor.stop()
        #expect(monitor.isRunning == false)
        monitor.stop()
        #expect(monitor.isRunning == false)
    }
}
