# Etap 1 — Panel z edytorem — podsumowanie

**Data ukończenia:** 2026-08-04
**Status:** ukończony z jednym odstępstwem (zaokrąglenie rogów zostawione systemowi).
Weryfikacja ręczna przeszła w całości 2026-08-04.

## 1. Co powstało

Kliknięcie ikony w belce rozwija pod nią okno z polem tekstu i od razu stawia w nim kursor —
można pisać bez sięgania po mysz. Ponowne kliknięcie ikony albo `Esc` chowa okno. Panel da się
przesuwać i skalować, a jego rozmiar i pozycja przeżywają restart aplikacji. Treść **jeszcze nie**
przeżywa restartu — zapis na dysk to etap 2.

## 2. Nowe pliki i ich rola

| Plik | Odpowiedzialność |
|---|---|
| `Sources/OneSheetCore/MenuBar/NotePanel.swift` | okno panelu: styl, zachowanie, pokazywanie/chowanie, ramka |
| `Sources/OneSheetCore/MenuBar/PanelGeometry.swift` | czysta arytmetyka pozycji okna — jedyna testowalna część etapu |
| `Sources/OneSheetCore/Editor/EditorViewController.swift` | `NSScrollView` + `NSTextView`, konfiguracja pola tekstu, przechwycenie `Esc` |

Zmienione: `AppConfiguration` (stałe panelu i edytora), `Log` (kategorie `panel`, `editor`),
`StatusItemController` (`buttonFrameOnScreen`), `AppDelegate` (budowa i przełączanie panelu),
`Tests/OneSheetTests/main.swift` (7 nowych testów geometrii).

## 3. Jak to działa — mechanizmy

### Okno, które nie zabiera aktywności innej aplikacji

- **Problem:** aplikacja z polityką `.accessory` nie jest aktywna. Zwykłe okno pokazane przez
  taką aplikację albo nie przyjmie klawiatury, albo — jeśli wymusimy aktywację — odbierze fokus
  aplikacji, z której użytkownik właśnie kopiował tekst.
- **Rozwiązanie:** `NSPanel` ze stylem `.nonactivatingPanel`. To jedyny styl okna w AppKit, który
  może zostać oknem **kluczowym** (przyjmować klawiaturę) bez aktywowania swojej aplikacji.
  Do tego `becomesKeyOnlyIfNeeded = false`, żeby panel stawał się kluczowy od razu przy pokazaniu,
  a nie dopiero po kliknięciu w pole tekstu.
- **Dlaczego tak:** alternatywą był `NSApp.activate()` przy każdym otwarciu (plan awaryjny z sekcji
  8 specyfikacji). Kosztowałby przełączenie aktywnej aplikacji przy każdym zerknięciu w notatnik.
- **Na co uważać:** `makeKeyAndOrderFront(_:)` wywołane z nieaktywnej aplikacji potrafi nie wysunąć
  okna na wierzch. Stąd para wywołań:

```swift
orderFrontRegardless()   // wysuwa okno niezależnie od stanu aktywacji aplikacji
makeKey()                // dopiero teraz okno przejmuje klawiaturę
editorViewController.focusText()
```

Dodatkowo `canBecomeKey` jest nadpisane na `true` (bez tego panel bez tytułu bywa pomijany przy
wyborze okna kluczowego), a `canBecomeMain` na `false` — okno główne w aplikacji bez menu głównego
nie ma sensu i wpływa na rysowanie ramek innych okien.

### Panel, którego nie da się przypadkiem zgubić

Trzy ustawienia, każde odpowiada za inny sposób zniknięcia okna:

```swift
hidesOnDeactivate = false                                  // przełączenie na inną aplikację
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]  // inne biurko / pełny ekran
level = .floating                                          // przykrycie oknem innej aplikacji
```

Świadomie **nie** obsługujemy `windowDidResignKey` — to najczęstsza implementacja panelu spod
belki (tak działa `NSPopover`) i akurat tu byłaby wadą: notatnik ma móc stać otwarty obok edytora
kodu przez cały dzień. Zamknięcie to `orderOut(nil)`, nie `close()` — okno powstaje raz przy
starcie aplikacji i tylko znika z ekranu, więc otwarcie kosztuje tyle, co narysowanie klatki.

### Wygląd bez paska tytułu, ale ze skalowaniem

- **Problem:** panel ma wyglądać jak kartka — bez tytułu, bez kropek sterujących — ale wciąż być
  skalowalny i przesuwalny.
- **Rozwiązanie:** styl `.titled` (pasek tytułu istnieje) + `.fullSizeContentView` (zawartość
  sięga pod pasek) + `titlebarAppearsTransparent` i `titleVisibility = .hidden` (pasek jest
  niewidoczny) + ukryte `standardWindowButton(...)`. Pasek dalej łapie przeciąganie, krawędzie
  dalej łapią skalowanie, ale nic z tego nie widać.
- **Dlaczego tak:** okno `.borderless` traci skalowanie i przeciąganie — trzeba by je pisać ręcznie
  z `mouseDragged`. `isMovableByWindowBackground = true` kolidowałoby z zaznaczaniem tekstu:
  przeciągnięcie po tekście przesuwałoby okno zamiast zaznaczać.
- **Na co uważać:** niewidoczny pasek tytułu **nadal przechwytuje kliknięcia**. Gdyby pole tekstu
  sięgało samej góry okna, jego pierwsze 28 pt byłoby martwe — kliknięcie tam przeciągałoby okno,
  a nie stawiało kursor. Dlatego edytor jest przypięty 28 pt poniżej górnej krawędzi
  (`AppConfiguration.Panel.dragStripHeight`), a rozmycie tła wypełnia całość.

Tło to `NSVisualEffectView` z materiałem `.popover` i `blendingMode = .behindWindow` — rozmywa to,
co jest **pod** oknem. Wariant `.withinWindow` rozmywałby własną zawartość panelu, czyli tekst
notatki. `state = .active` wymusza pełne rozmycie także wtedy, gdy aplikacja jest nieaktywna —
a nasza jest nieaktywna praktycznie zawsze.

### `Esc` — dlaczego `cancelOperation` w oknie to za mało

- **Problem:** `Esc` miał chować panel, a nie robił nic.
- **Przyczyna:** `NSTextView` konsumuje `Esc` — w standardowych powiązaniach klawiszy jest on
  podpięty pod podpowiadanie słów (`complete:`, to samo, co robi `Esc` w TextEdit). Zdarzenie nigdy
  nie dochodzi do okna, więc nadpisany `cancelOperation(_:)` w `NotePanel` się nie uruchamia.
- **Rozwiązanie:** przechwycenie na poziomie delegata pola tekstu, który dostaje polecenie
  **przed** domyślną implementacją:

```swift
func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    let isCancel = commandSelector == #selector(NSResponder.cancelOperation(_:))
        || commandSelector == #selector(NSStandardKeyBindingResponding.complete(_:))
    guard isCancel else { return false }
    onCancel?()
    return true   // `true` = polecenie obsłużone, nie przekazuj dalej
}
```

Nadpisanie `cancelOperation(_:)` w `NotePanel` zostało jako druga ścieżka — na wypadek, gdyby
pierwszym responderem nie było pole tekstu.

- **Na co uważać:** zwrócenie `false` z tej metody oddaje polecenie domyślnej implementacji.
  Łatwo tu przypadkiem połknąć strzałki albo `Enter`, więc warunek musi być wąski.

### Pozycja okna: co liczymy sami, a co robi za nas AppKit

Rozmiar i pozycja są zapamiętywane przez AppKit pod nazwą `NotePanel`
(klucz `NSWindow Frame NotePanel` w `UserDefaults`). Pułapka: `setFrameAutosaveName(_:)` włącza
tylko **zapisywanie**. Odtworzenie trzeba wywołać ręcznie — automatycznie dzieje się to wyłącznie
dla okien wczytanych z NIB-a, których tu nie ma:

```swift
guard setFrameAutosaveName(AppConfiguration.Panel.frameAutosaveName) else { ... }
hasResolvedFrame = setFrameUsingName(AppConfiguration.Panel.frameAutosaveName)
```

`setFrameUsingName` zwraca `false`, gdy nic nie było zapisane — i to jest sygnał „pierwsze
uruchomienie, ustaw panel pod ikoną". Przy kolejnych uruchomieniach wygrywa pozycja użytkownika.

Samo liczenie pozycji siedzi w `PanelGeometry` — bez `NSWindow` i `NSScreen`, wyłącznie arytmetyka
prostokątów. To celowe: program testowy działa bez serwera okien, więc wszystko, co dotyka
prawdziwego okna, może być sprawdzone tylko oczami. Wydzielenie geometrii przesuwa granicę tego,
co da się zweryfikować testem.

Dwie rzeczy warte zapamiętania:

1. **Układ współrzędnych AppKit ma początek w lewym dolnym rogu**, oś Y rośnie do góry. „Pod ikoną"
   znaczy więc `y = anchor.minY - odstęp - wysokość`, a nie `+`.
2. **Przycinanie do `visibleFrame` zaczyna się od rozmiaru**, dopiero potem od pozycji. Gdyby
   panel był wyższy od ekranu, ograniczenia na `origin.y` byłyby sprzeczne i dawałyby ujemne
   wyniki. Ten sam kod ratuje dwa różne przypadki: ikonę tuż przy prawej krawędzi ekranu
   (wyśrodkowany panel wystawałby poza obszar) i ramkę zapamiętaną na monitorze, który przestał
   być podłączony.

Punkt zaczepienia bierze się z przycisku w belce. `NSStatusItem.button` żyje we własnym oknie
tworzonym przez belkę systemową, więc droga do współrzędnych ekranu prowadzi przez to okno:

```swift
window.convertToScreen(button.convert(button.bounds, to: nil))
```

### Konfiguracja `NSTextView` w `NSScrollView`

`NSTextView` wstawiony ręcznie do `NSScrollView` wymaga zestawu ustawień, których nie da się
zgadnąć: `isVerticallyResizable = true`, `isHorizontallyResizable = false`,
`autoresizingMask = [.width]`, `textContainer.widthTracksTextView = true` oraz `maxSize`
o nieskończonej wysokości. Sens całości: szerokość podąża za oknem (zawijanie wierszy), wysokość
rośnie z treścią (przewijanie w pionie), poziomego przewijania nie ma wcale.

Poza tym: `drawsBackground = false` na polu tekstu **i** na `NSScrollView` — inaczej jednolita
płaszczyzna przykryłaby rozmycie tła. Kolor tekstu to `.labelColor`, kolor dynamiczny, który sam
przełącza się z motywem systemu (na sztywno wpisana czerń byłaby nieczytelna w trybie ciemnym).
Zamiana cudzysłowów na typograficzne jest wyłączona — psuje wklejany kod; sprawdzanie pisowni
i zamiana tekstu zostają, bo są w zakresie jako standardowe usługi systemowe.

## 4. Decyzje i odstępstwa od planu

### Odstępstwo: zaokrąglenie rogów zostawione systemowi

Specyfikacja (sekcja 3.2) mówi o zaokrągleniu 12 pt na `NSVisualEffectView`. Nie ustawiam
`layer.cornerRadius`: okno ze stylem `.titled` jest już przycinane do kształtu okna przez system,
a macOS 26 ma własny, większy promień. Ręczne 12 pt obcinałoby zawartość **wewnątrz** i tak
zaokrąglonego okna, co daje albo jasny włos przy krawędzi, albo podwójny łuk.

Wygląd obejrzany i zaakceptowany 2026-08-04 — systemowy promień jest poprawny, jawnego
`cornerRadius` nie dodajemy. Wpis w rejestrze decyzji.

Poza tym: bez odstępstw. Cały zakres z workflow zrealizowany.

## 5. Testy

**Automatyczne — 11 testów, wszystkie przechodzą** (4 z etapu 0 + 7 nowych):

- panel wyśrodkowany pod ikoną, górna krawędź o 6 pt poniżej ikony
- ikona przy prawej krawędzi ekranu — panel dosunięty do krawędzi, rozmiar bez zmian
- ikona przy lewej krawędzi — to samo z drugiej strony
- brak ikony (awaryjnie) — panel pod górną krawędzią obszaru roboczego
- panel wyższy niż ekran — zmniejszony do wysokości obszaru roboczego
- ramka zapamiętana poza ekranem — wsunięta w obszar roboczy
- ramka mieszcząca się na ekranie — nietknięta

**Sprawdzone przeze mnie na osobnym stanowisku testowym** (jednorazowy program poza repozytorium,
tworzący prawdziwy panel i wysyłający zdarzenia klawiatury wewnątrz własnego procesu — bez
uprawnień Accessibility; stanowisko po użyciu skasowane wraz z wpisami, które zdążyło zapisać
w `UserDefaults`):

- panel po `present(...)` jest widoczny i jest oknem kluczowym mimo `.accessory` i braku aktywacji
- pierwszym responderem jest `NSTextView` — kursor jest w tekście bez klikania
- ramka mieści się w `visibleFrame` przy ikonie tuż przy prawej krawędzi monitora 3440×1440
- widok edytora ma niezerowy rozmiar i zaczyna się dokładnie 28 pt poniżej górnej krawędzi
- syntetyczne zdarzenia klawiatury trafiają do pola tekstu (wpisane znaki są w `string`)
- `Esc` chowa panel, ponowne otwarcie działa, treść przeżywa schowanie

Dodatkowo: `swift build` od zera bez ostrzeżeń, `./scripts/run.sh` uruchamia aplikację, w logu
pojawia się utworzenie ikony.

**Zweryfikowane ręcznie przez użytkownika — 2026-08-04, wszystko przeszło:**

1. ✅ Klik w ikonę → panel rozwija się pod nią, kursor miga w tekście, **pisanie działa bez
   klikania w pole**. To było główne ryzyko etapu: routing klawiatury do panelu nieaktywującego
   działa, plan awaryjny z `NSApp.activate()` jest niepotrzebny.
2. ✅ Wygląd: rozmycie tła, rogi okna, brak paska tytułu i kropek sterujących, jasny i ciemny motyw.
3. ✅ Przeciąganie za górne 28 pt i skalowanie za krawędź; po `killall OneSheet` i ponownym
   uruchomieniu rozmiar i pozycja wracają.
4. ✅ Panel zostaje widoczny po kliknięciu w inną aplikację, `⌘Tab`, przejściu na inne biurko
   i przy pełnym ekranie innej aplikacji.
5. ✅ `Esc` chowa panel, klik w ikonę otwiera i chowa.

## 6. Napotkane problemy

**`Esc` nie działał z poziomu okna.** Nadpisany `cancelOperation(_:)` w `NotePanel` nie był
wywoływany, bo `NSTextView` konsumuje `Esc` na podpowiadanie słów. Rozwiązane przechwyceniem
w `textView(_:doCommandBy:)` — opisane wyżej. Wykryte przy pisaniu kodu, nie po fakcie:
gdyby nie to, `Esc` byłby martwy i wyszłoby to dopiero przy ręcznym teście.

**`NSSize(width: .greatestFiniteMagnitude, ...)` nie kompiluje się** — kompilator nie umie wybrać
między `CGFloat.greatestFiniteMagnitude` a `Double.greatestFiniteMagnitude`. Konieczne jawne
`CGFloat.`.

**Odtwarzanie ramki okna.** Pierwsza wersja polegała na samym `setFrameAutosaveName(_:)` i panel
zawsze otwierał się pod ikoną, ignorując zapamiętaną pozycję. Brakowało `setFrameUsingName(_:)`.

## 7. Dług techniczny

- **Treść żyje tylko w pamięci.** `NSTextStorage` nie jest z niczym związany, `killall` kasuje
  wszystko. To nie jest przeoczenie, tylko zakres etapu 2 — ale do tego czasu aplikacja jest
  demonstracją, nie notatnikiem.
- **`EditorViewController` nie jest `contentViewController` panelu.** Widok jest wstawiany ręcznie
  jako podwidok tła, więc kontroler nie trafia do łańcucha responderów i nie dostaje
  `viewDidAppear()`. Nie przeszkadza (etap 3 używa lokalnego monitora zdarzeń, nie akcji z menu),
  ale gdyby kiedyś przeszkodziło, poprawką jest kontroler-kontener, którego widokiem jest
  `NSVisualEffectView`.

## 8. Co dalej

Etap 2 podpina `NoteStore` pod `NSTextView`: `textDidChange` uruchamia debounce, `flush()` zapisuje
synchronicznie. Z tego etapu wynika jedna rzecz istotna dla następnego — panel może być otwarty
tygodniami, więc jego schowanie nie jest wiarygodnym momentem zapisu. Ciężar spada na debounce
i na `flush()` przy utracie aktywności, uśpieniu i zakończeniu aplikacji. `EditorViewController`
już jest delegatem `NSTextView`, więc `textDidChange(_:)` ma gdzie trafić.
