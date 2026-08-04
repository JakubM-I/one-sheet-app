import Foundation

/// Czysta arytmetyka pozycjonowania panelu — bez `NSWindow` i bez `NSScreen`.
///
/// Wydzielone z `NotePanel` z jednego powodu: to jedyna część etapu 1, którą da się
/// sprawdzić testem. Program testowy działa bez serwera okien, więc wszystko, co dotyka
/// prawdziwego okna, może być zweryfikowane wyłącznie oczami.
///
/// Układ współrzędnych AppKit: początek w lewym **dolnym** rogu, oś Y rośnie do góry.
/// Dlatego „pod ikoną" znaczy `y` mniejsze niż dolna krawędź ikony.
enum PanelGeometry {

    /// Ramka panelu przy pierwszym otwarciu: wyśrodkowana względem ikony w belce,
    /// zaczepiona pod nią, przycięta do widocznego obszaru ekranu.
    ///
    /// - Parameters:
    ///   - size: pożądany rozmiar panelu
    ///   - anchor: prostokąt ikony w belce we współrzędnych ekranu; `nil`, gdy ikony
    ///     nie udało się utworzyć — wtedy panel ląduje pod środkiem górnej krawędzi
    ///   - visibleFrame: obszar ekranu wolny od belki i Docka (`NSScreen.visibleFrame`)
    ///   - gap: odstęp między ikoną a panelem
    static func initialFrame(
        size: NSSize,
        anchor: NSRect?,
        visibleFrame: NSRect,
        gap: CGFloat
    ) -> NSRect {
        let horizontalCenter = anchor?.midX ?? visibleFrame.midX
        // Bez ikony zaczepiamy się o górną krawędź obszaru roboczego — to i tak
        // dokładnie ta wysokość, na której kończy się belka.
        let topEdge = anchor?.minY ?? visibleFrame.maxY

        let frame = NSRect(
            x: horizontalCenter - size.width / 2,
            y: topEdge - gap - size.height,
            width: size.width,
            height: size.height
        )
        return clamped(frame, to: visibleFrame)
    }

    /// Wsuwa ramkę w widoczny obszar ekranu.
    ///
    /// Dwa przypadki, dla których to istnieje: ikona przy prawej krawędzi ekranu
    /// (wyśrodkowany panel wystawałby poza ekran) oraz zapamiętana ramka z monitora,
    /// który przestał być podłączony.
    static func clamped(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        var result = frame
        // Najpierw rozmiar: panel większy od ekranu nie da się w niego wsunąć,
        // a bez tego kroku dalsze `min`/`max` dałyby sprzeczne ograniczenia.
        result.size.width = min(result.width, visibleFrame.width)
        result.size.height = min(result.height, visibleFrame.height)
        result.origin.x = min(max(result.minX, visibleFrame.minX), visibleFrame.maxX - result.width)
        result.origin.y = min(max(result.minY, visibleFrame.minY), visibleFrame.maxY - result.height)
        return result
    }
}
