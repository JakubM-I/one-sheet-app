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

    @Test("panel jest wyśrodkowany pod ikoną")
    func centeredBelowStatusItem() {
        let frame = PanelGeometry.initialFrame(
            size: size, anchor: statusItem(atX: 1200), visibleFrame: screen, gap: gap
        )
        #expect(frame.midX == 1212, "środek panelu pod środkiem ikony")
        #expect(frame.maxY == 877 - gap, "górna krawędź poniżej ikony")
        #expect(frame.size == size, "rozmiar bez zmian")
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
}
