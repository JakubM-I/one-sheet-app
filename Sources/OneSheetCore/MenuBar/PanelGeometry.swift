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

    /// Ramka panelu przy pierwszym otwarciu: zaczepiona pod ikoną w belce, wyrównana
    /// do jej lewej krawędzi, przycięta do widocznego obszaru ekranu.
    ///
    /// Wyrównanie do lewej, a nie wyśrodkowanie względem ikony (zmiana 2026-08-05):
    /// ikona ma zostać nad **rogiem** panelu, tak jak dzieje się to w menu rozwijanym
    /// z belki. Wyśrodkowanie odsuwało panel w prawo od ikony i przy szerokim oknie
    /// wyglądało jak przypadkowe położenie. Ten sam `gap`, który dzieli panel od belki,
    /// odsuwa go też od lewej krawędzi ikony — dzięki temu ikona jest wizualnie
    /// wewnątrz panelu, a nie dokładnie w jego narożniku.
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
        // Bez ikony wracamy do wyśrodkowania: nie ma czego wyrównywać, a środek
        // górnej krawędzi jest jedynym sensownym miejscem domyślnym.
        let leftEdge = anchor.map { $0.minX - gap } ?? (visibleFrame.midX - size.width / 2)
        // Bez ikony zaczepiamy się o górną krawędź obszaru roboczego — to i tak
        // dokładnie ta wysokość, na której kończy się belka.
        let topEdge = anchor?.minY ?? visibleFrame.maxY

        let frame = NSRect(
            x: leftEdge,
            y: topEdge - gap - size.height,
            width: size.width,
            height: size.height
        )
        return clamped(frame, to: visibleFrame)
    }

    /// Ramka przy ponownym pokazaniu panelu, gdy poprzednia pozycja jest zapamiętana.
    ///
    /// Zapamiętana pozycja obowiązuje tylko na ekranie, na którym użytkownik ją zostawił.
    /// Przy otwarciu na **innym** ekranie (klik w ikonę na drugim monitorze) samo
    /// przycięcie „dociągałoby" ramkę do najbliższej krawędzi ekranu docelowego — panel
    /// lądował w rogu, najbliżej starej pozycji, zamiast pod ikoną (defekt zgłoszony
    /// przy weryfikacji dwóch monitorów, 2026-08-05). Stąd rozróżnienie: ramka
    /// przecinająca ekran docelowy jest tylko przycinana (panel częściowo wystający,
    /// np. po zmianie rozdzielczości), ramka z innego ekranu — zakotwiczana na nowo
    /// pod ikoną, z zachowaniem rozmiaru.
    static func presentationFrame(
        saved: NSRect,
        anchor: NSRect?,
        visibleFrame: NSRect,
        gap: CGFloat
    ) -> NSRect {
        if saved.intersects(visibleFrame) {
            return clamped(saved, to: visibleFrame)
        }
        return initialFrame(size: saved.size, anchor: anchor, visibleFrame: visibleFrame, gap: gap)
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
