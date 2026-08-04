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

harness.finish()
