import AppKit
import Testing
@testable import OneSheetCore

/// Menu kontekstowe ikony jest budowane z modelu, więc każdy wariant stanu
/// (autostart włączony/wyłączony, komunikaty o błędach) da się sprawdzić
/// bez belki systemowej i bez okien.
@Suite("Menu ikony statusu")
@MainActor
struct StatusItemMenuTests {

    private final class MenuTarget: NSObject {
        @objc func toggleLaunchAtLogin(_ sender: Any?) {}
        @objc func toggleHidesOnClickOutside(_ sender: Any?) {}
    }

    private func makeMenu(model: StatusItemMenu.Model, target: AnyObject? = nil) -> NSMenu {
        StatusItemMenu.makeMenu(
            model: model,
            target: target,
            toggleLaunchAtLoginAction: #selector(MenuTarget.toggleLaunchAtLogin(_:)),
            toggleHidesOnClickOutsideAction: #selector(MenuTarget.toggleHidesOnClickOutside(_:))
        )
    }

    @Test("bez komunikatów menu ma dwa przełączniki i pozycję Zakończ")
    func plainMenu() {
        let target = MenuTarget()
        let items = makeMenu(model: .init(), target: target).items.filter { !$0.isSeparatorItem }

        #expect(items.map(\.title) == [
            "Uruchamiaj przy logowaniu",
            "Chowaj po kliknięciu poza notatką",
            "Zakończ",
        ])
        #expect(items[0].target === target)
        #expect(items[0].action == #selector(MenuTarget.toggleLaunchAtLogin(_:)))
        #expect(items[1].target === target)
        #expect(items[1].action == #selector(MenuTarget.toggleHidesOnClickOutside(_:)))
        // Zakończ idzie łańcuchem responderów do NSApplication — cel musi zostać pusty.
        #expect(items[2].action == #selector(NSApplication.terminate(_:)))
        #expect(items[2].target == nil)
    }

    @Test("ptaszek odzwierciedla stan autostartu z modelu", arguments: [true, false])
    func launchAtLoginState(enabled: Bool) {
        let menu = makeMenu(model: .init(launchAtLoginEnabled: enabled))
        #expect(menu.items[0].state == (enabled ? .on : .off))
    }

    @Test("ptaszek odzwierciedla tryb chowania po kliknięciu poza panelem", arguments: [true, false])
    func hidesOnClickOutsideState(enabled: Bool) {
        let menu = makeMenu(model: .init(hidesOnClickOutside: enabled))
        let item = menu.items.first { $0.title == "Chowaj po kliknięciu poza notatką" }
        #expect(item?.state == (enabled ? .on : .off))
    }

    @Test("komunikaty trafiają do menu jako pozycje bez akcji")
    func notices() {
        var model = StatusItemMenu.Model()
        model.launchAtLoginNotice = "Autostart niedostępny: odmowa systemu"
        model.hotKeyNotice = "Skrót ⌥⌘N niedostępny"
        let items = makeMenu(model: model).items.filter { !$0.isSeparatorItem }

        #expect(items.map(\.title) == [
            "Uruchamiaj przy logowaniu",
            "Autostart niedostępny: odmowa systemu",
            "Chowaj po kliknięciu poza notatką",
            "Skrót ⌥⌘N niedostępny",
            "Zakończ",
        ])
        // Brak akcji = pozycja informacyjna; `autoenablesItems` utrzyma ją wyszarzoną.
        #expect(items[1].action == nil)
        #expect(items[3].action == nil)
        #expect(items[1].isEnabled == false)
        #expect(items[3].isEnabled == false)
    }
}
