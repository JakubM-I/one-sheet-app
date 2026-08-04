# Opis funkcjonalności — one-sheet

## Idea w jednym zdaniu

Jedna kartka papieru przypięta do górnej belki systemu: klikasz, piszesz, zamykasz — treść zawsze
tam jest.

## Historyjki użytkownika

- Kopiuję fragment ze strony, klikam ikonę w belce, wklejam, zamykam. Zajmuje to trzy sekundy
  i nie muszę niczego nazywać ani zapisywać.
- Wracam do Maca po restarcie, klikam ikonę i widzę dokładnie to, co zostawiłem — łącznie
  z pozycją przewinięcia i formatowaniem.
- Chcę wyróżnić w zapiskach jedną linię jako nagłówek albo zrobić listę punktowaną — robię to
  skrótem klawiszowym, tak jak w każdej aplikacji macOS.
- Nigdy nie zastanawiam się „gdzie to zapisałem" — jest jedno miejsce.

## W zakresie

### 1. Obecność w belce systemowej

- Aplikacja startuje bez okna i bez ikony w Docku — widoczna jest wyłącznie jako ikona
  w prawej części górnej belki (menu bar).
- Kliknięcie lewym przyciskiem rozwija panel z notatnikiem tuż pod ikoną.
- Ponowne kliknięcie ikony lub `Esc` — panel się chowa.
- Kliknięcie prawym przyciskiem (lub długie przytrzymanie) otwiera małe menu:
  „Uruchamiaj przy logowaniu", „Zakończ".
- Ikona jest szablonowa (template) — sama dostosowuje się do jasnego i ciemnego motywu
  oraz do przezroczystości belki.

### 2. Panel z notatnikiem

- Jedno pole tekstowe wypełniające cały panel — bez pasków narzędzi, bez tytułu, bez zakładek.
- Panel jest przesuwalny i skalowalny; jego rozmiar i pozycja są zapamiętywane między
  uruchomieniami.
- Po otwarciu kursor od razu jest w tekście, w miejscu, w którym był ostatnio.
- Pozycja przewinięcia jest odtwarzana.
- **Panel zostaje otwarty, dopóki go świadomie nie zamknę.** Kliknięcie w inną aplikację,
  przełączenie okna czy przejście na inne biurko (Space) nie chowa notatnika — pływa on nad
  innymi oknami i czeka. Zamykają go wyłącznie: ponowne kliknięcie ikony, `Esc` oraz globalny
  skrót klawiszowy.

### 3. Edycja treści

- Pisanie, wklejanie, wycinanie, przeciąganie tekstu — pełne, standardowe zachowanie `NSTextView`.
- Wklejanie ze schowka zachowuje formatowanie źródła; `⌥⇧⌘V` wkleja jako czysty tekst.
- Nieograniczone cofanie i ponawianie (`⌘Z` / `⇧⌘Z`) w obrębie sesji.
- Standardowe usługi systemowe: sprawdzanie pisowni, zamiana tekstu, dyktowanie, emoji (`⌃⌘Spacja`).

### 4. Formatowanie treści

Jedyna „funkcja" aplikacji poza pisaniem. Dostępne przez skróty klawiszowe i menu kontekstowe
(prawy przycisk myszy w polu tekstu):

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

Menu kontekstowe zawiera te same pozycje, aby dało się formatować bez pamiętania skrótów.

### 5. Zapis i trwałość

- **Brak polecenia „Zapisz".** Każda zmiana trafia na dysk automatycznie, z krótkim opóźnieniem
  (ok. 0,7 s bezczynności).
- Wymuszony zapis następuje dodatkowo przy: zamknięciu panelu, utracie aktywności przez
  aplikację, uśpieniu Maca, wylogowaniu i zakończeniu aplikacji.
- Treść przeżywa: schowanie panelu, zamknięcie aplikacji, restart systemu, wymuszone ubicie
  procesu (utrata ograniczona do zmian z ostatniej sekundy).
- Zapis jest atomowy, z kopią zapasową poprzedniej wersji — uszkodzenie pliku w trakcie zapisu
  nie może skasować notatki.

### 6. Integracja z systemem

- **Globalny skrót klawiszowy** otwiera i zamyka panel z dowolnej aplikacji. Domyślnie `⌥⌘N`.
- **Uruchamianie przy logowaniu** — przełącznik w menu kontekstowym ikony, domyślnie włączony
  po pierwszym uruchomieniu (z możliwością wyłączenia).
- **Brak ikony w Docku** i brak przełączania `⌘Tab` — aplikacja nie zaśmieca przełącznika zadań.

## Poza zakresem — świadomie i trwale

Poniższe elementy **nie powstaną**. Lista istnieje po to, by nie wracać do dyskusji:

- wiele notatek, lista notatek, zakładki, karty
- katalogi, tagi, kolory etykiet, ulubione
- daty utworzenia i modyfikacji widoczne dla użytkownika
- wyszukiwanie i filtrowanie
- synchronizacja (iCloud, Dropbox, cokolwiek), konta, logowanie
- eksport, import, drukowanie
- szyfrowanie, hasło, Touch ID
- historia wersji, kosz, przywracanie
- obrazki i załączniki jako funkcja (wklejony obrazek nie zepsuje pliku i zostanie zachowany,
  ale nie budujemy wokół tego żadnego interfejsu — patrz uzasadnienie formatu RTFD w specyfikacji)
- tabele, linki klikalne
- Markdown, checklisty, bloki kodu, podświetlanie składni
- okno preferencji, panel ustawień, motywy
- przypomnienia, powiadomienia, widżety, Spotlight, Shortcuts, AppleScript
- statystyki, licznik słów

## Kryteria akceptacji całości

Aplikacja jest gotowa, gdy jednocześnie:

1. Ikona jest w belce po zalogowaniu, bez ręcznego uruchamiania.
2. Od naciśnięcia `⌥⌘N` do możliwości pisania mija poniżej 150 ms.
3. Tekst wklejony z przeglądarki zachowuje pogrubienia i kursywę.
4. `killall -9 OneSheet` bezpośrednio po wpisaniu zdania nie powoduje utraty tego zdania
   (po odczekaniu 1 s od wpisania).
5. Notatka o długości 50 000 znaków otwiera się i przewija bez zauważalnych zacięć.
6. Aplikacja nie tworzy żadnego pliku poza własnym katalogiem w `Application Support`
   i wpisami w `UserDefaults`.
