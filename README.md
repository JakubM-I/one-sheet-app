# one-sheet

Jedna, wieczna kartka na szybkie notatki, żyjąca w górnej belce macOS. Klikasz ikonę
(albo naciskasz `⌥⌘N`), piszesz, zamykasz — treść zawsze tam jest. Bez listy notatek,
bez zapisywania, bez wyszukiwarki. Szczegóły zakresu: [docs/FUNKCJONALNOSCI.md](docs/FUNKCJONALNOSCI.md).

## Wymagania

- macOS 26.0+ (Tahoe), Apple Silicon
- do budowania: Swift 6.3+ (wystarczą Command Line Tools, Xcode nie jest potrzebny)

## Instalacja

```bash
./scripts/install.sh
```

Skrypt buduje wydanie, kopiuje `OneSheet.app` do `/Applications` i uruchamia aplikację.
Przy pierwszym uruchomieniu aplikacja sama włącza „Uruchamiaj przy logowaniu"
(do wyłączenia w menu pod prawym przyciskiem na ikonie w belce).

Aplikacja jest podpisana ad-hoc — działa na maszynie, na której została zbudowana.
Przeniesienie gotowego `OneSheet.app` na inny komputer wymagałoby podpisu Developer ID
i notaryzacji; zamiast tego sklonuj repozytorium i zbuduj na miejscu.

## Użycie

| Działanie | Jak |
|---|---|
| Otwórz / schowaj panel | klik w ikonę w belce albo `⌥⌘N` z dowolnej aplikacji |
| Schowaj panel | `Esc` |
| Zakończ aplikację | prawy przycisk na ikonie → „Zakończ" |

Panel można przesuwać za górną krawędź i skalować za rogi; rozmiar i pozycja są
zapamiętywane. Panel zostaje otwarty, dopóki go świadomie nie zamkniesz — kliknięcie
w inną aplikację go nie chowa.

### Skróty formatowania

| Działanie | Skrót |
|---|---|
| Pogrubienie | `⌘B` |
| Kursywa | `⌘I` |
| Podkreślenie | `⌘U` |
| Przekreślenie | `⌃⌘K` |
| Powiększ / pomniejsz czcionkę | `⌘+` / `⌘-` |
| Lista punktowana | `⌃⌘L` |
| Wyrównanie do lewej / do środka | `⌘{` / `⌘\|` |
| Usuń formatowanie zaznaczenia | `⌃⌘\` |
| Wklej bez formatowania | `⌥⇧⌘V` |

Te same pozycje są w menu kontekstowym pola tekstu (prawy przycisk → „Formatowanie").

## Gdzie leżą dane i jak zrobić kopię zapasową

Cała notatka mieszka w jednym katalogu:

```
~/Library/Application Support/OneSheet/
├── note.rtfd          # treść notatki (format RTFD, otwiera go TextEdit)
├── note.rtfd.backup   # poprzednia poprawnie zapisana wersja
└── state.json         # pozycja kursora i przewinięcia
```

Kopia zapasowa to skopiowanie tego katalogu w dowolne miejsce:

```bash
cp -R ~/Library/Application\ Support/OneSheet ~/Desktop/OneSheet-kopia
```

Przywrócenie: zakończ aplikację (prawy przycisk na ikonie → „Zakończ"), skopiuj
katalog z powrotem, uruchom ponownie. Zapis na dysk jest atomowy i zawsze zostawia
kopię poprzedniej wersji — awaria w trakcie zapisu nie może skasować notatki.

## Praca nad kodem

```bash
swift build                    # kompilacja
./scripts/test.sh              # testy (swift-testing; samo `swift test` nie zadziała — patrz CLAUDE.md)
./scripts/run.sh [debug|release]   # build + uruchomienie kopii roboczej z repozytorium
```

Dokumentacja projektu: [CLAUDE.md](CLAUDE.md) (zasady pracy),
[docs/SPECYFIKACJA.md](docs/SPECYFIKACJA.md) (architektura),
[docs/WORKFLOW.md](docs/WORKFLOW.md) (etapy i rejestr decyzji),
[docs/podsumowania/](docs/podsumowania/) (jak działa każda warstwa).
