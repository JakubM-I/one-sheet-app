# Szablon podsumowania etapu

Plik powstaje po ukończeniu każdego etapu jako `etap_N_podsumowanie.md`.

**Cel dokumentu:** ma go czytać człowiek, który chce zrozumieć własną aplikację — nie tylko
dowiedzieć się, że etap „zrobiony". Piszemy tak, jakbyśmy tłumaczyli koledze, który zna
programowanie, ale nie zna akurat AppKit-u. Konkretnie, bez lania wody, bez chwalenia się.

Zasady:
- każde nietrywialne rozwiązanie wyjaśniamy: co robi, dlaczego akurat tak, co odrzuciliśmy
- fragmenty kodu tylko tam, gdzie ilustrują mechanizm — 5–15 linii, nie całe pliki
- nazwy API zawsze pełne (`NSStatusItem.button`, a nie „przycisk statusu”), żeby dało się je wygooglać
- napotkane pułapki i błędy opisujemy szczerze — one uczą najwięcej
- bez marketingu: „działa poprawnie” zastępujemy tym, co dokładnie sprawdzono

---

# Etap N — <nazwa> — podsumowanie

**Data ukończenia:** RRRR-MM-DD
**Status:** ukończony / ukończony z odstępstwami

## 1. Co powstało

Dwa–trzy zdania: co aplikacja potrafi po tym etapie, czego nie potrafiła wcześniej.

## 2. Nowe pliki i ich rola

| Plik | Odpowiedzialność |
|---|---|
| `Sources/OneSheet/...` | ... |

## 3. Jak to działa — mechanizmy

Sekcja edukacyjna, najważniejsza część dokumentu. Dla każdego istotnego mechanizmu:

### <Nazwa mechanizmu>

- **Problem:** co trzeba było osiągnąć
- **Rozwiązanie:** jakie API, jaki przepływ sterowania
- **Dlaczego tak:** jakie alternatywy odpadły i z jakiego powodu
- **Na co uważać:** pułapka, którą łatwo tu wdepnąć

## 4. Decyzje i odstępstwa od planu

Co zrobiliśmy inaczej niż zakładała specyfikacja i dlaczego. Jeśli nic — wpisz „brak”.
Każde odstępstwo musi też trafić do rejestru decyzji w [WORKFLOW.md](../WORKFLOW.md).

## 5. Testy

- **Automatyczne:** co pokrywają, ile ich jest, wynik `swift test`
- **Sprawdzone przeze mnie ręcznie:** lista z konkretnym wynikiem
- **Wymaga weryfikacji przez Ciebie:** to, czego nie da się sprawdzić bez ludzkich oczu
  (wygląd, płynność, zachowanie na Twoim sprzęcie)

## 6. Napotkane problemy

Co nie zadziałało za pierwszym razem, jaka była przyczyna, jak zostało rozwiązane.
Jeśli coś obeszliśmy prowizorycznie — zaznacz to wyraźnie i dopisz do długu technicznego.

## 7. Dług techniczny

Świadome uproszczenia do posprzątania później. Pusta lista to też odpowiedź.

## 8. Co dalej

Jednym akapitem: od czego zaczyna się kolejny etap i czy coś z tego etapu na niego wpływa.
