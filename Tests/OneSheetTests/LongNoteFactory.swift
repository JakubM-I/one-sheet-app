import AppKit

/// Generator długiej, sformatowanej notatki do testów wydajności (etap 5).
///
/// Treść celowo nie jest jednym powtórzonym znakiem: akapity różnej długości,
/// część pogrubiona i przekreślona — serializator RTFD zapisuje przebiegi atrybutów,
/// więc dokument bez zmian formatowania byłby nierealistycznie łatwym przypadkiem.
enum LongNoteFactory {

    static func make(characterCount: Int) -> NSAttributedString {
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

        return text.attributedSubstring(from: NSRange(location: 0, length: characterCount))
    }
}
