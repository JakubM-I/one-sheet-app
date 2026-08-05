import Foundation
import Testing
@testable import OneSheetCore

/// Katalog główny repozytorium, wyliczony ze ścieżki tego pliku w czasie kompilacji.
/// Binarka testowa leży w `.build/`, więc bieżący katalog roboczy jest niepewny.
private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Tests/OneSheetTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // katalog główny

/// Wczytanie `Info.plist` osobno w każdym teście. Plik ma kilkaset bajtów, a testy
/// niezależne od siebie mogą działać równolegle i nie przenoszą stanu.
private func loadInfoPlist() throws -> [String: Any] {
    let data = try Data(contentsOf: repositoryRoot.appending(path: "Resources/Info.plist"))
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    return plist as? [String: Any] ?? [:]
}

@Suite("Info.plist zgadza się z konfiguracją w kodzie")
struct InfoPlistTests {

    // Rozjazd identyfikatora cicho zepsuje SMAppService w etapie 4 — stąd ten test.
    @Test("CFBundleIdentifier odpowiada AppConfiguration.bundleIdentifier")
    func bundleIdentifier() throws {
        let plist = try loadInfoPlist()
        #expect(plist["CFBundleIdentifier"] as? String == AppConfiguration.bundleIdentifier)
    }

    // Nazwa musi się zgadzać z nazwą binarki kopiowanej przez bundle.sh.
    @Test("CFBundleExecutable to OneSheet")
    func executableName() throws {
        let plist = try loadInfoPlist()
        #expect(plist["CFBundleExecutable"] as? String == "OneSheet")
    }

    // Bez tego aplikacja pokaże ikonę w Docku i wejdzie do ⌘Tab.
    @Test("LSUIElement jest włączone")
    func uiElement() throws {
        let plist = try loadInfoPlist()
        #expect(plist["LSUIElement"] as? Bool == true)
    }

    @Test("LSMinimumSystemVersion to macOS 26.0")
    func minimumSystemVersion() throws {
        let plist = try loadInfoPlist()
        #expect(plist["LSMinimumSystemVersion"] as? String == "26.0")
    }
}
