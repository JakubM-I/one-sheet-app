import Foundation

/// Minimalny harness testowy.
///
/// Dlaczego własny, a nie XCTest: Command Line Tools nie zawierają frameworku XCTest
/// ani biblioteki swift-testing (są częścią Xcode), więc `swift test` na tej maszynie
/// nie ma czego uruchomić. Zamiast instalować 10 GB narzędzi dla kilkunastu asercji,
/// testy są zwykłym programem — uruchamianym przez `./scripts/test.sh`.
///
/// Świadome ograniczenia: brak automatycznego wykrywania testów (rejestrujemy je ręcznie
/// w `main.swift`), brak równoległości, brak integracji z IDE.
@MainActor
final class TestHarness {

    private var currentSuite = ""
    private var passedCount = 0
    private var failures: [String] = []

    func suite(_ name: String, _ body: () throws -> Void) {
        currentSuite = name
        print("\n\u{001B}[1m\(name)\u{001B}[0m")
        do {
            try body()
        } catch {
            record(failure: "przerwany wyjątkiem: \(error)", test: "<suite>")
        }
    }

    func test(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passedCount += 1
            print("  \u{001B}[32m✓\u{001B}[0m \(name)")
        } catch let error as Expectation {
            record(failure: error.message, test: name)
            print("  \u{001B}[31m✗\u{001B}[0m \(name)")
            print("      \(error.message)")
            print("      \(error.file):\(error.line)")
        } catch {
            record(failure: "nieoczekiwany wyjątek: \(error)", test: name)
            print("  \u{001B}[31m✗\u{001B}[0m \(name) — nieoczekiwany wyjątek: \(error)")
        }
    }

    private func record(failure: String, test: String) {
        failures.append("\(currentSuite) › \(test): \(failure)")
    }

    /// Wypisuje podsumowanie i kończy proces. Kod wyjścia 1 przy jakimkolwiek błędzie,
    /// żeby skrypt (i przyszłe CI) wiedział, że testy padły.
    func finish() -> Never {
        print("")
        if failures.isEmpty {
            print("\u{001B}[32m\(passedCount) testów przeszło\u{001B}[0m")
            exit(0)
        }
        print("\u{001B}[31m\(failures.count) błędów, \(passedCount) przeszło\u{001B}[0m")
        for failure in failures {
            print("  • \(failure)")
        }
        exit(1)
    }
}

/// Niespełniona asercja. Rzucana zamiast przerywania procesu, żeby jeden zły test
/// nie ukrywał wyników pozostałych.
struct Expectation: Error {
    let message: String
    let file: String
    let line: Int
}

func expect(
    _ condition: Bool,
    _ message: @autoclosure () -> String = "warunek nie jest spełniony",
    file: String = #fileID,
    line: Int = #line
) throws {
    guard condition else {
        throw Expectation(message: message(), file: file, line: line)
    }
}

func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ label: @autoclosure () -> String = "",
    file: String = #fileID,
    line: Int = #line
) throws {
    guard actual == expected else {
        let prefix = label().isEmpty ? "" : "\(label()): "
        throw Expectation(
            message: "\(prefix)oczekiwano \(expected), otrzymano \(actual)",
            file: file,
            line: line
        )
    }
}
