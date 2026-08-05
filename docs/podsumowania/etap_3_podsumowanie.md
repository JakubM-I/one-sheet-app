# Etap 3 — Formatowanie — podsumowanie

**Data ukończenia:** 2026-08-05
**Status:** ukończony z odstępstwami (3 wpisy w rejestrze decyzji, żaden nie zmienia zakresu)

## 1. Co powstało

Notatkę da się teraz formatować: pogrubienie, kursywa, podkreślenie, przekreślenie, zmiana
rozmiaru czcionki, lista punktowana, wyrównanie, usunięcie formatowania i wklejenie bez
formatowania — wszystko skrótami z tabeli w [FUNKCJONALNOSCI.md](../FUNKCJONALNOSCI.md)
oraz z menu kontekstowego pola tekstu (podmenu „Formatowanie"). Każda operacja trafia do
autozapisu i cofa się jednym `⌘Z`. Dodatkowo tekst wklejony z jasnych stron WWW nie znika
już wizualnie po przełączeniu systemu na ciemny motyw.

## 2. Nowe pliki i ich rola

| Plik | Odpowiedzialność |
|---|---|
| `Sources/OneSheetCore/Editor/FormatMenu.swift` | jedyne źródło pozycji formatowania — buduje je i dla menu głównego, i dla menu kontekstowego |
| `Sources/OneSheetCore/Editor/FormattingCommands.swift` | trzy operacje bez standardowego selektora AppKit: przekreślenie, lista punktowana, usunięcie formatowania |
| `Sources/OneSheetCore/Editor/NoteTextView.swift` | podklasa `NSTextView` istniejąca tylko po to, by dokleić podmenu „Formatowanie" do menu kontekstowego |
| `Tests/OneSheetTests/FormattingCommandsTests.swift` | operacje własne: atrybuty, akapity, undo, sygnał autozapisu, round-trip RTFD |
| `Tests/OneSheetTests/FormatMenuTests.swift` | strażnik zgodności skrótów, wykonawców i tagów z tabelą ze specyfikacji |

Zmienione: `MainMenu` (menu „Format" obok „Edycji"), `EditorViewController` (właściciel
`FormattingCommands`, siatka bezpieczeństwa autozapisu, wspólne atrybuty domyślne,
mapowanie kolorów dla ciemnego motywu), `AppDelegate` (kolejność startu: najpierw edytor,
potem menu, bo menu celuje w obiekt edytora).

## 3. Jak to działa — mechanizmy

### Trzy rodzaje wykonawców jednej tabeli skrótów

- **Problem:** dziewięć operacji formatowania, a własnego kodu ma być tyle, ile konieczne.
- **Rozwiązanie:** każda pozycja menu „Format" ma jednego z trzech wykonawców.
  `⌘B`/`⌘I`/`⌘+`/`⌘-` celują wprost w `NSFontManager.shared` (akcje `addFontTrait:`
  i `modifyFont:`, parametr operacji siedzi w `NSMenuItem.tag`). `⌘U`, `⌘{`, `⌘|`
  i `⌥⇧⌘V` mają cel pusty — AppKit szuka wykonawcy w łańcuchu responderów i znajduje
  `NSTextView`, które te selektory (`underline:`, `alignLeft:`, `alignCenter:`,
  `pasteAsPlainText:`) po prostu ma. Dopiero trzy operacje bez odpowiednika w AppKit
  (`⌃⌘K`, `⌃⌘L`, `⌃⌘\`) celują we własny obiekt `FormattingCommands`.
- **Dlaczego tak:** `NSFontManager.addFontTrait(_:)` nie jest zwykłym „ustaw pogrubienie" —
  menedżer czcionek odczytuje bieżącą czcionkę zaznaczenia, przełącza cechę w obie strony
  i wysyła `changeFont(_:)` do pola tekstu, które stosuje zmianę do zaznaczenia **albo**
  do `typingAttributes`, gdy zaznaczenia nie ma. Pisanie tego samemu to powielanie AppKit-u
  z gorszym pokryciem przypadków brzegowych.
- **Na co uważać:** skróty ze znakiem z Shifta (`⌘{`, `⌘|`, `⌥⇧⌘V`) deklaruje się tym
  znakiem wprost w `keyEquivalent` (`"{"`, `"|"`, `"V"`), **bez** `.shift` w masce —
  ta sama pułapka, którą etap 2 opisał przy `⇧⌘Z`. Zapis z `.shift` kompiluje się
  i nigdy nie dopasowuje zdarzenia.

### Jedno źródło pozycji: menu główne i menu kontekstowe

- **Problem:** wymóg z workflow — lista skrótów i lista pozycji menu kontekstowego nie mogą
  się rozjechać.
- **Rozwiązanie:** `FormatMenu.makeItems(commands:)` to jedyna definicja pozycji.
  `MainMenu.install(formatting:)` wkłada je do ukrytego menu głównego (stamtąd działają
  skróty — mechanizm opisany w podsumowaniu etapu 2), a `NoteTextView.menu(for:)` dokleja
  te same pozycje do systemowego menu kontekstowego jako podmenu „Formatowanie".
  Test `FormatMenuTests` pilnuje dodatkowo zgodności z tabelą ze specyfikacji.
- **Dlaczego podmenu, a nie pozycje luzem:** systemowe menu kontekstowe `NSTextView`
  ma kilkanaście pozycji, a AppKit własne grupy (Font, Substitutions, Spelling) też trzyma
  w podmenu. Wpis w rejestrze decyzji.
- **Na co uważać:** `NSMenuItem` może należeć tylko do jednego menu, więc „te same pozycje"
  znaczy „budowane tą samą metodą", nie „współdzielone obiekty". Oraz: `NSMenuItem.target`
  nie trzyma celu przy życiu — `FormattingCommands` musi mieć właściciela, jest nim
  `EditorViewController`.

### `shouldChangeText` / `didChangeText` — trzy gwarancje w jednej parze wywołań

- **Problem:** operacja formatowania musi być cofalna jednym `⌘Z`, musi wyzwolić autozapis
  i nie może się wykonać, gdy pole tekstu edycji odmawia.
- **Rozwiązanie:** każda mutacja w `FormattingCommands` przechodzi przez
  `NSTextView.shouldChangeText(in:replacementString:)` z `replacementString: nil`
  (to udokumentowany zapis „zmieniam same atrybuty"), potem
  `NSTextStorage.beginEditing()`/`endEditing()` wokół właściwej zmiany, na końcu
  `didChangeText()`. `shouldChangeText` rejestruje w `undoManager` stan atrybutów całego
  zakresu — stąd jedno `⌘Z` cofa całość; `didChangeText()` wysyła `textDidChange`
  do delegata — a na nim wisi `NoteStore.scheduleSave`.
- **Dlaczego tak:** goła mutacja `NSTextStorage` działa i wygląda na prostszą, ale omija
  i undo, i autozapis — pogrubienie zniknęłoby przy restarcie. Dokładnie przed tym
  ostrzegała definicja ukończenia etapu.
- **Na co uważać:** kolejność. `shouldChangeText` rejestruje undo natychmiast, więc jawna
  grupa (`beginUndoGrouping`) musi być otwarta **przed** nim — w testach, gdzie nie kręci
  się pętla zdarzeń i `groupsByEvent` nie domknie grupy za nas, odwrotna kolejność kończy
  się niedomkniętą grupą i `undo()` nie ma czego cofnąć.

### Siatka bezpieczeństwa autozapisu — nasłuch samego magazynu tekstu

- **Problem:** para `shouldChangeText`/`didChangeText` obejmuje tylko nasz kod. Pogrubienie
  przez `NSFontManager` czy cofnięcie operacji formatowania mutują `NSTextStorage` własnymi
  drogami, bez gwarancji, że delegat pola tekstu się o tym dowie.
- **Rozwiązanie:** `EditorViewController` nasłuchuje
  `NSTextStorage.didProcessEditingNotification` i zgłasza zmianę treści, gdy
  `editedMask` zawiera `.editedAttributes`, a **nie** zawiera `.editedCharacters` —
  zmiany znaków zgłasza już `textDidChange` i bez tego filtra każde naciśnięcie klawisza
  szłoby do autozapisu podwójnie (debounce by to zniósł, ale po co).
- **Dlaczego nie `NSTextStorageDelegate`:** miejsce delegata magazynu zostaje wolne,
  a wzorzec „obserwator przez `NotificationCenter` + selektor" jest już w tym kontrolerze
  ustanowiony (przewijanie, pierwsze pokazanie panelu).
- **Na co uważać:** nazwa metody obserwatora. Pierwsza wersja nazywała się
  `textStorageDidProcessEditing(_:)` — dokładnie tak, jak opcjonalna metoda protokołu
  `NSTextStorageDelegate`. Kompilator Swift 6 potraktował ją jak (nieizolowanego) świadka
  protokołu i zgłosił ostrzeżenia o dostępie do stanu `@MainActor` spoza aktora. Zmiana
  nazwy na `storageDidProcessEditing(_:)` zamknęła temat.

### Lista punktowana — `NSTextList` w TextKit 2

- **Problem:** `⌃⌘L` ma zamieniać akapity zaznaczenia w listę punktowaną i z powrotem,
  a AppKit nie ma na to selektora.
- **Rozwiązanie:** styl akapitu. `NSMutableParagraphStyle.textLists` dostaje jeden wspólny
  `NSTextList(markerFormat: .disc, options: 0)` dla wszystkich akapitów operacji — osobne
  obiekty listy oznaczałyby ciąg list jednopunktowych, nie punkty jednej listy. TextKit 2
  buduje z takich akapitów `NSTextListElement` i **sam rysuje znaczniki** — w treści
  notatki nie ma żadnego znaku punktora, więc plik RTFD pozostaje czysty, a wyłączenie
  listy to tylko zdjęcie atrybutu.
- **Dlaczego akapity, nie zaznaczenie:** styl akapitu jest atrybutem całego akapitu.
  Operacja obejmuje więc pełne akapity pokrywające zaznaczenie
  (`NSString.paragraphRange(for:)`), nawet gdy zaznaczenie zaczyna się w ich środku.
- **Na co uważać:** dwa przypadki brzegowe. Pusty akapit nie ma znaków, na których atrybut
  mógłby wisieć — listę da się tam „włączyć" wyłącznie przez `typingAttributes`; z tego
  samego mechanizmu bierze się kontynuacja listy po Enterze, więc `typingAttributes`
  aktualizujemy przy każdym przełączeniu. Po drugie `paragraphRange(for:)` dla pozycji
  równej długości tekstu zwraca zakres pusty — pętla po akapitach musi się na nim
  zatrzymać, inaczej czytanie atrybutu spod tej pozycji kończy się wyjątkiem.

### Usunięcie formatowania, które nie kasuje załączników

- **Problem:** `⌃⌘\` ma sprowadzić zaznaczenie do stanu domyślnego. Najprostsze
  `setAttributes(_:range:)` zdejmuje **wszystkie** atrybuty — w tym `.attachment`,
  czyli wklejony obrazek zamieniłby się w znak zastępczy. Zasada nr 1 projektu: dane
  użytkownika są święte, także te spoza budowanych funkcji (uzasadnienie wyboru RTFD).
- **Rozwiązanie:** przed `setAttributes` spisujemy zakresy `.attachment`
  (`enumerateAttribute`), po nim wkładamy je z powrotem. Stan domyślny to
  `FormattingCommands.defaultAttributes` — ta sama definicja, którą
  `EditorViewController` ustawia jako startowe `typingAttributes`, więc „bez
  formatowania" i „świeże pole tekstu" nie mogą się rozjechać.
- **Na co uważać:** kolor w atrybutach domyślnych to dynamiczny `NSColor.labelColor`,
  nie zrzut jego aktualnej wartości — po `⌃⌘\` tekst ma dalej reagować na zmianę motywu.

### Czytelność w ciemnym motywie — mapowanie adaptacyjne kolorów

- **Problem:** tekst pisany w aplikacji ma dynamiczny `.labelColor`, ale tekst wklejony
  z jasnej strony WWW przynosi stały czarny — na ciemnym tle panelu byłby nieczytelny,
  a kryterium etapu wprost tego zakazuje.
- **Rozwiązanie:** `NSTextView.usesAdaptiveColorMappingForDarkAppearance = true`.
  Pole tekstu odwraca skrajne kolory przy **rysowaniu** w przeciwnym motywie;
  w `NSTextStorage` i w pliku RTFD zostają wartości oryginalne.
- **Dlaczego nie przepisywanie kolorów przy wklejeniu:** zmieniałoby treść użytkownika
  (utrata informacji o kolorze źródła) i wymagało własnej heurystyki „który kolor jest
  za ciemny". Mapowanie adaptacyjne jest odwracalne i systemowe. Wpis w rejestrze decyzji,
  bo wykracza poza literalny zakres etapu.

## 4. Decyzje i odstępstwa od planu

Cztery, wszystkie w rejestrze decyzji w [WORKFLOW.md](../WORKFLOW.md):

1. pozycje formatowania w menu kontekstowym jako podmenu „Formatowanie" zamiast doklejone luzem,
2. `usesAdaptiveColorMappingForDarkAppearance = true` — konieczne dla kryterium ciemnego motywu,
3. siatka bezpieczeństwa autozapisu przez `NSTextStorage.didProcessEditingNotification`
   (specyfikacja wymagała efektu — „każda operacja wyzwala autozapis" — a to jest wybrany mechanizm),
4. **zmiana decyzji z etapu 1 po weryfikacji ręcznej**: tło panelu jednolite zamiast szkła.
   `NSVisualEffectView` wyleciał w całości — okno jest nieprzezroczyste
   (`isOpaque = true`), a tło rysuje `NSWindow.backgroundColor = .textBackgroundColor`
   (dynamiczny kolor tła dokumentu: biały w jasnym motywie, grafitowy w ciemnym).
   Powód: rozmycie przepuszczało zawartość spod okna i psuło czytelność notatki,
   zwłaszcza w jasnym motywie.

## 5. Testy

- **Automatyczne:** 43 testy, wszystkie zielone (`./scripts/test.sh`), w tym 16 nowych.
  `FormattingCommands`: przekreślenie (zaznaczenie, zakres mieszany, atrybuty pisania),
  lista punktowana (pełne akapity, wspólny obiekt listy, `typingAttributes`), usunięcie
  formatowania (powrót do domyślnych, ochrona załącznika, reset atrybutów pisania),
  cofnięcie całej operacji jednym `undo()`, licznik `textDidChange` dla każdej operacji,
  nasłuch mutacji samych atrybutów w `EditorViewController`, round-trip przekreślenia
  i `NSTextList` przez serializację RTFD. `FormatMenu`: zgodność tytułów, skrótów, masek,
  wykonawców i tagów z tabelą ze specyfikacji.
- **Sprawdzone przeze mnie ręcznie:** `swift build` od zera bez ostrzeżeń;
  `./scripts/run.sh` — aplikacja startuje, w logu `Aplikacja uruchomiona` i wczytanie
  istniejącej notatki (125 znaków, dane nietknięte).
- **Wymaga weryfikacji przez Ciebie** (lista też w definicji ukończenia w workflow):
  - skróty standardowe (`⌘B`, `⌘I`, `⌘U`, `⌘+`/`⌘-`, `⌘{`/`⌘|`, `⌥⇧⌘V`) na zaznaczeniu
    i przy samym kursorze — wykonuje je AppKit, testy jednostkowe ich nie widzą,
  - `⌘Z` po operacji `NSFontManager` (pogrubienie, rozmiar),
  - wygląd listy punktowanej: znaczniki, zachowanie po Enterze — atrybuty są pod testem,
    rysowanie nie,
  - wklejenie sformatowanego fragmentu z Safari,
  - `⌘B` w innej aplikacji przy schowanym panelu (nie ma prawa nic zrobić),
  - ciemny motyw: tekst własny i wklejony z jasnej strony czytelne po przełączeniu,
  - `killall -9 OneSheet` sekundę po pogrubieniu — pogrubienie ma przeżyć restart.

## 6. Napotkane problemy

Jeden, wykryty kompilacją: metoda obserwatora nazwana `textStorageDidProcessEditing(_:)`
pokrywa się z opcjonalną metodą protokołu `NSTextStorageDelegate`, więc Swift 6 uznał ją
za nieizolowanego świadka protokołu i ostrzegał o dostępie do stanu `@MainActor` spoza
aktora — mimo że klasa w ogóle tego protokołu nie deklaruje. Zmiana nazwy na
`storageDidProcessEditing(_:)` usunęła kolizję. Wniosek na przyszłość: w podklasach
i delegatach AppKit nazwy „brzmiące systemowo" potrafią wpaść w cudze protokoły.

## 7. Dług techniczny

- `FormattingCommands.validateMenuItem(_:)` tylko włącza/wyłącza pozycje — nie ustawia
  `state` (znacznika ✓ przy aktywnym przekreśleniu czy liście) w menu kontekstowym.
  Kosmetyka, do rozważenia przy wykończeniu (etap 6).
- Lista punktowana zdaje się na automatyczne wcięcia TextKit 2 — jeśli ręczna weryfikacja
  pokaże, że znaczniki nachodzą na tekst, trzeba będzie dołożyć `headIndent`/
  `firstLineHeadIndent` do stylu akapitu listy.

## 8. Co dalej

Etap 4 — integracja z systemem: globalny skrót `⌥⌘N` przez Carbon `RegisterEventHotKey`,
menu kontekstowe ikony w belce („Uruchamiaj przy logowaniu" przez `SMAppService`, „Zakończ")
i ikona aplikacji. Z tego etapu korzysta bezpośrednio: menu kontekstowe ikony powstanie
w miejscu przygotowanym w `AppDelegate.showContextMenu()`, a wymóg podpisu ad-hoc dla
`SMAppService` obsługuje już `scripts/bundle.sh`.
