# Dodatek — chowanie po kliknięciu poza notatką — podsumowanie

**Data ukończenia:** 2026-10-03
**Status:** ukończony, zweryfikowany przez użytkownika 2026-10-03

## 1. Co powstało

W menu prawego przycisku ikony pojawił się drugi przełącznik: „Chowaj po kliknięciu poza
notatką". Domyślnie jest wyłączony i wtedy aplikacja zachowuje się jak dotąd: panel stoi otwarty,
dopóki nie klikniesz ikony, nie naciśniesz `Esc` albo `⌥⌘N`. Po włączeniu panel chowa się także
po kliknięciu myszą gdziekolwiek poza nim, jak menu systemowe.

## 2. Nowe pliki i ich rola

| Plik | Odpowiedzialność |
|---|---|
| `Sources/OneSheetCore/MenuBar/OutsideClickMonitor.swift` | instaluje i zdejmuje globalny monitor kliknięć myszą |
| `Tests/OneSheetTests/OutsideClickMonitorTests.swift` | cykl życia monitora (start/stop, idempotentność) |

Zmienione: `AppConfiguration` (klucz `hidesOnClickOutside`), `NotePanel` (callback `onPresent`),
`StatusItemMenu` (nowa pozycja), `AppDelegate` (połączenie wszystkiego), `StatusItemMenuTests`.

## 3. Jak to działa — mechanizmy

### Monitor globalny, a nie lokalny

- **Problem:** dowiedzieć się, że użytkownik kliknął *poza* naszym panelem, także w zupełnie
  inną aplikację.
- **Rozwiązanie:** `NSEvent.addGlobalMonitorForEvents(matching:handler:)` z maską
  `[.leftMouseDown, .rightMouseDown, .otherMouseDown]`. AppKit ma dwa rodzaje monitorów:
  - **lokalny** (`addLocalMonitorForEvents`) widzi zdarzenia trafiające do *naszej* aplikacji
    i może je zmienić albo połknąć,
  - **globalny** widzi zdarzenia trafiające do *innych* procesów i może je tylko obejrzeć.

  Potrzebujemy dokładnie tego drugiego: każde zdarzenie, które dociera do monitora globalnego,
  jest z definicji kliknięciem poza naszą aplikacją. Nie trzeba niczego liczyć ani porównywać
  współrzędnych z ramką panelu.
- **Dlaczego tak:** alternatywą było `windowDidResignKey` (panel traci status okna kluczowego,
  więc ktoś kliknął obok). Nasz panel jest jednak `.nonactivatingPanel`: aplikacja *nie staje się
  aktywna*, kiedy w nim piszesz. Status okna kluczowego zachowuje się wtedy nieprzewidywalnie
  i nie jest wiarygodnym sygnałem kliknięcia obok. To samo zastrzeżenie od etapu 1 stoi
  w specyfikacji.

### Dlaczego klik we własną ikonę nie chowa panelu dwa razy

Ikona w belce (`NSStatusItem.button`) żyje w oknie, które należy do **naszego** procesu. Kliknięcie
w nią jest więc zdarzeniem lokalnym i monitor globalny go nie dostaje. Dostaje je tylko
`StatusItemController.handleClick`, który robi swój zwykły `toggle`. Gdyby monitor też je widział,
najpierw schowałby panel, a zaraz potem `toggle` otworzyłby go z powrotem: panel by tylko mrugnął.
Ten punkt jest na liście kontrolnej do sprawdzenia ręcznie, bo test jednostkowy go nie wykryje.

### Uprawnienia — gdzie przebiega granica

Monitor globalny dla **klawiatury** wymaga zgody Accessibility. Inaczej każda aplikacja mogłaby
podsłuchiwać hasła wpisywane gdzie indziej. Ruchy i kliknięcia myszą tej zgody nie wymagają.
Dlatego w etapie 4 skrót globalny musiał iść przez Carbon `RegisterEventHotKey`, a tutaj monitor
NSEvent wystarcza. Zdanie w specyfikacji zostało doprecyzowane, bo wcześniej sugerowało, że całe
`addGlobalMonitorForEvents` wymaga Accessibility.

### Monitor żyje tylko przy otwartym panelu

```swift
panel.onPresent = { [weak self] in
    guard let self, hidesOnClickOutside else { return }
    outsideClickMonitor.start()
}
panel.onHide = { [weak self] in
    self?.noteStore.flush()
    self?.outsideClickMonitor.stop()
}
```

Każda droga schowania (ikona, `Esc`, skrót, klik obok) przechodzi przez `NotePanel.hide()`,
a więc i przez `onHide`. Dlatego wystarcza jedno miejsce zdejmowania. Przy schowanym panelu żadne
kliknięcie w systemie nie budzi aplikacji. `NotePanel` nic nie wie o preferencji: ogłasza tylko
„pokazałem się", a decyzję podejmuje `AppDelegate`.

- **Na co uważać:** `start()` jest idempotentne celowo. Dwa zainstalowane monitory oznaczałyby
  dwa wywołania `hide()` na jedno kliknięcie. Handler monitora przychodzi na głównym wątku, ale
  jego sygnatura tego nie gwarantuje, więc w Swift 6 trzeba `MainActor.assumeIsolated`.

### Zapis notatki

Bez zmian. Schowanie przez kliknięcie obok to zwykłe `hide()`, więc `onHide` robi `flush()` tak
samo jak przy `Esc`.

## 4. Decyzje i odstępstwa od planu

- **Zmiana zakresu** — FUNKCJONALNOSCI sekcja 2 mówiła, że panel zamykają *wyłącznie* trzy akcje.
  Wpis w rejestrze decyzji z 2026-10-03.
- Przełącznik żyje w menu ikony, a nie w oknie ustawień. „Okno preferencji, panel ustawień"
  zostaje na liście rzeczy trwale poza zakresem.
- Chowa wyłącznie kliknięcie myszą. `⌘Tab`, zmiana biurka i Mission Control nie chowają
  (ustalone z użytkownikiem).
- Z planu: krok 0 („szybki test na żywo z tymczasowym monitorem") połączyłem z właściwą
  implementacją, bo tymczasowy monitor byłby tym samym kodem. Jego punkty (brak monitu
  Accessibility, brak podwójnego `toggle`) są teraz na liście kontrolnej do weryfikacji ręcznej.

## 5. Testy

- **Automatyczne:** 81 testów w 13 zestawach, wszystkie zielone. Nowe:
  `OutsideClickMonitorTests` (2) oraz w `StatusItemMenuTests` pozycja menu, jej cel i akcja,
  ptaszek dla obu stanów.
- **Sprawdzone przeze mnie:** kompilacja, start aplikacji z pakietu, wpisy w logu przy starcie.
- **Przed weryfikacją:** `./scripts/install.sh`. Autostart i Finder uruchamiają kopię
  z `/Applications`, a `./scripts/run.sh` jej nie podmienia — pierwsza próba weryfikacji
  trafiła właśnie na starą kopię z 2026-08-05, w której przełącznika jeszcze nie było.
- **Zweryfikowane przez użytkownika (2026-10-03):** wszystkie punkty ręczne z listy — brak
  monitu Accessibility, chowanie po kliknięciu obok, brak podwójnego `toggle` przy kliknięciu
  ikony, natychmiastowe przełączanie, trwałość ustawienia i zapis notatki.
- **Lista kontrolna:** cała lista z [WORKFLOW.md](../WORKFLOW.md), sekcja
  „Chowanie po kliknięciu poza notatką". Kliknięć w inne aplikacje nie da się zasymulować
  w teście: zdarzenia syntetyczne trafiają do naszego procesu, a monitor globalny ich nie widzi.

## 6. Napotkane problemy

Brak w kodzie. Przy budowaniu linker zgłasza `ld: warning: search path
'/Library/Developer/CommandLineTools/Developer/...' not found`. Tych ścieżek nie dodaje ani
`Package.swift`, ani kod projektu (ta zmiana nie dotyka ustawień linkera), tylko toolchain
Command Line Tools. Nie badałem, czy ostrzeżenie występowało przed tą zmianą.

## 7. Dług techniczny

Brak.

## 8. Co dalej

Zmiana zamknięta. Przy okazji przeniesiono roboczy pakiet do `build.noindex/` — Spotlight
pokazywał dwie kopie aplikacji (rejestr decyzji, 2026-10-03).
