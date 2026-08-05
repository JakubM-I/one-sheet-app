import Foundation
import Testing
@testable import OneSheetCore

@Suite("Pozycjonowanie panelu")
struct PanelGeometryTests {

    /// Ekran 1440×900 z belką u góry: obszar roboczy kończy się na y = 875.
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
    let size = NSSize(width: 380, height: 480)
    let gap: CGFloat = 6

    /// Ikona w belce: 24×22 pt, dolna krawędź na wysokości 877.
    func statusItem(atX x: CGFloat) -> NSRect {
        NSRect(x: x, y: 877, width: 24, height: 22)
    }

    /// Zmiana 2026-08-05: ikona ma zostać nad rogiem panelu, a nie nad jego środkiem.
    @Test("panel zaczepia się pod ikoną, wyrównany do jej lewej krawędzi")
    func alignedBelowStatusItem() {
        let frame = PanelGeometry.initialFrame(
            size: size, anchor: statusItem(atX: 900), visibleFrame: screen, gap: gap
        )
        #expect(frame.minX == 900 - gap, "lewa krawędź panelu tuż przed lewą krawędzią ikony")
        #expect(frame.maxY == 877 - gap, "górna krawędź poniżej ikony")
        #expect(frame.size == size, "rozmiar bez zmian")
    }

    /// Ikona blisko prawej krawędzi: panel wyrównany do niej wystawałby poza ekran,
    /// więc wsuwa się w obszar roboczy — ale nadal kończy pod ikoną, nie przed nią.
    @Test("ikona przy prawej krawędzi cofa panel do krawędzi ekranu")
    func alignmentYieldsToScreenEdge() {
        let frame = PanelGeometry.initialFrame(
            size: size, anchor: statusItem(atX: 1300), visibleFrame: screen, gap: gap
        )
        #expect(frame.maxX == screen.maxX)
        #expect(frame.size == size)
    }

    /// Oba brzegi ekranu jednym testem: panel ma się wsunąć do środka,
    /// nie zmieniając przy tym rozmiaru.
    @Test("ikona przy krawędzi ekranu nie wypycha panelu poza obszar roboczy",
          arguments: [CGFloat(1414), CGFloat(2)])
    func clampedAtScreenEdges(iconX: CGFloat) {
        let frame = PanelGeometry.initialFrame(
            size: size, anchor: statusItem(atX: iconX), visibleFrame: screen, gap: gap
        )
        #expect(screen.contains(frame))
        #expect(frame.size == size, "przycięcie nie zmienia rozmiaru")
    }

    @Test("bez ikony panel ląduje pod górną krawędzią obszaru roboczego")
    func fallbackWithoutStatusItem() {
        let frame = PanelGeometry.initialFrame(
            size: size, anchor: nil, visibleFrame: screen, gap: gap
        )
        #expect(frame.midX == screen.midX)
        #expect(frame.maxY == screen.maxY - gap)
    }

    @Test("panel wyższy niż ekran zostaje zmniejszony do obszaru roboczego")
    func oversizedPanelShrinks() {
        let frame = PanelGeometry.initialFrame(
            size: NSSize(width: 380, height: 2000),
            anchor: statusItem(atX: 1200),
            visibleFrame: screen,
            gap: gap
        )
        #expect(frame.height == screen.height)
        #expect(frame.minY == screen.minY)
    }

    /// Ramka zapamiętana na monitorze, którego już nie ma — w każdą stronę.
    @Test("ramka spoza ekranu jest wsuwana w obszar roboczy", arguments: [
        NSRect(x: 2200, y: -400, width: 380, height: 480),
        NSRect(x: -900, y: 2000, width: 380, height: 480),
    ])
    func clampsOrphanedFrame(orphaned: NSRect) {
        let frame = PanelGeometry.clamped(orphaned, to: screen)
        #expect(screen.contains(frame))
        #expect(frame.size == orphaned.size)
    }

    @Test("ramka mieszcząca się na ekranie nie jest ruszana")
    func leavesValidFrameAlone() {
        let untouched = NSRect(x: 100, y: 100, width: 380, height: 480)
        #expect(PanelGeometry.clamped(untouched, to: screen) == untouched)
    }

    // MARK: - Ponowne pokazanie z zapamiętaną ramką

    /// Defekt z weryfikacji dwóch monitorów (2026-08-05): ramka zapamiętana na
    /// wbudowanym ekranie, ikona kliknięta na zewnętrznym — panel ma wrócić pod
    /// ikonę, a nie zostać dociągnięty do najbliższej krawędzi nowego ekranu.
    @Test("ramka z innego monitora wraca pod klikniętą ikonę")
    func reanchorsFrameFromAnotherScreen() {
        let savedOnBuiltIn = NSRect(x: -1200, y: -600, width: 420, height: 520)
        let frame = PanelGeometry.presentationFrame(
            saved: savedOnBuiltIn, anchor: statusItem(atX: 900), visibleFrame: screen, gap: gap
        )
        #expect(frame.minX == 900 - gap, "lewa krawędź panelu tuż przed lewą krawędzią ikony")
        #expect(frame.maxY == 877 - gap, "górna krawędź poniżej ikony")
        #expect(frame.size == savedOnBuiltIn.size, "rozmiar użytkownika zachowany")
    }

    @Test("ramka z innego monitora bez ikony ląduje pod górną krawędzią ekranu")
    func reanchorsFrameWithoutAnchor() {
        let savedOnBuiltIn = NSRect(x: -1200, y: -600, width: 380, height: 480)
        let frame = PanelGeometry.presentationFrame(
            saved: savedOnBuiltIn, anchor: nil, visibleFrame: screen, gap: gap
        )
        #expect(frame.midX == screen.midX)
        #expect(frame.maxY == screen.maxY - gap)
    }

    @Test("ramka częściowo wystająca za ekran jest przycinana, nie przenoszona pod ikonę")
    func clampsPartiallyVisibleFrame() {
        let partiallyOff = NSRect(x: 1300, y: 100, width: 380, height: 480)
        let frame = PanelGeometry.presentationFrame(
            saved: partiallyOff, anchor: statusItem(atX: 200), visibleFrame: screen, gap: gap
        )
        #expect(screen.contains(frame))
        #expect(frame.minY == 100, "pozycja pionowa zostaje — to korekta, nie przeprowadzka")
        #expect(frame.maxX == screen.maxX, "wsunięta dokładnie do krawędzi")
    }

    @Test("ramka w całości na ekranie docelowym nie jest ruszana")
    func keepsFrameOnTargetScreen() {
        let saved = NSRect(x: 900, y: 300, width: 380, height: 480)
        let frame = PanelGeometry.presentationFrame(
            saved: saved, anchor: statusItem(atX: 200), visibleFrame: screen, gap: gap
        )
        #expect(frame == saved)
    }
}
