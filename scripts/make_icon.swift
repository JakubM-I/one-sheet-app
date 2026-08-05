#!/usr/bin/env swift
//
// Generuje scripts/AppIcon.icns — finalną ikonę aplikacji (etap 6) dla Findera,
// listy Elementów logowania i /Applications. Motyw: jedna kartka papieru z liniami
// tekstu, wypełniająca siatkę ikon macOS.
//
// Uruchamianie (jednorazowe, wynik trafia do repozytorium):
//   swift scripts/make_icon.swift
//
// Wymaga tylko systemowych narzędzi: AppKit do rysowania, SwiftUI do kształtu
// (patrz niżej), iconutil (/usr/bin/iconutil, część macOS, nie Xcode) do złożenia
// .icns z zestawu PNG.
//
// Dlaczego SwiftUI w skrypcie rysującym: maska ikon macOS to zaokrąglony kwadrat
// o „ciągłej" krzywiźnie rogów (superelipsa Apple), a jedyne publiczne API oddające
// dokładnie ten kształt to `RoundedRectangle(cornerRadius:style:.continuous)`.
// `NSBezierPath(roundedRect:)` daje rogi kołowe — przy pełnowymiarowej ikonie
// różnica jest widoczna jako „twarde" przejście łuku w prostą.

import AppKit
import SwiftUI

/// Rysuje ikonę na płótnie o podanym boku (w pikselach) i zwraca PNG.
func renderIcon(side: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.current = context

    let s = CGFloat(side)

    // Siatka ikon macOS: kwadrat 824/1024 wyśrodkowany na płótnie, promień rogów
    // ~22,5% boku. Margines wokół zostaje przezroczysty — jest częścią formatu,
    // nie „pustym miejscem".
    let cardSide = 824.0 / 1024.0 * s
    let cardRect = NSRect(
        x: (s - cardSide) / 2,
        y: (s - cardSide) / 2,
        width: cardSide,
        height: cardSide
    )
    let cornerRadius = 185.0 / 824.0 * cardSide
    let cardPath = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .path(in: cardRect)
    let card = NSBezierPath(cgPath: cardPath.cgPath)

    // Delikatny cień pod kartką, żeby nie zlewała się z jasnym tłem Findera.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 0.024 * s
    shadow.shadowOffset = NSSize(width: 0, height: -0.012 * s)
    shadow.set()

    // Tło kartki: pionowy gradient papieru — cieplejsza biel u góry, chłodniejsza
    // szarość u dołu, jak światło padające na kartkę.
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 1.00, green: 1.00, blue: 0.99, alpha: 1),
        ending: NSColor(calibratedRed: 0.91, green: 0.92, blue: 0.94, alpha: 1)
    )
    gradient?.draw(in: card, angle: -90)

    // Cień był potrzebny tylko przy wypełnieniu kartki.
    NSShadow().set()

    // Obwódka — bez niej biała kartka znika na białym tle.
    NSColor.black.withAlphaComponent(0.10).setStroke()
    card.lineWidth = max(1, 0.006 * s)
    card.stroke()

    // Linie tekstu: pierwsza dłuższa i ciemniejsza („tytuł" notatki), pod nią akapit
    // z szarych linii o nierównych szerokościach — równe końce wyglądałyby jak tabela,
    // nie jak pismo. Zaokrąglone końce nawiązują do linii w symbolu `note.text` z belki.
    let leftEdge = 0.22 * s
    let titleHeight = 0.052 * s
    let lineHeight = 0.038 * s
    let titleColor = NSColor(calibratedWhite: 0.24, alpha: 1)
    let bodyColor = NSColor(calibratedWhite: 0.62, alpha: 1)

    let title = NSRect(x: leftEdge, y: 0.655 * s, width: 0.40 * s, height: titleHeight)
    titleColor.setFill()
    NSBezierPath(roundedRect: title, xRadius: titleHeight / 2, yRadius: titleHeight / 2).fill()

    let bodyWidths: [CGFloat] = [0.56, 0.49, 0.56, 0.33]
    for (index, width) in bodyWidths.enumerated() {
        let y = 0.545 * s - CGFloat(index) * 0.093 * s
        let lineRect = NSRect(x: leftEdge, y: y, width: width * s, height: lineHeight)
        bodyColor.setFill()
        NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
    }

    return bitmap.representation(using: .png, properties: [:])
}

// Zestaw rozmiarów wymaganych przez format .iconset.
let entries: [(name: String, side: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let scriptsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("AppIcon.iconset", isDirectory: true)
let outputURL = scriptsDirectory.appendingPathComponent("AppIcon.icns")

do {
    try? FileManager.default.removeItem(at: iconsetURL)
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    for entry in entries {
        guard let png = renderIcon(side: entry.side) else {
            fputs("BŁĄD: nie udało się narysować \(entry.name)\n", stderr)
            exit(1)
        }
        try png.write(to: iconsetURL.appendingPathComponent(entry.name))
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        fputs("BŁĄD: iconutil zakończył się kodem \(iconutil.terminationStatus)\n", stderr)
        exit(1)
    }

    try? FileManager.default.removeItem(at: iconsetURL)
    print("Gotowe: \(outputURL.path)")
} catch {
    fputs("BŁĄD: \(error.localizedDescription)\n", stderr)
    exit(1)
}
