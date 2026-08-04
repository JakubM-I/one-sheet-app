import Foundation
@testable import OneSheetCore

// Rejestr testów. Bez automatycznego wykrywania — każdy nowy zestaw trzeba tu dopisać.

let harness = TestHarness()

/// Katalog główny repozytorium, wyliczony ze ścieżki tego pliku w czasie kompilacji.
/// Binarka testowa leży w `.build/`, więc bieżący katalog roboczy jest niepewny.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Tests/OneSheetTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // katalog główny

harness.suite("Info.plist zgadza się z konfiguracją w kodzie") {
    let plistURL = repositoryRoot.appending(path: "Resources/Info.plist")
    let data = try Data(contentsOf: plistURL)
    let plist = try PropertyListSerialization.propertyList(
        from: data, format: nil
    ) as? [String: Any] ?? [:]

    // Rozjazd identyfikatora cicho zepsuje SMAppService w etapie 4 — stąd ten test.
    harness.test("CFBundleIdentifier odpowiada AppConfiguration.bundleIdentifier") {
        try expectEqual(
            plist["CFBundleIdentifier"] as? String,
            AppConfiguration.bundleIdentifier
        )
    }

    // Nazwa musi się zgadzać z nazwą binarki kopiowanej przez bundle.sh.
    harness.test("CFBundleExecutable to OneSheet") {
        try expectEqual(plist["CFBundleExecutable"] as? String, "OneSheet")
    }

    // Bez tego aplikacja pokaże ikonę w Docku i wejdzie do ⌘Tab.
    harness.test("LSUIElement jest włączone") {
        try expectEqual(plist["LSUIElement"] as? Bool, true)
    }

    harness.test("LSMinimumSystemVersion to macOS 26.0") {
        try expectEqual(plist["LSMinimumSystemVersion"] as? String, "26.0")
    }
}

harness.suite("Pozycjonowanie panelu") {
    // Ekran 1440×900 z belką u góry: obszar roboczy kończy się na y = 875.
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
    let size = NSSize(width: 380, height: 480)
    let gap: CGFloat = 6

    /// Ikona w belce: 24×22 pt, dolna krawędź na wysokości 877.
    func statusItem(atX x: CGFloat) -> NSRect {
        NSRect(x: x, y: 877, width: 24, height: 22)
    }

    harness.test("panel jest wyśrodkowany pod ikoną") {
        let frame = PanelGeometry.initialFrame(
            size: size, anchor: statusItem(atX: 1200), visibleFrame: screen, gap: gap
        )
        try expectEqual(frame.midX, 1212, "środek panelu pod środkiem ikony")
        try expectEqual(frame.maxY, 877 - gap, "górna krawędź poniżej ikony")
        try expectEqual(frame.size, size, "rozmiar bez zmian")
    }

    harness.test("ikona przy prawej krawędzi nie wypycha panelu poza ekran") {
        let frame = PanelGeometry.initialFrame(
            size: size, anchor: statusItem(atX: 1414), visibleFrame: screen, gap: gap
        )
        try expectEqual(frame.maxX, screen.maxX, "panel dosunięty do prawej krawędzi")
        try expectEqual(frame.size, size, "przycięcie nie zmienia rozmiaru")
    }

    harness.test("ikona przy lewej krawędzi nie wypycha panelu poza ekran") {
        let frame = PanelGeometry.initialFrame(
            size: size, anchor: statusItem(atX: 2), visibleFrame: screen, gap: gap
        )
        try expectEqual(frame.minX, screen.minX)
    }

    harness.test("bez ikony panel ląduje pod górną krawędzią obszaru roboczego") {
        let frame = PanelGeometry.initialFrame(
            size: size, anchor: nil, visibleFrame: screen, gap: gap
        )
        try expectEqual(frame.midX, screen.midX)
        try expectEqual(frame.maxY, screen.maxY - gap)
    }

    harness.test("panel wyższy niż ekran zostaje zmniejszony do obszaru roboczego") {
        let frame = PanelGeometry.initialFrame(
            size: NSSize(width: 380, height: 2000),
            anchor: statusItem(atX: 1200),
            visibleFrame: screen,
            gap: gap
        )
        try expectEqual(frame.height, screen.height)
        try expectEqual(frame.minY, screen.minY)
    }

    // Ramka zapamiętana na monitorze, którego już nie ma.
    harness.test("ramka spoza ekranu jest wsuwana w obszar roboczy") {
        let orphaned = NSRect(x: 2200, y: -400, width: 380, height: 480)
        let frame = PanelGeometry.clamped(orphaned, to: screen)
        try expectEqual(frame, NSRect(x: 1060, y: 0, width: 380, height: 480))
    }

    harness.test("ramka mieszcząca się na ekranie nie jest ruszana") {
        let untouched = NSRect(x: 100, y: 100, width: 380, height: 480)
        try expectEqual(PanelGeometry.clamped(untouched, to: screen), untouched)
    }
}

harness.finish()
