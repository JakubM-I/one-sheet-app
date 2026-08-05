# Etap 4 — Integracja z systemem — podsumowanie

**Data ukończenia:** 2026-08-05
**Status:** ukończony (czeka na weryfikację ręczną)

## 1. Co powstało

Aplikacja przestała być „okienkiem na żądanie kliknięcia" i stała się stałym elementem
systemu: panel otwiera i zamyka globalny skrót `⌥⌘N` z dowolnej aplikacji, prawy przycisk
na ikonie w belce pokazuje menu z przełącznikiem „Uruchamiaj przy logowaniu" i pozycją
„Zakończ", a przy pierwszym uruchomieniu aplikacja sama rejestruje się jako element
logowania. Pakiet dostał też ikonę (roboczą — finalna powstaje w etapie 6).

## 2. Nowe pliki i ich rola

| Plik | Odpowiedzialność |
|---|---|
| `Sources/OneSheetCore/MenuBar/HotKeyRegistering.swift` | protokół rejestracji skrótu — oddziela `AppDelegate` od Carbon |
| `Sources/OneSheetCore/MenuBar/GlobalHotKey.swift` | implementacja przez `RegisterEventHotKey` z HIToolbox |
| `Sources/OneSheetCore/App/LaunchAtLogin.swift` | autostart przez `SMAppService.mainApp`, łącznie z domyślnym włączeniem przy pierwszym starcie |
| `Sources/OneSheetCore/MenuBar/StatusItemMenu.swift` | budowa menu kontekstowego ikony z czystego modelu (testowalna bez belki) |
| `scripts/make_icon.swift` | generator `AppIcon.icns`: rysowanie w AppKit + złożenie przez `iconutil` |
| `scripts/AppIcon.icns` | ikona aplikacji (Finder, Elementy logowania) |
| `Tests/OneSheetTests/StatusItemMenuTests.swift` | zgodność pozycji menu z modelem |
| `Tests/OneSheetTests/GlobalHotKeyTests.swift` | rejestracja/wyrejestrowanie skrótu w procesie testowym |

Zmienione: `AppConfiguration` (stałe skrótu i klucze `UserDefaults`), `AppDelegate`
(spięcie całości), `StatusItemController` (pokazywanie menu), `scripts/bundle.sh`
(`--options runtime` przy podpisie).

## 3. Jak to działa — mechanizmy

### Globalny skrót bez uprawnień — Carbon `RegisterEventHotKey`

- **Problem:** `⌥⌘N` ma działać, gdy aplikacja jest w tle i nie jest aktywna — czyli
  zdarzenie klawiatury w ogóle do niej nie trafia.
- **Rozwiązanie:** `RegisterEventHotKey` z HIToolbox rejestruje kombinację w systemowym
  dyspozytorze zdarzeń. System sam wykrywa naciśnięcie (niezależnie od aktywnej aplikacji)
  i dostarcza zdarzenie `kEventHotKeyPressed` do naszego procesu, gdzie odbiera je uchwyt
  zainstalowany przez `InstallEventHandler(GetEventDispatcherTarget(), ...)`.
- **Dlaczego tak:** jedyna alternatywa w AppKit — `NSEvent.addGlobalMonitorForEvents` —
  wymaga uprawnień Accessibility (okno z prośbą przy pierwszym starcie) i tylko *podgląda*
  zdarzenia: inne aplikacje też dostałyby `⌥⌘N`. Carbon konsumuje naciśnięcie i nie pyta
  o nic. API jest stare, ale wciąż wspierane na macOS 26 — korzysta z niego praktycznie
  każdy launcher i menedżer schowka.
- **Na co uważać — trzy rzeczy:**
  1. Uchwyt zdarzeń to funkcja C: bez domknięć, bez `self`. Kontekst przechodzi przez
     surowy wskaźnik `userData` (`Unmanaged.passUnretained`), więc obiekt **musi** żyć
     dłużej niż rejestracja — stąd kontrakt „wyrejestruj, zanim zwolnisz" zapisany
     w protokole. Swift 6 dodatkowo nie przepuści surowego wskaźnika do domknięcia
     `@MainActor` (nie jest `Sendable`) — do środka wchodzi jako `UInt(bitPattern:)`.
  2. Carbon dostarcza zdarzenia w pętli zdarzeń wątku głównego, ale kompilator o tym nie
     wie. `MainActor.assumeIsolated` dokumentuje to założenie i — gdyby kiedyś przestało
     obowiązywać — zakończy proces trapem zamiast cichego wyścigu danych.
  3. Uchwyt dostaje **wszystkie** zdarzenia hot-key procesu, nie tylko „swoje". Każda
     instancja `GlobalHotKey` ma więc własny identyfikator (`EventHotKeyID.id`)
     i sprawdza go, zanim wywoła akcję — inaczej aplikacja i testy w jednym procesie
     wywoływałyby nawzajem swoje callbacki.

Maski modyfikatorów Carbon (`optionKey`, `cmdKey`) to **inne stałe** niż
`NSEvent.ModifierFlags` — pomieszanie ich kompiluje się bez słowa i rejestruje zły skrót.

### Pomiar: „skrót zajęty" nie istnieje między aplikacjami

Specyfikacja (sekcja 8) zakładała ryzyko „skrót zajęty przez inną aplikację → błąd
rejestracji → komunikat w menu". Stanowisko testowe (drugi proces rejestrujący `⌥⌘N`,
gdy OneSheet już go trzyma) pokazało, że `RegisterEventHotKey` zwraca wtedy `noErr` —
system dopuszcza duplikaty między procesami i sam rozstrzyga, komu doręczyć naciśnięcie.
Błąd `eventHotKeyExistsErr` (-9878) dotyczy wyłącznie duplikatu **w obrębie jednego
procesu**. Obsługa błędu rejestracji zostaje w kodzie (awaria samego API, dziwne stany
systemu), ale komunikat „Skrót ⌥⌘N niedostępny" w praktyce nie powinien się nigdy pokazać.
Sprostowanie trafiło do rejestru decyzji i do tabeli ryzyk w specyfikacji.

### Autostart — `SMAppService.mainApp`

- **Problem:** ikona ma być w belce po zalogowaniu, bez ręcznego uruchamiania, ale
  z uczciwym przełącznikiem dla użytkownika.
- **Rozwiązanie:** `try SMAppService.mainApp.register()` / `.unregister()`. Stan
  przełącznika w menu czytamy **za każdym razem** z `SMAppService.mainApp.status`,
  nie z własnej flagi — użytkownik może zmienić stan w Ustawieniach systemowych
  → Elementy logowania za plecami aplikacji i ptaszek ma tego nie przekłamywać.
  Flaga `launchAtLogin` w `UserDefaults` odnotowuje tylko, że pierwsze uruchomienie
  już włączyło autostart; bez niej każdy start cofałby ręczne wyłączenie.
- **Dlaczego tak:** starsze drogi (`LSSharedFileList`, `SMLoginItemSetEnabled` z osobnym
  helperem) są przestarzałe albo wymagają drugiego targetu. `SMAppService.mainApp`
  istnieje dokładnie po to: aplikacja rejestruje samą siebie, a system pokazuje ją
  w Ustawieniach z prawidłową nazwą i możliwością wyłączenia.
- **Na co uważać:** `register()` działa tylko dla podpisanej binarki uruchomionej
  z pakietu `.app` — dla procesu spod `swift run` rzuca błędem. To spodziewana ścieżka:
  błąd idzie do logu i jako wyszarzona linia do menu, aplikacja żyje dalej. Ryzyko
  „`SMAppService` odrzuca podpis ad-hoc" **nie zmaterializowało się**: rejestracja
  z podpisem ad-hoc przechodzi i kończy się statusem `.enabled`. Status
  `.requiresApproval` traktujemy przy przełączaniu jak „włączone" — rejestracja już
  nastąpiła, więc następna akcja użytkownika ma ją wycofać, nie ponowić.

### Menu kontekstowe ikony bez utraty lewego kliknięcia

- **Problem:** `NSStatusItem` z ustawionym `menu` pokazuje je przy **każdym** kliknięciu —
  lewy przycisk przestałby otwierać panel.
- **Rozwiązanie:** menu jest podpinane tylko na czas pokazania: `statusItem.menu = menu`,
  `button.performClick(nil)` (rozwija synchronicznie), `statusItem.menu = nil`. Lewy
  przycisk dalej trafia w akcję przycisku, prawy dostaje pełne menu z systemowym
  zachowaniem klawiatury i pozycjonowaniem.
- **Dlaczego tak:** ręczne `NSMenu.popUp(positioning:at:in:)` też działa, ale wymaga
  liczenia pozycji i nie podświetla ikony na czas otwarcia. Trik z chwilowym `menu` to
  utarty wzorzec dla ikon rozróżniających przyciski.
- **Na co uważać:** menu budujemy od nowa przy każdym otwarciu — stan autostartu mógł
  się zmienić poza aplikacją. Pozycja „Zakończ" nie ma celu (`target = nil`): akcja
  `terminate(_:)` idzie łańcuchem responderów do `NSApplication`, a zapis notatki
  gwarantuje istniejący `applicationWillTerminate` → `flush()`. Pozycje informacyjne
  (komunikaty o błędach) nie mają akcji, więc `autoenablesItems` trzyma je wyszarzone.

### Ikona bez Xcode i bez grafika

`AppIcon.icns` powstaje ze skryptu `swift scripts/make_icon.swift`: rysowanie kartki
z liniami w `NSBitmapImageRep` (10 rozmiarów od 16 do 1024 px), zapis do katalogu
`AppIcon.iconset`, złożenie przez `/usr/bin/iconutil -c icns` — narzędzie systemowe,
nie Xcode'owe. Finalna ikona (etap 6) może podmienić plik bez zmiany procesu pakowania.
`CFBundleIconFile = AppIcon` siedział w `Info.plist` od etapu 0, więc wystarczyło
dostarczyć plik.

### Podpis z hardened runtime

`bundle.sh` podpisuje teraz z `--options runtime`, zgodnie ze specyfikacją (sekcja 5).
Dla aplikacji korzystającej wyłącznie z bibliotek systemowych hardened runtime niczego
nie ogranicza, a podpis (nawet ad-hoc) jest warunkiem działania `SMAppService`.

## 4. Decyzje i odstępstwa od planu

- Sprostowanie ryzyka „skrót zajęty" — patrz pomiar wyżej i rejestr decyzji.
- Ikona generowana skryptem zamiast dostarczona jako grafika — rejestr decyzji.
- Poza tym zakres zgodny z workflow i specyfikacją.

## 5. Testy

- **Automatyczne:** 49 testów przechodzi (`./scripts/test.sh`), w tym 6 nowych:
  zgodność menu kontekstowego z modelem (pozycje, ptaszek, komunikaty, brak celu
  pozycji „Zakończ") oraz rejestracja skrótu (rejestracja + wyrejestrowanie
  + ponowna rejestracja, idempotencja, unikalność identyfikatorów). Testy skrótu
  używają kombinacji `⌃⌥⇧⌘F13`, żeby nie kolidować z działającą aplikacją.
- **Sprawdzone przeze mnie:**
  - `swift build` od zera bez ostrzeżeń;
  - aplikacja startuje z pakietu, wczytuje istniejącą notatkę (227 znaków — dane
    użytkownika nietknięte);
  - log potwierdza rejestrację `⌥⌘N` bez żadnego okna z prośbą o uprawnienia;
  - pierwsze uruchomienie: `SMAppService.mainApp.status == .enabled`, flaga
    `launchAtLogin = 1` w `UserDefaults`;
  - aplikacja przeżywa start przy zajętym `⌥⌘N` (stanowisko z drugim procesem);
  - `iconutil` składa poprawny `.icns`, pakiet podpisuje się z `--options runtime`.
- **Wymaga weryfikacji przez Ciebie:**
  - `⌥⌘N` z innej aplikacji faktycznie otwiera i chowa panel (kursor od razu w tekście);
  - prawy przycisk na ikonie: menu wygląda sensownie, ptaszek zgadza się ze stanem
    w Ustawieniach systemowych, przełączenie działa w obie strony;
  - „Zakończ" kończy aplikację, a treść wpisana tuż przed jest po ponownym starcie;
  - OneSheet widnieje w Ustawieniach systemowych → Ogólne → Elementy logowania;
  - po restarcie Maca ikona pojawia się w belce sama;
  - wygląd roboczej ikony w Finderze/Elementach logowania (ocena estetyczna).

## 6. Napotkane problemy

- **Swift 6 vs. wywołanie zwrotne C:** kompilator odrzucił przekazanie `userData`
  (surowego wskaźnika) do domknięcia `MainActor.assumeIsolated` — wskaźniki nie są
  `Sendable`. Rozwiązanie: wskaźnik wchodzi do domknięcia jako `UInt(bitPattern:)`
  i jest odtwarzany w środku. Izolacji to nie psuje — wskaźnik pochodzi z tego samego
  wątku, na którym domknięcie zaraz się wykona.
- **Fałszywie „udany" test negatywny:** pierwsze stanowisko do testu zajętego skrótu
  odpalało skrypt przez `swift plik.swift` w tle — interpreter kompilował się dłużej
  niż trwał cały test, więc skrót nigdy nie był zajęty, a wynik wyglądał na sukces
  aplikacji. Po skompilowaniu pomocnika `swiftc` i potwierdzeniu jego rejestracji
  wyszedł prawdziwy wynik: duplikaty między procesami są legalne (pomiar w sekcji 3).

## 7. Dług techniczny

- Element logowania wskazuje na `OneSheet.app` w katalogu repozytorium — po instalacji
  do `/Applications` (etap 6) trzeba będzie przełączyć autostart, żeby wskazywał
  właściwą kopię.
- Ikona jest robocza; finalna powstaje w etapie 6 (`make_icon.swift` można wtedy
  rozbudować albo podmienić sam plik).
- Flaga `hotKeyEnabled` w `UserDefaults` jest honorowana, ale nie ma interfejsu do jej
  zmiany — zgodnie ze specyfikacją (sekcja 3.5) i zakresem; zostaje jako furtka.

## 8. Co dalej

Etap 5 (hardening) nie dokłada funkcji — mierzy i uszczelnia: notatki 50 000 i 200 000
znaków, czas otwarcia panelu (<150 ms), przegląd ścieżek błędów `NoteStore`, dwa
monitory, Spaces i tryb pełnoekranowy, sprzątanie martwego kodu. Z tego etapu wpływa
na niego jedno: globalny skrót to teraz główna droga otwierania panelu, więc pomiar
czasu otwarcia powinien mierzyć ścieżkę od `⌥⌘N`, nie tylko od kliknięcia.
