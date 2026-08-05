import AppKit

// Generator długiej, sformatowanej notatki RTFD — część stanowiska testowego
// `scripts/longnote_stand.sh` (etap 5, hardening). Treść odpowiada generatorowi
// z testów (`LongNoteFactory`): akapity różnej długości, część pogrubiona
// i przekreślona, żeby serializator miał realistyczne przebiegi atrybutów.
//
// Użycie: swift scripts/longnote_gen.swift <ścieżka do note.rtfd> <liczba znaków>

let arguments = CommandLine.arguments
guard arguments.count == 3, let characterCount = Int(arguments[2]), characterCount > 0 else {
    FileHandle.standardError.write(
        Data("Użycie: swift scripts/longnote_gen.swift <ścieżka do note.rtfd> <liczba znaków>\n".utf8)
    )
    exit(1)
}
let destination = URL(fileURLWithPath: arguments[1])

let paragraph = "Notatka rośnie akapit po akapicie, a każdy z nich ma trochę inną długość i treść. "
let text = NSMutableAttributedString()
var index = 0

while text.length < characterCount {
    let line = NSMutableAttributedString(
        string: "Akapit \(index): \(paragraph)\n",
        attributes: [.font: NSFont.systemFont(ofSize: 14)]
    )
    if index.isMultiple(of: 5) {
        line.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 14),
            range: NSRange(location: 0, length: min(20, line.length))
        )
    }
    if index.isMultiple(of: 7) {
        line.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: min(12, line.length))
        )
    }
    text.append(line)
    index += 1
}

let trimmed = text.attributedSubstring(from: NSRange(location: 0, length: characterCount))

do {
    let wrapper = try trimmed.fileWrapper(
        from: NSRange(location: 0, length: trimmed.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
    )
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try wrapper.write(to: destination, options: .atomic, originalContentsURL: nil)
    print("Notatka \(trimmed.length) znaków zapisana: \(destination.path)")
} catch {
    FileHandle.standardError.write(Data("Zapis nieudany: \(error)\n".utf8))
    exit(1)
}
