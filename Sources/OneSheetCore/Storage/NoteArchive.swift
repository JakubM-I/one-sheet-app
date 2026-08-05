import AppKit

/// Warstwa dotykająca dysku. Bez stanu — pamięć o tym, co czeka na zapis, żyje w `NoteStore`.
///
/// Każda metoda albo kończy się powodzeniem, albo rzuca. Decyzję, co zrobić z błędem
/// (spróbować kopii zapasowej, odłożyć plik na bok, powtórzyć zapis), podejmuje `NoteStore`.
enum NoteArchive {

    // MARK: - Notatka

    /// Zapisuje treść, nie ryzykując istniejącej wersji.
    ///
    /// Trzy kroki i kolejność każdego z nich ma znaczenie:
    /// 1. serializacja do `FileWrapper` — może rzucić, a wtedy na dysku nic się nie zmieniło,
    /// 2. zapis do pliku roboczego w **tym samym katalogu** — warunek atomowej podmiany
    ///    (przenosiny między woluminami nie są atomowe),
    /// 3. `replaceItemAt(...)`, które podmienia katalog pakietu jednym ruchem i odkłada
    ///    poprzednią wersję jako kopię zapasową.
    ///
    /// W żadnym momencie nie istnieje stan, w którym `note.rtfd` jest niekompletny:
    /// albo jest stary w całości, albo nowy w całości.
    static func writeNote(_ text: NSAttributedString, to layout: NoteFileLayout) throws {
        try layout.createDirectoryIfNeeded()

        let wrapper = try text.fileWrapper(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )

        let fileManager = FileManager.default

        // Plik roboczy po nieudanym zapisie zostaje do diagnostyki, więc przed nowym
        // zapisem trzeba posprzątać po poprzedniej próbie. Notatki to nie dotyka.
        if fileManager.fileExists(atPath: layout.temporary.path(percentEncoded: false)) {
            try fileManager.removeItem(at: layout.temporary)
        }
        try wrapper.write(to: layout.temporary, options: .atomic, originalContentsURL: nil)

        guard fileManager.fileExists(atPath: layout.note.path(percentEncoded: false)) else {
            // Pierwszy zapis w życiu aplikacji: nie ma czego podmieniać ani kopiować.
            try fileManager.moveItem(at: layout.temporary, to: layout.note)
            return
        }

        // `replaceItemAt(...)` odmawia, gdy plik o nazwie kopii już istnieje. Kasujemy go
        // dopiero teraz, gdy nowa wersja leży już gotowa obok: w tym oknie czasu na dysku
        // wciąż jest kompletna, stara notatka.
        if fileManager.fileExists(atPath: layout.backup.path(percentEncoded: false)) {
            try fileManager.removeItem(at: layout.backup)
        }

        _ = try fileManager.replaceItemAt(
            layout.note,
            withItemAt: layout.temporary,
            backupItemName: AppConfiguration.Storage.backupFileName,
            // Bez tej opcji `replaceItemAt` kasuje kopię zapasową zaraz po udanej podmianie,
            // czyli robi dokładnie odwrotność tego, po co ją tworzymy.
            options: [.withoutDeletingBackupItem]
        )
    }

    static func readNote(at url: URL) throws -> NSAttributedString {
        // Jawny `documentType` jest tu celowy: bez niego czytnik zgaduje format i potrafi
        // wczytać uszkodzony plik jako zwykły tekst z krzaczkami zamiast zgłosić błąd.
        try NSAttributedString(
            url: url,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        )
    }

    // MARK: - Stan sesji

    static func writeState(_ state: EditorState, to layout: NoteFileLayout) throws {
        try layout.createDirectoryIfNeeded()
        // `state.json` to jeden mały plik, więc wystarczy atomowość, jaką daje `Data.write`.
        // Kopia zapasowa nie ma sensu: utrata pozycji kursora to nie utrata danych.
        try JSONEncoder().encode(state).write(to: layout.state, options: .atomic)
    }

    static func readState(at url: URL) -> EditorState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(EditorState.self, from: data)
    }
}
