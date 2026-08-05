#!/usr/bin/env swift
//
// Generuje scripts/AppIcon.icns — ikonę aplikacji dla Findera, Docka (nieużywanego)
// i listy Elementów logowania. Prosty motyw kartki z liniami; finalna ikona powstaje
// w etapie 6, ta wersja istnieje, żeby autostart nie pokazywał pustej ikony.
//
// Uruchamianie (jednorazowe, wynik trafia do repozytorium):
//   swift scripts/make_icon.swift
//
// Wymaga tylko systemowych narzędzi: AppKit do rysowania, iconutil (/usr/bin/iconutil,
// część macOS, nie Xcode) do złożenia .icns z zestawu PNG.

import AppKit

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

    // Kartka: zaokrąglony kwadrat z marginesem ~10% (klasyczna siatka ikon macOS).
    let cardRect = NSRect(x: 0.10 * s, y: 0.10 * s, width: 0.80 * s, height: 0.80 * s)
    let cornerRadius = 0.185 * cardRect.width
    let card = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Delikatny cień pod kartką, żeby nie zlewała się z jasnym tłem Findera.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 0.035 * s
    shadow.shadowOffset = NSSize(width: 0, height: -0.018 * s)
    shadow.set()

    // Tło kartki: pionowy gradient papieru.
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        ending: NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.95, alpha: 1)
    )
    gradient?.draw(in: card, angle: -90)

    // Cień był potrzebny tylko przy wypełnieniu kartki.
    NSShadow().set()

    // Obwódka — bez niej biała kartka znika na białym tle.
    NSColor.black.withAlphaComponent(0.12).setStroke()
    card.lineWidth = max(1, 0.008 * s)
    card.stroke()

    // Linie tekstu jak w symbolu `note.text`: pierwsza ciemniejsza („tytuł"), reszta szara.
    let lineHeight = 0.045 * s
    let leftEdge = 0.235 * s
    let widths: [CGFloat] = [0.42, 0.53, 0.53, 0.36]
    let colors: [NSColor] = [
        NSColor(calibratedWhite: 0.22, alpha: 1),
        NSColor(calibratedWhite: 0.55, alpha: 1),
        NSColor(calibratedWhite: 0.55, alpha: 1),
        NSColor(calibratedWhite: 0.55, alpha: 1),
    ]
    for (index, width) in widths.enumerated() {
        let y = 0.66 * s - CGFloat(index) * 0.115 * s
        let lineRect = NSRect(x: leftEdge, y: y, width: width * s, height: lineHeight)
        colors[index].setFill()
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
