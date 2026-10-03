# CLAUDE.md — one-sheet

Plik sterujący pracą nad projektem. Czytaj go przed każdą zmianą w kodzie.

## Czym jest ten projekt

`one-sheet` to natywna aplikacja macOS: **jedna, wieczna kartka na szybkie notatki**, żyjąca
w górnej belce systemowej. Kliknięcie ikony rozwija okno z edytorem tekstu sformatowanego.
Wszystko zapisuje się samo. Nie ma listy notatek, dat, katalogów, tagów ani wyszukiwarki.

Pełne dokumenty:
- [docs/FUNKCJONALNOSCI.md](docs/FUNKCJONALNOSCI.md) — co aplikacja robi i czego świadomie nie robi
- [docs/SPECYFIKACJA.md](docs/SPECYFIKACJA.md) — architektura, format danych, decyzje techniczne
- [docs/WORKFLOW.md](docs/WORKFLOW.md) — podział na etapy, kolejność prac, definicja ukończenia

## Środowisko

- macOS Tahoe 26.5.2, Apple Silicon (arm64)
- **Brak pełnego Xcode** — tylko Command Line Tools. `xcodebuild` nie działa i nie wolno go używać.
- Swift 6.3.3, budowanie wyłącznie przez SwiftPM
- Docelowa platforma: macOS 26.0+, wyłącznie arm64

## Komendy

```bash
swift build                    # kompilacja
./scripts/test.sh              # testy (swift-testing) — nie `swift test`, patrz niżej
./scripts/bundle.sh [debug|release]   # złożenie build.noindex/OneSheet.app + podpis ad-hoc
./scripts/run.sh [debug|release]      # bundle + zabicie starej instancji + uruchomienie
./scripts/install.sh           # bundle release + podmiana kopii w /Applications + uruchomienie
killall OneSheet               # zatrzymanie (do etapu 4 nie ma pozycji „Zakończ")
```

Podgląd logów na żywo:

```bash
/usr/bin/log stream --info --predicate 'subsystem == "com.kubam.OneSheet"'
```

Pełna ścieżka `/usr/bin/log` jest konieczna — `log` to wbudowane polecenie zsh. Flaga `--info`
też, bo wpisy poziomu `.info` nie są domyślnie wyświetlane.

**Testy uruchamiaj przez `./scripts/test.sh`, nie przez samo `swift test`.** Biblioteka
swift-testing (`@Test`, `#expect`, `@Suite`) jest częścią Command Line Tools, ale SwiftPM szuka
jej tam, gdzie kładzie ją Xcode — brakujące ścieżki dokłada skrypt i tylko wtedy, gdy
`xcode-select -p` wskazuje na Command Line Tools. Samo `swift test` skończy się błędem
`no such module 'Testing'`.

XCTest w Command Line Tools faktycznie nie ma (jest częścią Xcode) — nie pisz testów opartych
na `import XCTest`.

## Zasady nienaruszalne

1. **Dane użytkownika są święte.** Każda zmiana dotykająca zapisu/odczytu notatki musi zachować
   zapis atomowy i kopię zapasową. Nigdy nie nadpisuj pliku notatki częściowym zapisem.
   Nigdy nie kasuj pliku notatki „przy okazji" refaktoru.
2. **Zero funkcji spoza zakresu.** Jeśli pomysł nie występuje w
   [docs/FUNKCJONALNOSCI.md](docs/FUNKCJONALNOSCI.md) w sekcji „W zakresie", nie implementuj go —
   zgłoś propozycję i czekaj na decyzję. Ta aplikacja wygrywa prostotą.
3. **Natywny AppKit, nie imitacja.** Edytor to `NSTextView`. Nie zastępuj go własnym
   rysowaniem tekstu, `TextEditor` z SwiftUI ani WebView.
4. **Bez zależności zewnętrznych.** `Package.swift` ma pustą listę `dependencies`. Wszystko z SDK.
   Wyjątek wymaga wyraźnej zgody.
5. **Nie wolno instalować Xcode ani zmieniać `xcode-select`** bez pytania.
6. **Jeden etap naraz.** Pracuj zgodnie z [docs/WORKFLOW.md](docs/WORKFLOW.md), nie wyprzedzaj
   kolejnych etapów. Po zakończeniu etapu zatrzymaj się i wykonaj protokół poniżej.
7. **Nie wykonuj operacji Git.** Repozytorium prowadzi użytkownik ręcznie — żadnych
   `git add`, `git commit`, `git branch`, `git checkout` bez wyraźnego polecenia.
   Praca toczy się na gałęzi `dev`.

## Protokół zakończenia etapu

Etap uznaje się za zamknięty dopiero po wykonaniu wszystkich czterech kroków:

1. **Zbuduj i uruchom** — `swift build` bez ostrzeżeń, `swift test` zielony, aplikacja startuje.
2. **Przejdź listę kontrolną** z definicji ukończenia danego etapu w
   [docs/WORKFLOW.md](docs/WORKFLOW.md). Zaznacz, co sprawdziłeś sam, a co wymaga oczu człowieka.
3. **Napisz podsumowanie** do `docs/podsumowania/etap_N_podsumowanie.md` według
   [szablonu](docs/podsumowania/SZABLON.md). Ma mieć charakter edukacyjny — po przeczytaniu
   użytkownik ma rozumieć, *jak* to działa i *dlaczego* tak, a nie tylko *że* działa.
4. **Zgłoś w rozmowie**: co powstało, wynik testów, co wymaga ręcznej weryfikacji, co się
   zmieniło względem planu. Zaktualizuj status etapu w workflow (`⬜` → `✅`) i dopisz ewentualne
   odstępstwa do rejestru decyzji. Potem **zatrzymaj się** i czekaj na decyzję o kolejnym etapie.

## Konwencje kodu

- Swift 6, tryb ścisłej współbieżności. Cały kod UI i dostęp do stanu notatki na `@MainActor`.
  Zapis na dysk w osobnym aktorze/kolejce, ale wyzwalany z main.
- Jeden typ na plik, nazwa pliku = nazwa typu.
- Nazwy typów i API po angielsku; komentarze i dokumentacja po polsku.
- Komentarze tylko tam, gdzie wyjaśniają **dlaczego**, nie **co**. Kod ma się tłumaczyć sam.
- Bez `print` w kodzie produkcyjnym — logowanie przez `os.Logger` z subsystemem
  `com.kubam.OneSheet`.
- Bez `try!`, `as!` i wymuszonego rozpakowania poza testami. Błąd odczytu notatki obsługujemy,
  nie wywracamy nim aplikacji.

## Struktura katalogów

```
one-sheet/
├── CLAUDE.md
├── Package.swift
├── docs/
│   ├── FUNKCJONALNOSCI.md      # zakres
│   ├── SPECYFIKACJA.md         # architektura i decyzje
│   ├── WORKFLOW.md             # etapy i rejestr decyzji
│   └── podsumowania/           # raport po każdym ukończonym etapie
├── scripts/                    # test.sh, bundle.sh, run.sh, ikona
├── Resources/Info.plist        # wkładany do pakietu przez bundle.sh
├── Sources/
│   ├── OneSheet/main.swift     # punkt wejścia, kilka linii
│   └── OneSheetCore/           # cały kod aplikacji
│       ├── App/                # AppDelegate, cykl życia, konfiguracja, logowanie
│       ├── MenuBar/            # NSStatusItem, panel, pozycjonowanie
│       ├── Editor/             # NSTextView, formatowanie, skróty
│       └── Storage/            # odczyt/zapis RTFD, autozapis, backup
└── Tests/OneSheetTests/        # testy na swift-testing (jeden plik = jeden @Suite)
```

**Cała logika należy do `OneSheetCore`, nie do `OneSheet`.** Symbole targetu wykonywalnego
nie są eksportowane, więc kod umieszczony w `Sources/OneSheet/` staje się nietestowalny.
`main.swift` ma pozostać kilkulinijkowy. Publiczny jest wyłącznie `AppDelegate` — reszta
biblioteki zostaje wewnętrzna, a testy sięgają do niej przez `@testable import`.

## Jak weryfikować zmiany

Testy jednostkowe pokrywają warstwę `Storage` (serializacja, atomowość, odtwarzanie po awarii).
Reszta wymaga weryfikacji ręcznej — po każdym etapie przejdź listę kontrolną z
[docs/WORKFLOW.md](docs/WORKFLOW.md). Minimalny smoke test przed zgłoszeniem gotowości:

1. `./scripts/run.sh` — ikona pojawia się w belce
2. klik w ikonę → panel się rozwija, kursor jest w polu tekstu
3. wpisz tekst, pogrub fragment (⌘B), wklej tekst ze schowka
4. zamknij panel, ubij proces (`killall OneSheet`), uruchom ponownie
5. treść i formatowanie są nienaruszone

## Czego nie robić

- Nie dodawaj okna preferencji „na wszelki wypadek".
- Nie wprowadzaj synchronizacji iCloud, eksportu, szyfrowania, historii wersji.
- Nie zmieniaj formatu pliku notatki bez ścieżki migracji i zgody.
- Nie commituj `.build/`, `build.noindex/` ani plików z `~/Library/Application Support/OneSheet/`.
