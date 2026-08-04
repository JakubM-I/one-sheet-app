import os

/// Kategorie logowania. Zamiast `print` — `os.Logger` trafia do Konsoli systemowej,
/// działa też wtedy, gdy aplikacja jest uruchomiona z pakietu `.app`, bez terminala.
enum Log {
    static let app = Logger(subsystem: AppConfiguration.loggingSubsystem, category: "app")
    static let menuBar = Logger(subsystem: AppConfiguration.loggingSubsystem, category: "menubar")
    static let panel = Logger(subsystem: AppConfiguration.loggingSubsystem, category: "panel")
    static let editor = Logger(subsystem: AppConfiguration.loggingSubsystem, category: "editor")
    static let storage = Logger(subsystem: AppConfiguration.loggingSubsystem, category: "storage")
}
