# Etap 6 — Wykończenie i instalacja — podsumowanie

**Data ukończenia:** 2026-08-05
**Status:** ukończony z odstępstwami (rozszerzenie zakresu o naprawę rejestracji autostartu)

## 1. Co powstało

Aplikacja mieszka teraz w `/Applications` jak każda inna: `./scripts/install.sh` buduje
wydanie, podmienia zainstalowaną kopię i uruchamia ją, a autostart po instalacji wskazuje
właściwą kopię — nie build roboczy z repozytorium. Do tego finalna ikona wypełniająca
siatkę ikon macOS oraz `README.md` z instrukcją instalacji, skrótami i opisem kopii
zapasowej. To był ostatni etap planu.

## 2. Nowe pliki i ich rola

| Plik | Odpowiedzialność |
|---|---|
| `scripts/install.sh` | build release → zatrzymanie instancji → podmiana `/Applications/OneSheet.app` → uruchomienie |
| `README.md` | dokument wejściowy: instalacja, użycie, skróty, gdzie leżą dane, kopia zapasowa |
| `Tests/OneSheetTests/LaunchAtLoginTests.swift` | 6 testów decyzji „czy ponowić rejestrację autostartu po przeprowadzce" |

Zmienione: `LaunchAtLogin` (mechanizm naprawy rejestracji), `AppConfiguration` (klucz
`registeredBundlePath`), `AppDelegate` (wywołanie `reconcileOnLaunch()` zamiast
`enableOnFirstLaunch()`), `scripts/make_icon.swift` (finalny rysunek ikony).

## 3. Jak to działa — mechanizmy

### Autostart po przeniesieniu pakietu

- **Problem:** wpis „uruchamiaj przy logowaniu" siedzi w systemowej bazie Background Task
  Management i trzyma **ścieżkę** pakietu (widać ją w `sfltool dumpbtm`, pole URL). Etap 4
  zarejestrował autostart dla kopii w repozytorium — po skopiowaniu aplikacji do
  `/Applications` logowanie nadal uruchamiałoby starą kopię, nadpisywaną przy każdym buildzie.
- **Rozwiązanie:** `LaunchAtLogin` zapamiętuje w `UserDefaults` (klucz `registeredBundlePath`)
  ścieżkę, z której ostatnio udała się rejestracja. Przy każdym starcie
  `reconcileOnLaunch()` porównuje ją z `Bundle.main.bundlePath`; rozjazd oznacza
  przeprowadzkę i wyzwala ponowną `SMAppService.mainApp.register()`, która aktualizuje
  wpis w bazie.
- **Dlaczego tak:** dwie oczywistsze drogi odpadły po pomiarach na żywym systemie.
  Po pierwsze, `SMAppService.mainApp.status` **nie wykrywa** przeprowadzki — z nowej
  lokalizacji dalej zwraca `.enabled`, bo dopasowuje po identyfikatorze pakietu, nie po
  ścieżce. Po drugie, nie trzeba niczego wyrejestrowywać ani sprzątać: ponowna `register()`
  z nowej ścieżki aktualizuje istniejący wpis **w miejscu** — ten sam UUID, nowy URL,
  pole `Generation` rośnie z 1 na 2. Duplikat nie powstaje.
- **Na co uważać:** dwa warunki brzegowe są równie ważne jak sam mechanizm. Naprawa działa
  tylko dla kopii w `/Applications` — inaczej uruchomienie builda roboczego przez
  `scripts/run.sh` „kradłoby" autostart świeżo zainstalowanej aplikacji. I tylko przy
  statusie `.enabled` — jeśli użytkownik wyłączył autostart w Ustawieniach systemowych,
  przeprowadzka nie może go włączyć z powrotem. Sama decyzja jest czystą funkcją
  `shouldRepairRegistration(intentEnabled:systemEnabled:registeredPath:currentPath:)`,
  więc wszystkie warianty pokrywają testy bez dotykania prawdziwej bazy login items.

```swift
nonisolated static func shouldRepairRegistration(
    intentEnabled: Bool, systemEnabled: Bool,
    registeredPath: String?, currentPath: String
) -> Bool {
    guard intentEnabled, systemEnabled else { return false }
    guard currentPath.hasPrefix("/Applications/") else { return false }
    return registeredPath != currentPath
}
```

Brak zapamiętanej ścieżki (instalacja sprzed tego mechanizmu) liczy się jako przeprowadzka —
dokładnie ten wariant naprawił istniejącą rejestrację przy pierwszym uruchomieniu z
`/Applications`.

### Finalna ikona — superelipsa Apple bez Xcode

- **Problem:** wersja robocza z etapu 4 rysowała małą kartkę z cieniem na przezroczystym
  tle. macOS 26 oczekuje ikon wypełniających siatkę (zaokrąglony kwadrat 824/1024 płótna);
  wszystko inne wygląda obco obok systemowych aplikacji.
- **Rozwiązanie:** przepisany `scripts/make_icon.swift`. Kartka wypełnia całą siatkę,
  a jej kształt pochodzi z `SwiftUI.RoundedRectangle(cornerRadius:style:.continuous)
  .path(in:)`, zamienionego na `NSBezierPath(cgPath:)` do rysowania w AppKit.
- **Dlaczego tak:** maska ikon macOS to nie zwykły zaokrąglony prostokąt, tylko superelipsa
  („continuous corners") — łuk przechodzi w prostą bez skoku krzywizny. Jedyne publiczne
  API oddające ten kształt to właśnie SwiftUI; `NSBezierPath(roundedRect:)` daje rogi
  kołowe, przy pełnowymiarowej ikonie zauważalnie „twardsze". Import SwiftUI w skrypcie
  nie przeczy zasadzie „czysty AppKit" — to generator zasobu uruchamiany raz, nie kod aplikacji.
- **Na co uważać:** `.icns` nie przenosi wariantu ciemnego motywu — to wymaga katalogu
  zasobów kompilowanego przez Xcode (`Assets.car`), którego nie mamy. Ikona jest jasna
  w obu motywach, jak kartka papieru — świadomy kompromis. Ikona w belce to osobny byt:
  szablonowy SF Symbol `note.text`, który system sam dostosowuje do motywu.

### `install.sh` — dlaczego kopiowanie wystarcza

- **Problem:** „instalacja" na macOS bywa mitologizowana; dla aplikacji bez sandboksa
  i bez zasobów systemowych to dosłownie skopiowanie pakietu.
- **Rozwiązanie:** `bundle.sh release` → `killall OneSheet` (SIGTERM przechodzi przez
  `applicationWillTerminate`, więc notatka ląduje na dysku przed podmianą) → `rm -rf` starej
  kopii → `ditto` nowej → `open`. `ditto` zamiast `cp -R`, bo zachowuje metadane i strukturę
  pakietu dokładnie tak, jak robi to Finder.
- **Dlaczego tak:** żadnych kreatorów, żadnego `sudo` — katalog `/Applications` ma grupowe
  prawo zapisu dla administratorów. Skrypt sprawdza `-w /Applications` i mówi wprost,
  gdy prawa nie starczają.
- **Na co uważać:** kolejność ma znaczenie — najpierw build (najdłuższy i może się nie udać,
  a wtedy stara kopia zostaje nietknięta), dopiero potem zatrzymanie działającej aplikacji.

### Notaryzacja — decyzja

Podpis ad-hoc (`codesign --sign -`) wystarcza, dopóki pakiet żyje na maszynie, na której
powstał: Gatekeeper weryfikuje kwarantannę pobranych plików, a lokalny build jej nie ma.
Notaryzacja i podpis Developer ID byłyby potrzebne dopiero do przeniesienia gotowego
`OneSheet.app` na inny komputer — wymagają płatnego konta deweloperskiego i nie dają nic
na własnej maszynie. Decyzja: **poza zakresem MVP**; droga na drugi komputer to
„sklonuj repozytorium i zbuduj na miejscu" (opisana w README).

## 4. Decyzje i odstępstwa od planu

Wszystkie w rejestrze decyzji w [WORKFLOW.md](../WORKFLOW.md):

- **rozszerzenie zakresu:** mechanizm `reconcileOnLaunch()` — plan etapu zakładał samo
  skopiowanie do `/Applications`, pomiar pokazał, że bez naprawy rejestracji autostart
  uruchamiałby kopię z repozytorium;
- nowy klucz `registeredBundlePath` w `UserDefaults` (aktualizacja specyfikacji, sekcja 3.5);
- notaryzacja poza zakresem MVP;
- finalna ikona nadal z generatora, kształt z SwiftUI.

## 5. Testy

- **Automatyczne:** 65 testów w 11 suitach, wszystkie zielone. Nowe:
  `LaunchAtLoginTests` — 6 wariantów decyzji naprawy (przeprowadzka, brak zapamiętanej
  ścieżki, ścieżka zgodna, kopia robocza, autostart wyłączony w systemie, zamiar wyłączony).
- **Sprawdzone przeze mnie na żywym systemie:**
  - przed naprawą wpis BTM wskazywał `file:///Users/macbook/Kodowanie/one-sheet/OneSheet.app/`;
    po `install.sh` i pierwszym starcie — `file:///Applications/OneSheet.app/`, `Generation: 2`,
    ten sam UUID (bez duplikatu);
  - log potwierdza przebieg: „Pakiet przeniesiony do /Applications/OneSheet.app — ponawiam
    rejestrację autostartu" → „Autostart włączony (status: 1)";
  - restart kontrolny: ponownej rejestracji **nie ma** (mechanizm jednorazowy), notatka
    użytkownika (227 znaków) wczytana z zainstalowanej kopii;
  - czysta przebudowa bez ostrzeżeń.
- **Potwierdzone przez użytkownika 2026-08-05:** wygląd finalnej ikony (Finder,
  `/Applications`); dwa monitory — panel otwierany na drugim ekranie, po dwóch poprawkach
  pozycjonowania (sekcja 6) pozycja zaakceptowana; Spaces i pełny ekran innej aplikacji —
  panel pozostaje widoczny. Tym samym domknięte zaległości z etapu 5.
- **Wymaga weryfikacji przez Ciebie:**
  - restart Maca: ikona w belce pojawia się sama, proces działa z `/Applications`
    (`ps aux | grep OneSheet`) — domyka zaległość z etapu 4;
  - tydzień codziennego użycia.

## 6. Napotkane problemy

**Defekt z weryfikacji dwóch monitorów (zgłoszony po pierwszym raporcie etapu).** Panel
otwarty wcześniej na wbudowanym ekranie, po kliknięciu ikony na zewnętrznym monitorze
lądował przy jego krawędzi zamiast pod ikoną. Przyczyna: zapamiętana ramka była zawsze
tylko przycinana (`PanelGeometry.clamped`) do ekranu docelowego — a przycięcie „dociąga"
prostokąt do najbliższej krawędzi, więc panel kończył najbliżej swojej starej pozycji.
Naprawa: `PanelGeometry.presentationFrame` — ramka przecinająca ekran docelowy jest
przycinana jak dotąd, ramka z innego ekranu jest zakotwiczana na nowo pod klikniętą ikoną
z zachowaniem rozmiaru. Cztery nowe testy (razem 69).

**Poprawka wyglądu przy okazji tej samej weryfikacji.** Zakotwiczony na nowo panel wypadał
wyśrodkowany względem ikony, przez co odsuwał się od niej w prawo — przy szerokim oknie
wyglądało to jak położenie przypadkowe. Zmiana: panel wyrównuje się do **lewej krawędzi**
ikony (z tym samym marginesem 6 pt, który dzieli go od belki), więc ikona zostaje nad
rogiem panelu, jak przy menu rozwijanym z belki. Gdy wyrównany panel wystawałby poza prawą
krawędź ekranu, dotychczasowe przycinanie cofa go do krawędzi — bez zmiany rozmiaru
(razem 70 testów).

Największą pracą etapu okazało się coś, czego w planie nie było: odkrycie, że login item
trzyma ścieżkę pakietu. Kolejność dochodzenia: `sfltool dumpbtm` pokazał URL wskazujący
repozytorium → pomiar tymczasowym logiem wykazał, że `status` z `/Applications` to nadal
`.enabled` (czyli status niczego nie wykryje) → drugi pomiar potwierdził, że `register()`
aktualizuje wpis w miejscu. Dopiero te trzy fakty wyznaczyły kształt mechanizmu — bez nich
naprawa oparta o status nigdy by się nie uruchomiła, a naprawa bezwarunkowa nadpisywałaby
decyzje użytkownika.

## 7. Dług techniczny

- Warunek `/Applications/` w `shouldRepairRegistration` jest sztywnym prefiksem — instalacja
  w `~/Applications` nie zostanie naprawiona. Świadome uproszczenie; `install.sh` instaluje
  wyłącznie do `/Applications`.
- Ikona bez wariantu ciemnego motywu (ograniczenie formatu `.icns` bez Xcode) — patrz wyżej.

## 8. Co dalej

To był ostatni etap planu. Zostaje weryfikacja ręczna z punktu 5 (ikona, restart Maca,
zaległości z etapu 5) i tydzień codziennego użycia — kryterium akceptacji całości.
Ewentualne poprawki po tym okresie to już utrzymanie, nie nowy etap.
