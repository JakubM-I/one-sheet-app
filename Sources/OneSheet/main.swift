import AppKit
import OneSheetCore

// Punkt wejścia. Świadomie bez `NSApplicationMain` / `@main`:
// aplikacja nie ma pliku NIB ani okna głównego, a jawna pętla pozwala trzymać
// referencję na delegata (`NSApplication.delegate` jest słabe) bez sztuczek.
//
// Kod najwyższego poziomu w `main.swift` jest w Swift 6 domyślnie na `@MainActor`,
// więc tworzenie obiektów AppKit jest tu bezpieczne.

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()
