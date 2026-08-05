import Foundation
import ServiceManagement

/// Autostart aplikacji przez `SMAppService.mainApp`.
///
/// Źródłem prawdy o stanie jest system (`SMAppService.mainApp.status`) — użytkownik może
/// w każdej chwili zmienić stan w Ustawieniach systemowych → Elementy logowania, więc
/// własna kopia stanu kłamałaby. Flaga w `UserDefaults` odnotowuje wyłącznie zamiar
/// użytkownika; bez niej pierwsze uruchomienie włączałoby autostart od nowa po każdym
/// jego ręcznym wyłączeniu.
///
/// `register()` wymaga podpisanej binarki uruchomionej z pakietu `.app` — dla procesu
/// spod `swift run` kończy się błędem. To spodziewana ścieżka, nie awaria: błąd trafia
/// do logu i do menu kontekstowego, aplikacja działa dalej.
@MainActor
final class LaunchAtLogin {

    /// Komunikat ostatniej nieudanej operacji — do wyszarzonej linii w menu kontekstowym.
    /// `nil` po każdej udanej operacji.
    private(set) var lastFailureDescription: String?

    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Rejestracja wykonana, ale czeka na zgodę użytkownika w Ustawieniach systemowych.
    var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Domyślne włączenie autostartu przy pierwszym uruchomieniu (FUNKCJONALNOSCI,
    /// sekcja 6). Wykonuje się raz — znacznikiem jest obecność klucza w `UserDefaults`.
    func enableOnFirstLaunch() {
        guard UserDefaults.standard.object(forKey: AppConfiguration.Defaults.launchAtLogin) == nil else {
            return
        }
        Log.app.info("Pierwsze uruchomienie — włączam autostart")
        register()
    }

    func toggle() {
        // `.requiresApproval` liczy się jako „włączone": rejestracja już nastąpiła,
        // więc kolejna akcja użytkownika ma ją wycofać, a nie ponawiać.
        if isEnabled || requiresApproval {
            unregister()
        } else {
            register()
        }
    }

    private func register() {
        do {
            try SMAppService.mainApp.register()
            lastFailureDescription = nil
            Log.app.info("Autostart włączony (status: \(SMAppService.mainApp.status.rawValue, privacy: .public))")
        } catch {
            lastFailureDescription = error.localizedDescription
            Log.app.error("Rejestracja autostartu nieudana: \(error.localizedDescription, privacy: .public)")
        }
        UserDefaults.standard.set(true, forKey: AppConfiguration.Defaults.launchAtLogin)
    }

    private func unregister() {
        do {
            try SMAppService.mainApp.unregister()
            lastFailureDescription = nil
            Log.app.info("Autostart wyłączony")
        } catch {
            lastFailureDescription = error.localizedDescription
            Log.app.error("Wyrejestrowanie autostartu nieudane: \(error.localizedDescription, privacy: .public)")
        }
        UserDefaults.standard.set(false, forKey: AppConfiguration.Defaults.launchAtLogin)
    }
}
