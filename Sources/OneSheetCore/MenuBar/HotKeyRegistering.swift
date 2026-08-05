import Foundation

/// Rejestracja globalnego skrótu klawiszowego.
///
/// Protokół oddziela `AppDelegate` od Carbon: implementację `RegisterEventHotKey`
/// da się podmienić (np. gdyby Apple w końcu dał następcę tego API) bez ruszania
/// reszty aplikacji — specyfikacja, sekcja 3.2.
@MainActor
protocol HotKeyRegistering: AnyObject {

    /// Wywoływane po naciśnięciu skrótu, zawsze na wątku głównym.
    var onHotKey: (@MainActor () -> Void)? { get set }

    /// Rzuca, gdy system odmówi rejestracji — najczęściej dlatego, że kombinację
    /// trzyma już inna aplikacja. Aplikacja ma to przeżyć i działać dalej bez skrótu.
    func register() throws

    /// Musi zostać wywołane, zanim właściciel zwolni obiekt — Carbon trzyma surowy
    /// wskaźnik do instancji i nie wie nic o ARC.
    func unregister()
}
