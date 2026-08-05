import Testing
@testable import OneSheetCore

/// Decyzja o ponownej rejestracji autostartu po przeniesieniu pakietu jest czystą
/// funkcją — dzięki temu każdy wariant (przeprowadzka, kopia robocza, autostart
/// wyłączony przez użytkownika) da się sprawdzić bez dotykania prawdziwej bazy
/// login items i bez uprawnień systemowych.
@Suite("Naprawa rejestracji autostartu po przeniesieniu pakietu")
struct LaunchAtLoginTests {

    private static let installedPath = "/Applications/OneSheet.app"
    private static let repositoryPath = "/Users/macbook/Kodowanie/one-sheet/OneSheet.app"

    @Test("przeprowadzka do /Applications wyzwala ponowną rejestrację")
    func repairsAfterMoveToApplications() {
        #expect(LaunchAtLogin.shouldRepairRegistration(
            intentEnabled: true,
            systemEnabled: true,
            registeredPath: Self.repositoryPath,
            currentPath: Self.installedPath
        ))
    }

    @Test("brak zapamiętanej ścieżki (instalacja sprzed tego mechanizmu) też liczy się jako przeprowadzka")
    func repairsWhenNoPathRecorded() {
        #expect(LaunchAtLogin.shouldRepairRegistration(
            intentEnabled: true,
            systemEnabled: true,
            registeredPath: nil,
            currentPath: Self.installedPath
        ))
    }

    @Test("zgodna ścieżka nie wyzwala rejestracji — start bez skutków ubocznych")
    func doesNothingWhenPathUnchanged() {
        #expect(!LaunchAtLogin.shouldRepairRegistration(
            intentEnabled: true,
            systemEnabled: true,
            registeredPath: Self.installedPath,
            currentPath: Self.installedPath
        ))
    }

    @Test("kopia robocza z repozytorium nie przejmuje autostartu zainstalowanej aplikacji")
    func repositoryCopyNeverSteals() {
        #expect(!LaunchAtLogin.shouldRepairRegistration(
            intentEnabled: true,
            systemEnabled: true,
            registeredPath: Self.installedPath,
            currentPath: Self.repositoryPath
        ))
    }

    @Test("autostart wyłączony w Ustawieniach systemowych zostaje wyłączony mimo przeprowadzki")
    func respectsSystemDisabledState() {
        #expect(!LaunchAtLogin.shouldRepairRegistration(
            intentEnabled: true,
            systemEnabled: false,
            registeredPath: Self.repositoryPath,
            currentPath: Self.installedPath
        ))
    }

    @Test("wyłączony zamiar użytkownika blokuje naprawę niezależnie od reszty")
    func respectsUserIntent() {
        #expect(!LaunchAtLogin.shouldRepairRegistration(
            intentEnabled: false,
            systemEnabled: true,
            registeredPath: Self.repositoryPath,
            currentPath: Self.installedPath
        ))
    }
}
