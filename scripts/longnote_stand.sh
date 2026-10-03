#!/usr/bin/env bash
#
# Stanowisko testu długiej notatki (etap 5, hardening): uruchamia aplikację na
# ODIZOLOWANYM katalogu domowym z wygenerowaną notatką — prawdziwa notatka
# w ~/Library/Application Support/OneSheet nie jest dotykana.
#
# Katalog danych jest przekierowany zmienną ONESHEET_DATA_DIRECTORY (obsługiwaną
# przez NoteFileLayout). Podmiana samego HOME nie działa — na macOS 26 FileManager
# wyznacza katalog domowy z bazy użytkowników i ignoruje zmienną środowiskową.
# Binarka jest uruchamiana bezpośrednio, a nie przez `open`: `open` startuje proces
# przez LaunchServices i nie przekazuje zmiennych środowiskowych.
#
# Po zakończeniu testu: killall OneSheet && ./scripts/run.sh (powrót do prawdziwej notatki).
#
# Użycie: ./scripts/longnote_stand.sh [liczba_znaków]    (domyślnie 200000)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COUNT="${1:-200000}"
STAND="$(mktemp -d "${TMPDIR:-/tmp}/onesheet-stand-XXXXXX")"

"$ROOT/scripts/bundle.sh" debug

echo "==> Generowanie notatki ($COUNT znaków)"
swift "$ROOT/scripts/longnote_gen.swift" "$STAND/note.rtfd" "$COUNT"

if pgrep -x OneSheet >/dev/null; then
	echo "==> Zatrzymywanie działającej instancji"
	killall OneSheet
	sleep 0.5
fi

echo "==> Uruchamianie z ONESHEET_DATA_DIRECTORY=$STAND"
# Przekierowanie na /dev/null jest konieczne: proces w tle dziedziczy stdout skryptu
# i bez niego trzymałby otwarty potok każdego, kto czyta wyjście stanowiska.
ONESHEET_DATA_DIRECTORY="$STAND" \
	"$ROOT/build.noindex/OneSheet.app/Contents/MacOS/OneSheet" >/dev/null 2>&1 &
disown

echo "==> Stanowisko działa. Do sprawdzenia: otwarcie panelu, przewijanie, edycja."
echo "    Czas otwarcia panelu jest w logu:"
echo "    /usr/bin/log stream --info --predicate 'subsystem == \"com.kubam.OneSheet\"'"
echo "    Powrót do prawdziwej notatki: killall OneSheet && ./scripts/run.sh"
