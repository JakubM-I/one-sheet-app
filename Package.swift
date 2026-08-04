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
        // Program testowy zamiast targetu XCTest — Command Line Tools nie zawierają
        // ani XCTest, ani swift-testing, więc `swift test` jest niedostępne.
        // Uruchamianie: ./scripts/test.sh
        .executableTarget(
            name: "OneSheetTests",
            dependencies: ["OneSheetCore"],
            path: "Tests/OneSheetTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
