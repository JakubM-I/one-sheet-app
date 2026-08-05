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

    /// Doprowadza rejestrację w systemie do zgodności ze stanem aplikacji. Dwie sytuacje:
    ///
    /// 1. **Pierwsze uruchomienie** — autostart włączany domyślnie (FUNKCJONALNOSCI,
    ///    sekcja 6). Znacznikiem jest brak klucza w `UserDefaults`.
    /// 2. **Bundle przeniesiony** (instalacja przez `scripts/install.sh`) — wpis autostartu
    ///    w systemie trzyma **ścieżkę** pakietu, więc po przeprowadzce do `/Applications`
    ///    logowanie uruchamiałoby starą kopię z repozytorium. `SMAppService.mainApp.status`
    ///    tego nie wykryje: dopasowuje po identyfikatorze pakietu i z nowej lokalizacji
    ///    dalej zwraca `.enabled` — zmierzone 2026-08-05. Wykrywamy przeprowadzkę sami,
    ///    porównując ścieżki, a ponowna `register()` aktualizuje istniejący wpis
    ///    w miejscu (ten sam UUID, nowy URL) — również zmierzone.
    func reconcileOnLaunch() {
        guard UserDefaults.standard.object(forKey: AppConfiguration.Defaults.launchAtLogin) != nil else {
            Log.app.info("Pierwsze uruchomienie — włączam autostart")
            register()
            return
        }
        let shouldRepair = Self.shouldRepairRegistration(
            intentEnabled: UserDefaults.standard.bool(forKey: AppConfiguration.Defaults.launchAtLogin),
            systemEnabled: isEnabled,
            registeredPath: UserDefaults.standard.string(forKey: AppConfiguration.Defaults.registeredBundlePath),
            currentPath: Bundle.main.bundlePath
        )
        if shouldRepair {
            Log.app.info("Pakiet przeniesiony do \(Bundle.main.bundlePath, privacy: .public) — ponawiam rejestrację autostartu")
            register()
        }
    }

    /// Czysta decyzja „czy ponowić rejestrację po przeprowadzce" — wydzielona, żeby dała
    /// się sprawdzić testem bez dotykania prawdziwej bazy login items.
    ///
    /// Naprawiamy wyłącznie kopię w `/Applications`: kopia w repozytorium jest buildem
    /// roboczym i uruchomienie jej (np. przez `scripts/run.sh`) nie może „ukraść"
    /// autostartu świeżo zainstalowanej aplikacji. Warunek `systemEnabled` chroni decyzję
    /// użytkownika — jeśli wyłączył autostart w Ustawieniach systemowych, przeprowadzka
    /// niczego nie włącza z powrotem.
    nonisolated static func shouldRepairRegistration(
        intentEnabled: Bool,
        systemEnabled: Bool,
        registeredPath: String?,
        currentPath: String
    ) -> Bool {
        guard intentEnabled, systemEnabled else { return false }
        guard currentPath.hasPrefix("/Applications/") else { return false }
        return registeredPath != currentPath
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
            // Ścieżka zapamiętywana tylko po sukcesie — po błędzie kolejny start
            // ma spróbować naprawy jeszcze raz.
            UserDefaults.standard.set(Bundle.main.bundlePath, forKey: AppConfiguration.Defaults.registeredBundlePath)
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
            UserDefaults.standard.removeObject(forKey: AppConfiguration.Defaults.registeredBundlePath)
            Log.app.info("Autostart wyłączony")
        } catch {
            lastFailureDescription = error.localizedDescription
            Log.app.error("Wyrejestrowanie autostartu nieudane: \(error.localizedDescription, privacy: .public)")
        }
        UserDefaults.standard.set(false, forKey: AppConfiguration.Defaults.launchAtLogin)
    }
}
