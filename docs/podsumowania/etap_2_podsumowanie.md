# Etap 2 — Trwałość — podsumowanie

**Data ukończenia:** 2026-08-04
**Status:** ukończony. Weryfikacja ręczna przeszła 2026-08-04 z jednym wyjątkiem (restart Maca —
do sprawdzenia przy okazji) i **wykryła defekt spoza warstwy trwałości**: martwe skróty `⌘`.
Naprawione w tym samym etapie, opis w sekcji 3.

## 1. Co powstało

Notatka przeżywa zamknięcie aplikacji. Każda zmiana trafia na dysk po 0,7 s ciszy — bez
polecenia „Zapisz", bez zamykania panelu. Zapis jest atomowy i zostawia po sobie kopię
poprzedniej wersji, więc uszkodzenie pliku nie kończy się utratą treści. Po ponownym
uruchomieniu wraca nie tylko tekst z formatowaniem, ale też pozycja kursora i przewinięcia.

## 2. Nowe pliki i ich rola

| Plik | Odpowiedzialność |
|---|---|
| `Sources/OneSheetCore/Storage/NoteFileLayout.swift` | ścieżki plików; wydzielone, żeby testy pracowały w katalogu tymczasowym |
| `Sources/OneSheetCore/Storage/NoteArchive.swift` | jedyne miejsce dotykające dysku: serializacja RTFD, zapis atomowy, `state.json` |
| `Sources/OneSheetCore/Storage/NoteStore.swift` | **kiedy** zapisać (debounce, twardy limit, `flush`) i **co zrobić z błędem** |
| `Sources/OneSheetCore/Storage/EditorState.swift` | pozycja kursora i przewinięcia jako `Codable` |
| `Sources/OneSheetCore/App/MainMenu.swift` | niewidoczne menu główne — jedyne źródło skrótów `⌘` (naprawa defektu, patrz 3) |

Zmienione: `AppConfiguration` (sekcja `Storage`), `Log` (kategoria `storage`),
`EditorViewController` (odczyt/zapis treści i stanu, śledzenie przewijania),
`NotePanel` (`onHide`), `AppDelegate` (wczytanie na starcie, podpięcie autozapisu,
obserwatory systemowe), `Tests/OneSheetTests/NoteStoreTests.swift` (16 nowych testów).

## 3. Jak to działa — mechanizmy

### Zapis, który nie może zostawić uciętego pliku

- **Problem:** notatka to jedyny egzemplarz danych użytkownika. Przerwanie zapisu w połowie
  — awaria zasilania, `killall -9`, pełny dysk — nie może zamienić jej w plik ucięty w środku.
- **Rozwiązanie:** trzy kroki w `NoteArchive.writeNote(_:to:)`, każdy w takiej kolejności,
  że po przerwaniu w dowolnym momencie na dysku wciąż leży kompletny dokument:

```swift
let wrapper = try text.fileWrapper(from: fullRange, documentAttributes: [.documentType: .rtfd])
try wrapper.write(to: layout.temporary, options: .atomic, originalContentsURL: nil)
_ = try FileManager.default.replaceItemAt(
    layout.note, withItemAt: layout.temporary,
    backupItemName: "note.rtfd.backup",
    options: [.withoutDeletingBackupItem]
)
```

  Nowa wersja powstaje **obok**, jako `note.rtfd.writing`, i dopiero gotowa podmienia starą
  jednym ruchem systemu plików.
- **Dlaczego tak:** `Data.write(options: .atomic)` załatwiłoby atomowość dla jednego pliku,
  ale RTFD to pakiet katalogowy — składa się z `TXT.rtf` i ewentualnych załączników.
  `replaceItemAt` umie podmienić cały katalog i przy okazji odłożyć poprzednią wersję.
- **Na co uważać — trzy pułapki, każda wykryta przy pisaniu tego kodu:**
  1. **`replaceItemAt` domyślnie kasuje kopię zapasową** zaraz po udanej podmianie. Bez
     `.withoutDeletingBackupItem` cały mechanizm kopii istniałby wyłącznie w komentarzach.
  2. **`replaceItemAt` odmawia, gdy plik o nazwie kopii już istnieje.** Trzeba go skasować
     samemu — i robimy to dopiero wtedy, gdy nowa wersja leży już gotowa obok. W tym oknie
     czasu na dysku wciąż jest kompletna, stara notatka.
  3. **Plik roboczy musi być w tym samym katalogu** co docelowy. Podmiana między woluminami
     nie jest atomowa; system zrobiłby wtedy zwykłe kopiowanie.

Po nieudanym zapisie plik roboczy **zostaje** — do diagnostyki. Stąd stała nazwa zamiast
losowej: w katalogu nigdy nie zbierze się więcej niż jeden taki plik.

### Debounce i twardy limit — dwa terminy, wygrywa wcześniejszy

- **Problem:** zapis przy każdym naciśnięciu klawisza to serializacja całego dokumentu
  kilkanaście razy na sekundę. Ale sam debounce („zapisz po 0,7 s ciszy") ma wadę: kto pisze
  bez przerwy, ten nie zapisuje nic — każde naciśnięcie odsuwa termin o kolejne 0,7 s.
- **Rozwiązanie:** dwa terminy naraz i sen do wcześniejszego z nich.

```swift
let deadline = min(
    now.addingTimeInterval(debounceInterval),          // 0,7 s ciszy
    firstChange.addingTimeInterval(hardSaveLimit)      // 5 s od pierwszej niezapisanej zmiany
)
```

  `firstUnsavedChange` to moment pierwszej zmiany, która jeszcze nie trafiła na dysk. Zeruje
  się dopiero wtedy, gdy nic już nie czeka — nie po samym udanym zapisie treści. Gdyby zerował
  się wcześniej, przewinięcie po nieudanym zapisie wyglądałoby jak „pierwsza zmiana" i odsuwało
  ponowną próbę o kolejne pięć sekund.
- **Na co uważać:** `Task.sleep` rzuca przy anulowaniu, więc `try?` jest tu konieczne — ale
  samo `try?` nie wystarcza. Po przebudzeniu trzeba jeszcze sprawdzić `Task.isCancelled`,
  inaczej anulowane zadanie i tak wykona zapis.

### Dwie drogi zapisu: treść i sama pozycja

`NoteStore` ma osobne `scheduleSave(_:state:)` i `scheduleStateSave(_:)`. Nie jest to
ozdobnik: przewijanie długiej notatki generuje dziesiątki zdarzeń na sekundę, a każde z nich
przez wspólną drogę oznaczałoby ponowną serializację całego RTFD. Zapisy dzielą jeden zegar,
ale każdy dotyka tylko swojego pliku. Pokrywa to test „zmiana samej pozycji nie przepisuje
notatki" — sprawdza wprost, że po samym `scheduleStateSave` plik `note.rtfd` **nie powstał**.

### Odczyt awaryjny — trzy poziomy, każdy niżej to wpis w logu

```
note.rtfd  →  note.rtfd.backup  →  pusty dokument
```

`NoteStore.load()` nie rzuca **nigdy**. Brak notatki i uszkodzona notatka to dwa różne
problemy, ale żaden nie jest powodem, by aplikacja się nie uruchomiła.

Uszkodzony plik nie jest kasowany ani nadpisywany — trafia na bok jako
`note.rtfd.corrupted-20260804T195418`. Powód jest prosty: to, że *my* nie umiemy go odczytać,
nie znaczy, że nie odczyta go człowiek w TextEdit. Licznik na końcu nazwy obsługuje dwa
uszkodzenia w tej samej sekundzie; nadpisanie poprzedniej kwarantanny byłoby skasowaniem
danych, czyli dokładnie tym, przed czym ona chroni.

Drobiazg, który okazał się istotny: przy odczycie podajemy `documentType` jawnie.

```swift
try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtfd],
                       documentAttributes: nil)
```

Bez tego czytnik zgaduje format i potrafi wczytać uszkodzony plik jako zwykły tekst pełen
krzaczków — zamiast zgłosić błąd i uruchomić odzyskiwanie z kopii.

### Kiedy zapis następuje na pewno (`flush`)

Debounce chroni przed utratą ostatniej sekundy pisania, ale są momenty, w których nie ma
czasu na czekanie. `flush()` jest synchroniczny i wywoływany z pięciu miejsc:
`applicationWillTerminate`, `NSApplication.willResignActiveNotification`,
`NSWorkspace.willSleepNotification`, `NSWorkspace.willPowerOffNotification` oraz schowanie panelu.

- **Na co uważać:** powiadomienia `NSWorkspace` chodzą **własnym** centrum
  (`NSWorkspace.shared.notificationCenter`), nie domyślnym. Zarejestrowanie ich
  w `NotificationCenter.default` kompiluje się i po cichu nie robi nic — aplikacja traciłaby
  zapis przy uśpieniu i wylogowaniu, a wyszłoby to na jaw dopiero w praktyce.

Schowanie panelu jest tu najsłabszym z pięciu wyzwalaczy i tak było zaplanowane: po decyzji
z etapu 1 panel może stać otwarty tygodniami.

### Przewinięcie, czyli walka z leniwym układem TextKit 2

- **Problem:** `state.json` przechowuje przewinięcie w punktach (np. 6378). Ustawienie go
  zaraz po wczytaniu notatki nie działa: panel nie był jeszcze pokazany, TextKit nie rozłożył
  ani jednej linii, `NSTextView` ma wysokość kilkuset punktów i przewinięcie zostaje przycięte.
- **Pierwsze podejście — i dlaczego upadło:** ponawianie próby przy każdej zmianie ramki
  `NSTextView` (TextKit rozkłada tekst kawałkami i za każdym razem powiadamia o nowej
  wysokości), z anulowaniem, gdy użytkownik przewinie sam. Problem: „użytkownik przewinął sam"
  jest nierozróżnialne od korekt, które `NSClipView` robi samodzielnie przy rosnącym dokumencie.
  Pierwsza taka korekta kasowała zapamiętaną pozycję i przewinięcie nie wracało nigdy.
  Wykryte na stanowisku testowym: zapisane 6378, odtworzone 0.
- **Rozwiązanie:** jedna próba, w dobrze określonym momencie — przy pierwszym pokazaniu panelu
  (`NSWindow.didBecomeKeyNotification`, z drugą drogą przez `focusText()`) — i w dwóch krokach:

```swift
textView.scrollRangeToVisible(textView.selectedRange())   // zmusza TextKit do układu aż do kursora
let reachable = max(0, textView.frame.height - clipView.bounds.height)
clipView.scroll(to: NSPoint(x: 0, y: min(state.scrollOffset, reachable)))
```

  Pierwszy krok działa zawsze i sam w sobie stawia widok w okolicy kursora. Drugi dociąga do
  dokładnej pozycji, o ile rozłożony tekst sięga tak daleko.
- **Dlaczego nie `ensureLayout` na całym dokumencie:** dla notatki na 200 000 znaków to sekundy
  pracy przy każdym starcie, w tym rozkładanie tekstu, którego użytkownik nigdy nie zobaczy.
  Cena tej decyzji: przy notatce na 14 700 znaków przewinięcie wróciło na 6221 zamiast 6378 —
  różnica 2,5%, poniżej jednej linii tekstu na ekranie.
- **`viewDidAppear()` tu nie zadziała.** Widok edytora jest wstawiany jako podwidok tła panelu,
  więc kontroler nie trafia do łańcucha responderów okna — to dług techniczny odnotowany
  w etapie 1, który po raz pierwszy dał o sobie znać właśnie tutaj.

Przy okazji wyszła inna rzecz: `scrollView.automaticallyAdjustsContentInsets` dokłada wcięcie
pod przezroczysty pasek tytułu okna `.fullSizeContentView`. U nas jest zbędne — widok edytora
i tak zaczyna się 28 pt niżej — a psuło arytmetykę: „na samej górze" znaczyło
`bounds.origin.y == -4`, a nie zero. Wyłączone.

### Menu, którego nikt nie zobaczy — i bez którego nie działa `⌘V`

To nie należało do zakresu etapu. Wyszło przy weryfikacji ręcznej: wklejanie działało
z menu kontekstowego, ale `⌘V` nie robiło nic.

- **Objaw był węższy niż problem.** Pomiar syntetycznymi zdarzeniami klawiatury pokazał, że
  martwe są **wszystkie** skróty z `⌘` — `⌘V`, `⌘C`, `⌘X`, `⌘A`, `⌘Z`, `⇧⌘Z`. Sprawdzony
  akurat został ten jeden.
- **Przyczyna:** w AppKit standardowe skróty edycyjne **nie są** wiązaniami klawiszy
  `NSTextView`. Nie ma ich w `StandardKeyBinding.dict` — pochodzą wyłącznie z `keyEquivalent`
  pozycji menu „Edycja". Projekt nie miał w ogóle `NSApp.mainMenu`, więc `NSApplication`
  nie miało czego odpytać i zdarzenie lądowało w `keyDown:`, gdzie nikt się nim nie interesował.
  Menu kontekstowe działało, bo to zupełnie inna ścieżka: pozycje wywołują `paste(_:)`
  bezpośrednio na polu tekstu.
- **Dlaczego nikt tego nie zauważył wcześniej:** specyfikacja w sekcji 3.3 twierdziła, że
  aplikacja `.accessory` nie ma menu głównego i `NSMenuItem.keyEquivalent` nie zadziała.
  To była nieprawda. Aplikacja `.accessory` nie ma **paska** menu, ale `NSApp.mainMenu` istnieje
  jako obiekt i `NSApplication.sendEvent(_:)` odpytuje go przez `performKeyEquivalent(with:)`,
  zanim odda zdarzenie oknu kluczowemu. Pomiar na prawdziwym `AppDelegate`:

| | bez `mainMenu` | z `mainMenu` |
|---|---|---|
| `⌘A` | zaznacza 0 z 15 znaków | zaznacza 15 z 15 |
| `⌘V` | nic | wkleja z zachowaniem formatowania |
| `⌘Z` / `⇧⌘Z` | nic | cofa i ponawia |

- **Rozwiązanie:** `MainMenu.install()` w `applicationDidFinishLaunching`, jedno menu „Edycja"
  ze standardowym zestawem. Pozycje nie mają `target` — puste `target` znaczy „szukaj wykonawcy
  w łańcuchu responderów", a tam siedzi `NSTextView`. To on wykonuje `paste(_:)` i on decyduje
  przez `validateUserInterfaceItem(_:)`, czy pozycja jest w danej chwili aktywna. Zero własnej
  logiki — cała robota jest po stronie AppKit-u, brakowało tylko punktu zaczepienia.
- **Na co uważać — `⇧⌘Z` deklaruje się wielką literą:**

```swift
menu.addItem(withTitle: "Ponów", action: Selector(("redo:")), keyEquivalent: "Z")   // działa
```

  Zapis `keyEquivalent: "z"` z maską `[.command, .shift]` wygląda naturalniej, kompiluje się
  i **nigdy nie dopasowuje zdarzenia**. Wykryte pomiarem: po naciśnięciu skrótu `canRedo`
  pozostawało `true`, czyli `redo:` nie zostało wywołane. Shift jest częścią samego znaku,
  nie osobnym modyfikatorem.
- **Drugi drobiazg, sprawdzony osobno:** system sam dokłada do menu „Edycja" własne pozycje
  (dyktowanie, „Emoji & Symbols", AutoFill) razem z wariantami alternatywnymi — 19 pozycji
  zamiast zadeklarowanych 9. Wyglądało to na wstrzykiwanie przy każdym zdarzeniu, więc
  zmierzyłem: po 60 naciśnięciach `⌘A` liczba pozycji nie drgnęła. Jednorazowa budowa, nie wyciek.

Konsekwencje dla etapu 3 są większe niż sama poprawka: zamiast lokalnego monitora `keyDown`
formatowanie może pójść przez to samo menu, standardowymi selektorami AppKit
(`addFontTrait:`, `underline:`, `alignLeft:`, `pasteAsPlainText:`). Zakres etapu 3 w workflow
i sekcja 3.3 specyfikacji zostały przepisane, a ryzyko „monitor przechwytuje skróty innych
aplikacji" z sekcji 8 znika — `performKeyEquivalent` dotyczy wyłącznie zdarzeń dostarczonych
do naszej aplikacji.

### Dlaczego `NoteStore` trzyma referencję, a nie kopię

`pendingText` wskazuje na żywy `NSTextStorage` pola tekstu, a nie na jego kopię. Kopiowanie
całej notatki przy każdym naciśnięciu klawisza kosztowałoby dokładnie tyle, ile próbuje
oszczędzić debounce. Jest to bezpieczne, bo cały `NoteStore` i cały dostęp do tekstu siedzą
na `@MainActor`: treść nie może się zmienić „w trakcie" zapisu, bo zapis jest synchroniczny
na tym samym wątku, co edycja. Zapisujemy po prostu stan aktualny w chwili zapisu.

### Wczytanie notatki nie może wyglądać jak edycja

Dwie warstwy tej samej ochrony. `EditorViewController.restore(...)` podnosi flagę `isRestoring`,
która wycisza `textDidChange` i `textViewDidChangeSelection`; `AppDelegate` dodatkowo wczytuje
treść **przed** podpięciem callbacków. Bez tego pierwszą czynnością aplikacji po starcie byłby
zapis tego, co przed chwilą wczytała. Przy okazji `undoManager.removeAllActions()` — `⌘Z` tuż
po starcie nie ma czego cofać.

## 4. Decyzje i odstępstwa od planu

1. **`load()` zwraca `LoadedNote` (treść + stan), nie samo `NSAttributedString`.** Specyfikacja
   w sekcji 3.4 podaje szkic API sprzed decyzji o `state.json`. Skoro pozycja kursora jest
   wczytywana razem z treścią, zwracanie jej osobnym wywołaniem tylko rozdzielałoby dwie
   rzeczy, które i tak są potrzebne w tym samym momencie.
2. **`scheduleSave(_:state:)` zamiast `scheduleSave(_:)` plus osobne `scheduleStateSave(_:)`.**
   Uzasadnienie w sekcji „Dwie drogi zapisu".
3. **Przewinięcie przywracane przy pierwszym pokazaniu panelu, nie przy wczytaniu notatki.**
   Wymuszone przez leniwy układ TextKit 2 — opis wyżej.
4. **`MainMenu` dołożone poza pierwotnym zakresem etapu.** Skróty edycyjne są w zakresie
   z [FUNKCJONALNOSCI.md](../FUNKCJONALNOSCI.md) sekcja 3 („pełne, standardowe zachowanie
   `NSTextView`", „nieograniczone cofanie i ponawianie `⌘Z` / `⇧⌘Z`"), więc to naprawa defektu,
   nie nowa funkcja. Bez niej kryterium „wklej fragment z Safari" nie da się przejść z klawiatury.
5. **Sekcja 3.3 specyfikacji sprostowana, zakres etapu 3 przepisany.** Uzasadnienie w sekcji 3.

Wszystkie odstępstwa dopisane do rejestru decyzji w [WORKFLOW.md](../WORKFLOW.md).

## 5. Testy

**Automatyczne — 27 testów, wszystkie przechodzą** (11 z etapów 0–1 + 16 nowych).
Każdy test warstwy `Storage` pracuje we własnym katalogu tymczasowym; żaden nie dotyka
prawdziwej notatki w `~/Library/Application Support/OneSheet`.

- treść i pogrubienie przeżywają zapis i ponowny odczyt
- pusta notatka też jest zapisywana (skasowanie treści to zmiana jak każda)
- drugi zapis odkłada poprzednią wersję jako `note.rtfd.backup`, pierwszy jeszcze nie
- po udanym zapisie w katalogu są dokładnie trzy pliki — żadnego roboczego
- uszkodzona notatka jest odtwarzana z kopii zapasowej
- uszkodzony plik trafia do kwarantanny **bajt w bajt**, nie do kosza
- uszkodzona notatka bez kopii daje pustą kartkę, nie wywrotkę
- brak `note.rtfd` przy istniejącej kopii — treść wraca z kopii
- `state.json`: round-trip, uszkodzony jest ignorowany bez szkody dla treści
- zmiana samej pozycji nie tworzy pliku notatki
- debounce: zapisu nie ma natychmiast, jest po ciszy; kolejna zmiana odsuwa termin
- twardy limit zapisuje mimo nieprzerwanego pisania co 100 ms
- `flush` anuluje zaplanowany zapis i wykonuje go od razu; bez zmian nie tworzy nic

**Sprawdzone przeze mnie na jednorazowym stanowisku testowym** (program poza repozytorium,
uruchamiający prawdziwy `AppDelegate` i sterujący polem tekstu programowo; po użyciu skasowany
razem z katalogiem, który zdążył utworzyć):

1. Wpisanie zdania, brak jakiegokolwiek `flush`, `SIGKILL` po 1,3 s → treść jest na dysku.
   To jest kryterium akceptacji nr 4 z opisu funkcjonalności, sprawdzone dosłownie.
2. Ponowne uruchomienie → wraca treść (14 691 znaków), zaznaczenie (14 686,0)
   i przewinięcie (6378 → 6221).
3. Podmiana `note.rtfd` na śmieci → wraca treść z kopii zapasowej, uszkodzony plik ląduje
   jako `note.rtfd.corrupted-20260804T195418`, w katalogu nie ubywa nic poza nim.
4. Czysty `swift build` od zera bez ostrzeżeń; `./scripts/run.sh` uruchamia aplikację.
5. Aplikacja po starcie **nie tworzy żadnego pliku** — katalog powstaje dopiero przy
   pierwszym zapisie.

6. Po dołożeniu `MainMenu`, na prawdziwym `AppDelegate`: `⌘A` zaznacza 9 z 9, `⌘C`+`⌘V` podwaja
   treść, `⌘Z` cofa, `⇧⌘Z` ponawia, `⌘X` wycina.

**Zweryfikowane przez użytkownika — 2026-08-04:**

1. ✅ Treść przeżywa ubicie procesu przy panelu otwartym przez cały czas.
2. ✅ Wklejenie sformatowanego fragmentu i restart aplikacji — formatowanie na miejscu.
   Przy okazji **wykryty defekt**: wklejanie działało wyłącznie z menu kontekstowego,
   `⌘V` nie robiło nic. Naprawione, opis w sekcji 3.
3. ⬜ Restart Maca — do sprawdzenia przy najbliższej okazji.
4. ➖ Dokładność przewinięcia przy bardzo długiej notatce — uznane za detal, zostaje jako dług.

**Zostało do sprawdzenia:**

1. Restart Maca — jedyny test ścieżki `flush` na `willPowerOffNotification`.
2. Opcjonalnie, ręczny test odzysku z kopii zapasowej:

```bash
rm -rf ~/Library/Application\ Support/OneSheet/note.rtfd && echo zepsute > ~/Library/Application\ Support/OneSheet/note.rtfd
```

## 6. Napotkane problemy

**Przewinięcie nie wracało (zapisane 6378, odtworzone 0).** Pierwsza implementacja ponawiała
próbę przy każdej zmianie ramki `NSTextView` i anulowała ją, gdy `NSClipView` zgłosił
przewinięcie „nie od nas". Okazało się, że `NSClipView` sam koryguje `bounds`, gdy dokument
rośnie — pierwsza taka korekta kasowała zapamiętaną pozycję. Przepisane na jedną próbę
w pierwszym pokazaniu panelu; opis w sekcji 3. Wykryte na stanowisku testowym, nie po fakcie.

**`scrollOffset: -4` zamiast zera.** `NSScrollView` sam dokłada wcięcie pod przezroczysty pasek
tytułu okna `.fullSizeContentView`. Wyłączone przez `automaticallyAdjustsContentInsets = false`.

**`replaceItemAt` i kopia zapasowa.** Dwie rzeczy, których nie widać w sygnaturze metody:
domyślnie kasuje kopię po udanej podmianie, i odmawia pracy, gdy plik o nazwie kopii już
istnieje. Obie opisane w sekcji 3.

**Martwe skróty `⌘` — defekt spoza tego etapu, znaleziony przy jego weryfikacji.** Opis
w sekcji 3. Warto zapamiętać dwie rzeczy. Po pierwsze: objaw („nie działa `⌘V`") był węższy
niż problem („nie działa żaden skrót `⌘`"); gdyby poprzestać na objawie, `⌘Z` zostałoby martwe
do końca projektu. Po drugie: przyczyną było zdanie w specyfikacji, w które nikt nie zwątpił,
bo brzmiało wiarygodnie. Kosztowało to trzy pomiary i przepisanie zakresu etapu 3 —
ale w drugą stronę oszczędza pisanie własnego monitora zdarzeń.

## 7. Dług techniczny

- **Nieudany zapis jest ponawiany dopiero przy następnej zmianie treści.** Jeśli dysk zapełni
  się dokładnie w chwili zapisu i użytkownik przestanie pisać, notatka zostanie w pamięci do
  najbliższego `flush` (schowanie panelu, uśpienie, zamknięcie). Nie ma osobnego ponawiania
  z odstępem. Do przeglądu w etapie 5 („przegląd wszystkich ścieżek błędu w `NoteStore`").
- **Pliki `note.rtfd.corrupted-*` nikną same.** To celowe — kasowanie danych użytkownika nie
  wchodzi w grę — ale w README z etapu 6 musi się znaleźć zdanie, skąd się biorą i że można
  je usunąć ręcznie.
- **Przewinięcie odtwarza się z dokładnością do ostatniego rozłożonego fragmentu.** Świadomy
  kompromis na rzecz czasu startu; jeśli w praktyce będzie przeszkadzać, poprawką jest
  `ensureLayout` ograniczone do zakresu od początku dokumentu do zapamiętanego przewinięcia.
- **Zachowanie przy notatce na 200 000 znaków nie było mierzone.** Stanowisko testowe
  sprawdzało 14 700 znaków. Pomiary są zakresem etapu 5.

## 8. Co dalej

Etap 3 to formatowanie — i po ustaleniach z tego etapu wygląda inaczej, niż zakładała
specyfikacja: zamiast lokalnego monitora `keyDown` rozszerzamy o menu „Format" to samo ukryte
menu główne, które właśnie powstało. Większość operacji ma gotowe selektory w AppKit
(`addFontTrait:`, `modifyFont:`, `underline:`, `alignLeft:`, `pasteAsPlainText:`); własnego
obiektu docelowego wymagają tylko przekreślenie, lista punktowana i usunięcie formatowania.
Te same pozycje zbudują menu kontekstowe, więc skróty i menu nie będą mogły się rozjechać.

Z tego etapu wynikają dwie rzeczy istotne dla następnego. Po pierwsze, każda
operacja formatowania musi kończyć się wywołaniem `textDidChange` — inaczej pogrubienie nie
uruchomi autozapisu i przepadnie. Skoro operacje idą przez `NSTextStorage` i grupy cofania,
trzeba to sprawdzić wprost, bo bezpośrednia mutacja `NSTextStorage` **nie** powiadamia delegata
pola tekstu. Po drugie, format RTFD już przetrwał round-trip z atrybutem `.font` — reszta
atrybutów formatowania (podkreślenie, przekreślenie, `NSTextList`, wyrównanie) korzysta z tej
samej drogi i nie wymaga zmian w warstwie `Storage`.
