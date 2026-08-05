# Dodatek — Pasek formatowania — podsumowanie

**Data ukończenia:** 2026-08-05
**Status:** wdrożone i zweryfikowane (zmiana po zamknięciu etapu 6, ze zmianą zakresu)

## 1. Co powstało

Nad polem tekstu pojawił się pasek z sześcioma przyciskami: pogrubienie, kursywa,
podkreślenie, przekreślenie, lista punktowana i usunięcie formatowania. Przyciski
odzwierciedlają stan tekstu pod kursorem — „B" jest wciśnięte, gdy kursor stoi w pogrubionym
fragmencie. Wcześniej te operacje były dostępne wyłącznie pod skrótami klawiszowymi i w
podmenu menu kontekstowego, czyli dwa kliknięcia i celowanie w listę.

Pasek zajmuje obszar dotychczasowego, pustego pasa do przeciągania okna i sam przejmuje jego
rolę. Chrome panelu zmalało z 58 pt (28 pusty pas + 30 pasek) do 40 pt, więc przy okazji
przybyło 18 pt na tekst.

## 2. Nowe pliki i ich rola

| Plik | Odpowiedzialność |
|---|---|
| `Sources/OneSheetCore/Editor/FormatBar.swift` | budowa przycisków z pozycji menu, przekazywanie akcji, odświeżanie stanu, przeciąganie okna |
| `Sources/OneSheetCore/Editor/FormattingState.swift` | odczyt „czy ta cecha jest teraz włączona" — jedno źródło dla przełączania i dla podświetlenia |
| `Tests/OneSheetTests/FormatBarTests.swift` | 8 testów: komplet przycisków, odzwierciedlanie stanu, kliknięcie, fokus |

Zmienione: `EditorViewController` (widok to teraz kontener pasek + pole tekstu),
`FormattingCommands` (odczyt stanu przeniesiony do `FormattingState`), `AppConfiguration`
(wysokość i odstępy paska, usunięte `Panel.dragStripHeight`), `NotePanel` (zniknął odstęp
na pasek tytułu).

## 3. Jak to działa — mechanizmy

### Trzy drogi, jedno źródło

- **Problem:** ta sama operacja jest teraz dostępna na trzy sposoby — skrótem, z menu
  kontekstowego i przyciskiem. To trzy okazje, żeby się rozjechały: przycisk mógłby wykonać
  coś innego niż `⌘B`, a podświetlenie pokazywać coś innego, niż zrobi kliknięcie.
- **Rozwiązanie:** pasek nie zna żadnej operacji formatowania. Bierze gotowe pozycje z
  `FormatMenu.makeItems(commands:)` — z tego samego źródła, z którego powstaje menu — i
  wyciąga z nich cel oraz akcję. Dopasowanie po parze (akcja, `tag`), bo pogrubienie i
  kursywa dzielą selektor `addFontTrait:` i różnią się wyłącznie maską cechy w `tag`.

  ```swift
  guard let item = items.first(where: { $0.action == command.action && $0.tag == command.tag })
  ```

- **Dlaczego tak:** alternatywą było zadeklarowanie w pasku własnych selektorów i celów.
  Kompiluje się identycznie, ale przy pierwszej zmianie w `FormatMenu` cicho przestaje
  odpowiadać rzeczywistości.
- **Na co uważać:** gdy pozycja menu zmieni akcję lub `tag`, dopasowanie zwraca `nil` i pasek
  **po cichu** pomija przycisk — zostaje tylko wpis w logu. Dlatego pierwszy test w suicie
  sprawdza komplet sześciu etykiet, a nie „czy pasek się zbudował".

### Przekazywanie akcji zamiast wywoływania

- **Problem:** pozycje menu mają trzy różne rodzaje celu. `addFontTrait:` wykonuje
  `NSFontManager.shared`, `toggleStrikethrough:` — obiekt `FormattingCommands`, a `underline:`
  ma cel pusty, co znaczy „szukaj wykonawcy w łańcuchu responderów".
- **Rozwiązanie:** przycisk celuje w sam pasek, a ten przekazuje akcję dalej:

  ```swift
  @objc private func runCommand(_ sender: NSButton) {
      guard let binding = bindings.first(where: { $0.button === sender }) else { return }
      NSApp.sendAction(binding.action, to: binding.target, from: sender)
      refresh()
  }
  ```

  `NSApp.sendAction(_:to:from:)` z `to: nil` robi dokładnie to samo co pozycja menu z pustym
  celem — rusza łańcuchem responderów, na którego końcu siedzi `NSTextView`.
- **Dlaczego tak:** nadawcą zostaje przycisk, a to istotne — `NSFontManager.addFontTrait(_:)`
  czyta maskę cechy z `tag` **nadawcy**. Gdyby przekazać `self`, pogrubienie i kursywa
  przestałyby się różnić. Drugi zysk to jedyny pewny moment na odświeżenie stanu (patrz niżej).

### Odczyt stanu: „włączone" znaczy „w całym zakresie"

- **Problem:** trzeba odpowiedzieć na pytanie „czy zaznaczenie jest pogrubione", gdy połowa
  jest, a połowa nie. I na to samo pytanie, gdy nic nie jest zaznaczone.
- **Rozwiązanie:** `FormattingState` przyjmuje jedną zasadę: cecha jest włączona wyłącznie
  wtedy, gdy obejmuje **cały** zakres. Pusty zakres pyta `typingAttributes`, bo nie ma wtedy
  znaków, na których atrybut mógłby wisieć.
- **Dlaczego tak:** to nie jest arbitralny wybór — dokładnie tę zasadę stosowały już
  przełączniki z etapu 3 (zaznaczenie w połowie przekreślone: pierwsze `⌃⌘K` ujednolica,
  drugie zdejmuje). Gdyby pasek liczył inaczej, przycisk pokazywałby stan „włączone", a
  kliknięcie i tak by włączało. Predykaty były prywatne w `FormattingCommands` — wyciągnięcie
  ich do osobnego typu było warunkiem, żeby nie istniały w dwóch kopiach.
- **Na co uważać:** `enumerateAttribute` na zakresie o długości zero **nie woła bloku ani
  razu**, więc pętla kończy się z wynikiem „wszędzie włączone". Stąd `guard range.length > 0`
  przed każdą pętlą, a nie po niej.

### Kiedy odświeżać podświetlenie

- **Problem:** formatowanie pod kursorem zmienia się na kilka sposobów i tylko część z nich
  wysyła powiadomienie.
- **Rozwiązanie:** trzy nasłuchy plus jeden przypadek obsłużony ręcznie:

  | Zdarzenie | Sygnał |
  |---|---|
  | ruch kursora, zmiana zaznaczenia | `NSTextView.didChangeSelectionNotification` |
  | edycja treści lub atrybutów | `NSTextStorage.didProcessEditingNotification` |
  | zmiana atrybutów wpisywania | `NSTextView.didChangeTypingAttributesNotification` |
  | kliknięcie we własny przycisk | jawne `refresh()` w `runCommand(_:)` |

- **Na co uważać:** `⌘B` przy pustym zaznaczeniu nie zmienia ani jednego znaku — zmienia
  wyłącznie `typingAttributes`. Bez czwartego wiersza tej tabeli przycisk zostawałby wtedy
  w starym stanie. Drugi haczyk: jedno naciśnięcie klawisza potrafi wysłać trzy powiadomienia
  naraz, a odczyt atrybutów przy dużym zaznaczeniu nie jest darmowy, więc odświeżenie jest
  zbierane do jednego na obrót pętli zdarzeń (flaga `isRefreshScheduled` + `async`).

### Scalenie pasa przeciągania z paskiem ikon

- **Problem:** przez chwilę panel miał dwa pasy: pusty 28-punktowy uchwyt do przesuwania okna
  i pod nim 30-punktowy rząd ikon. Wyglądało to jak niedokończony interfejs.
- **Rozwiązanie:** pasek ikon przesunięty na obszar niewidocznego paska tytułu, wysokość 40 pt,
  przyciski 24 pt wyśrodkowane w oknie. Przeciąganie przejmuje sam pasek:

  ```swift
  override func mouseDown(with event: NSEvent) {
      window?.performDrag(with: event)
  }
  ```

- **Dlaczego tak:** komentarz z etapu 1 twierdził, że pod pasem przeciągania „nie dałoby się
  kliknąć", i na tej podstawie edytor był odsuwany o 28 pt. Gdyby to była prawda, jedyną drogą
  byłby `NSToolbar` w stylu `.unifiedCompact` — natywny, ale kosztem przebudowy chrome okna:
  rezygnacji z `.fullSizeContentView`, delegata toolbara, walidacji pozycji i menu
  dostosowywania. Zamiast zgadywać, wykonałem pomiar `hitTest` od widoku ramki okna: przycisk
  umieszczony 6, 14 i 20 pt od górnej krawędzi (przy pasku tytułu wysokim na 32 pt) jest
  zwracany prawidłowo. **Kliknięcia tam docierają**, więc cała przebudowa była zbędna.
- **Na co uważać:** założenie z etapu 1 było prawdziwe w połowie. Zwykły `NSView` zwraca w
  `hitTest` samego siebie na całej swojej powierzchni, więc pasek położony na obszarze paska
  tytułu połyka przeciąganie — okna nie dałoby się ruszyć bez jawnego `performDrag`.
  Przyciski obsługują swoje kliknięcia same i do `mouseDown` paska nie docierają, dzięki czemu
  chwycić można wszędzie poza ikoną.

### Dwa drobiazgi, które łatwo przeoczyć

- **`refusesFirstResponder = true` na każdym przycisku.** Bez tego kliknięcie zabiera fokus
  polu tekstu i znika zaznaczenie, które użytkownik właśnie chce sformatować.
- **`NSBox` z `boxType = .separator` ma własną wysokość 5 pt.** Wpięty przy dolnej krawędzi
  paska wystawał 2 pt na pole tekstu i przechwytywał tam kliknięcia — wąski pasek, w którym
  kursor nie stawia się w tekście. Zastąpiony zwykłym widokiem z jawną wysokością 1 pt.
  Ten z kolei wymaga przeliczenia koloru przy zmianie motywu: `NSColor.separatorColor` jest
  kolorem dynamicznym, ale `cgColor` zapamiętuje jedną konkretną wartość, więc kolor jest
  rozwiązywany na nowo w `viewDidChangeEffectiveAppearance()`.

## 4. Decyzje i odstępstwa od planu

To jest **zmiana zakresu**, nie realizacja planu. `FUNKCJONALNOSCI.md` w sekcji 2 mówiło
wprost „bez pasków narzędzi". Zapis został zmieniony świadomie, po decyzji użytkownika, a nie
obejrzany bokiem — wraz z uzasadnieniem, gdzie przebiega nowa granica.

Odrzucone alternatywy:

- **pływający pasek nad zaznaczeniem** (wzorzec z Notion, Medium) — wymaga własnego okna,
  śledzenia geometrii zaznaczenia i decydowania, kiedy zniknąć; obcy w natywnej aplikacji,
  a przede wszystkim nie działa przy pustym zaznaczeniu, czyli przy włączaniu cechy **przed**
  pisaniem;
- **samo spłaszczenie menu kontekstowego** — nie usuwa problemu, tylko go skraca;
- **`NSToolbar` w stylu `.unifiedCompact`** — patrz pomiar `hitTest` wyżej.

Granica zakresu pozostaje ostra: sześć przycisków. Rozmiar czcionki, wyrównanie i wklejanie
bez formatowania zostają wyłącznie w menu kontekstowym i pod skrótami — pasek ma być rzędem
ikon, nie wstążką.

Pięć wpisów w rejestrze decyzji w [WORKFLOW.md](../WORKFLOW.md): zmiana zakresu, zasada
jednego źródła, scalenie pasków, sprostowanie założenia z etapu 1 oraz powód odrzucenia
`NSToolbar`.

## 5. Testy

**Automatyczne:** 8 nowych testów w `FormatBarTests`, łącznie 78 w 12 suitach, `./scripts/test.sh`
zielony. Pokrywają: komplet sześciu przycisków w kolejności, obecność ikony i podpowiedzi ze
skrótem, podświetlenie pogrubienia, brak podświetlenia przy zaznaczeniu pogrubionym w połowie,
odzwierciedlanie przekreślenia i listy, brak stanu na „usuń formatowanie", wykonanie operacji
po kliknięciu oraz `refusesFirstResponder`. Testy z etapu 3 (`FormattingCommandsTests`) pokryły
przy okazji przeniesienie odczytu stanu do `FormattingState` — przeszły bez zmian.

**Sprawdzone przeze mnie:**

- wygląd paska w obu motywach — wyrenderowany do PNG przez `cacheDisplay(in:to:)` na
  odizolowanym widoku; ikony czytelne, włos widoczny;
- geometria po scaleniu — pasek 40 pt od górnej krawędzi, pole tekstu od 40 pt, przyciski
  24 pt osadzone 8 pt od góry, poziomo 74,5…305,5 przy oknie 380, czyli środek dokładnie 190;
- trafienia — `hitTest` od widoku ramki okna dochodzi do wszystkich sześciu ikon mimo
  nakładającego się paska tytułu;
- start aplikacji na odizolowanym katalogu danych (`ONESHEET_DATA_DIRECTORY`) — bez błędów
  w logu, prawdziwa notatka nietknięta;
- podmiana kopii w `/Applications` — stary proces zakończył się przez `applicationWillTerminate`,
  nowy wczytał notatkę bez utraty treści.

**Zweryfikowane przez użytkownika:** działanie wszystkich przycisków, wyśrodkowanie,
przeciąganie okna za pasek oraz skalowanie okna za górną krawędź (jedyne realne ryzyko
scalenia — obszar zmiany rozmiaru obsługuje ramka okna, zanim zdarzenie trafi do widoków).

## 6. Napotkane problemy

- **`perform` koliduje z `NSObject.perform(_:)`.** `#selector(perform(_:))` nie kompiluje się —
  „ambiguous use". Metoda nazywa się `runCommand(_:)`.
- **Renderowanie okna, które nigdy nie było pokazane, jest niemiarodajne.** Pierwsza próba
  podglądu całego panelu przez `cacheDisplay(in:to:)` narysowała tylko zaznaczony fragment
  tekstu i pominęła przyciski — TextKit 2 rozkłada tekst leniwie, a kontrolki bez sesji
  rysowania okna nie mają się gdzie narysować. Kontrola układu została zastąpiona pomiarem
  współrzędnych, co i tak jest ostrzejszym sprawdzeniem niż oglądanie obrazka.
- **Dwie kopie aplikacji.** Po pierwszym wdrożeniu paska użytkownik nadal widział starą wersję,
  bo `./scripts/run.sh` podmienia kopię roboczą w repozytorium, a Launchpad uruchamia
  `/Applications/OneSheet.app`. To celowy podział z etapu 6 (wpis autostartu trzyma **ścieżkę**
  pakietu), ale w praktyce łatwo o pomyłkę: zmiana trafia do codziennego użytku dopiero po
  `./scripts/install.sh`.

## 7. Dług techniczny

- **Brak testu integracji paska z panelem.** Testy sprawdzają `FormatBar` w izolacji; to, że
  pasek faktycznie siedzi na górze okna i nie zasłania tekstu, było weryfikowane pomiarem
  jednorazowym, nie testem regresyjnym. Test wymagałby serwera okien, czyli bramkowania
  zmienną środowiskową, jak `PanelOpenPerfTests`.
- **Odświeżanie stanu jest liniowe względem zaznaczenia.** Przy przeciąganiu zaznaczenia przez
  bardzo długą notatkę każdy ruch myszy wywołuje przejście po atrybutach zakresu. Zbieranie
  odświeżeń tłumi to w obrębie jednego obrotu pętli, ale nie między kolejnymi ruchami.
  Na notatce 200 000 znaków nie zauważyłem problemu w pomiarach, ale to nie jest to samo co
  test pod palcem.
- **Podpowiedzi przycisków są po polsku, na sztywno**, jak reszta interfejsu. Zgodne z
  konwencją projektu (API po angielsku, interfejs po polsku), ale to miejsce, które trzeba
  będzie ruszyć, gdyby kiedykolwiek pojawiła się druga wersja językowa.

## 8. Co dalej

Plan z `WORKFLOW.md` jest zamknięty — to była zmiana po etapie 6, nie kolejny etap.
Z rzeczy, które ta zmiana zostawia na przyszłość: `FormattingState` jest teraz naturalnym
miejscem na każdy nowy odczyt formatowania, a `FormatBar` na każdy nowy przycisk — ale zanim
któryś się pojawi, warto wrócić do listy „Poza zakresem" w
[FUNKCJONALNOSCI.md](../FUNKCJONALNOSCI.md). Ta aplikacja wygrywa prostotą, a pasek jest
pierwszym elementem interfejsu, który kiedykolwiek do niej dołożono.
