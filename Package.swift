// swift-tools-version: 6.0
import PackageDescription

// Podział na bibliotekę i cienki punkt wejścia nie jest ozdobnikiem: symbole targetu
// wykonywalnego nie są eksportowane, więc nie da się ich zlinkować z programem testowym.
// Cała logika musi mieszkać w bibliotece, żeby dało się ją testować.
let package = Package(
    name: "OneSheet",
    platforms: [.macOS("26.0")],
    targets: [
        // Cały kod aplikacji.
        .target(
            name: "OneSheetCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Punkt wejścia: kilka linii, które uruchamiają pętlę zdarzeń.
        .executableTarget(
            name: "OneSheet",
            dependencies: ["OneSheetCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Testy na swift-testing (`@Test`, `#expect`). Biblioteka jest częścią
        // Command Line Tools, ale SwiftPM szuka jej tam, gdzie kładzie ją Xcode —
        // brakujące ścieżki dokłada `scripts/test.sh`. Uruchamianie: ./scripts/test.sh
        .testTarget(
            name: "OneSheetTests",
            dependencies: ["OneSheetCore"],
            path: "Tests/OneSheetTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
