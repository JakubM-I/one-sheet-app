import Foundation

/// Metadane sesji edycji: gdzie stał kursor i jak daleko było przewinięte.
///
/// Leżą w osobnym `state.json`, a nie w pliku notatki. Powód jest praktyczny: pozycja
/// przewinięcia zmienia się przy każdym ruchu kółka myszy, a treść — dużo rzadziej.
/// Trzymanie ich razem oznaczałoby przepisywanie całego RTFD przy każdym przewinięciu.
struct EditorState: Codable, Equatable, Sendable {

    /// Początek zaznaczenia. Przy zwykłym kursorze bez zaznaczenia `selectionLength == 0`.
    var selectionLocation: Int
    var selectionLength: Int

    /// Przesunięcie w pionie widoku przewijania, w punktach.
    var scrollOffset: Double

    static let initial = EditorState(selectionLocation: 0, selectionLength: 0, scrollOffset: 0)
}
