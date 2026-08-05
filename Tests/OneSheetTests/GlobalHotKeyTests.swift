import Carbon.HIToolbox
import Testing
@testable import OneSheetCore

/// `RegisterEventHotKey` nie wymaga uprawnień ani okien, więc rejestrację da się
/// sprawdzić w procesie testowym. Samego naciśnięcia klawisza test nie symuluje —
/// dostarczenie zdarzenia wymaga pętli zdarzeń i weryfikowane jest ręcznie.
@Suite("Globalny skrót")
@MainActor
struct GlobalHotKeyTests {

    /// Kombinacja inna niż produkcyjna `⌥⌘N`: testy działają obok uruchomionej
    /// aplikacji, a rejestracja hot-key jest wyłączna w obrębie sesji użytkownika.
    private static let testKeyCode = UInt32(kVK_F13)
    private static let testModifiers = UInt32(controlKey | optionKey | cmdKey | shiftKey)

    private func makeHotKey() -> GlobalHotKey {
        GlobalHotKey(keyCode: Self.testKeyCode, modifiers: Self.testModifiers)
    }

    @Test("rejestracja i wyrejestrowanie przechodzą, sprzątanie jest kompletne")
    func roundTrip() throws {
        let hotKey = makeHotKey()
        try hotKey.register()
        hotKey.unregister()

        // Gdyby `unregister()` nie sprzątało do końca, druga rejestracja tej samej
        // kombinacji skończyłaby się `eventHotKeyExistsErr`.
        try hotKey.register()
        hotKey.unregister()
    }

    @Test("ponowna rejestracja bez wyrejestrowania jest nieszkodliwa")
    func doubleRegister() throws {
        let hotKey = makeHotKey()
        try hotKey.register()
        try hotKey.register()
        hotKey.unregister()
    }

    @Test("każda instancja dostaje inny identyfikator zdarzeń")
    func uniqueIdentifiers() {
        #expect(makeHotKey().identifier != makeHotKey().identifier)
    }
}
