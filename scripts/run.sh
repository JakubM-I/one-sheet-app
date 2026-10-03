#!/usr/bin/env bash
#
# Buduje pakiet, ubija poprzednią instancję i uruchamia aplikację.
#
# Użycie: ./scripts/run.sh [debug|release]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-debug}"

"$ROOT/scripts/bundle.sh" "$CONFIGURATION"

if pgrep -x OneSheet >/dev/null; then
	echo "==> Zatrzymywanie poprzedniej instancji"
	killall OneSheet
	# LaunchServices potrzebuje chwili, zanim zwolni poprzednią instancję —
	# bez tego `open` potrafi po prostu uaktywnić zabijany proces.
	sleep 0.5
fi

echo "==> Uruchamianie"
# `-n` wymusza nową instancję zamiast uaktywnienia już działającej kopii
# zarejestrowanej wcześniej w LaunchServices (np. tej z /Applications).
open -n "$ROOT/build.noindex/OneSheet.app"

echo "==> Ikona powinna być w prawej części górnej belki."
# Uwaga na dwie pułapki w tym poleceniu:
#  - `log` to wbudowana komenda zsh, więc konieczna jest pełna ścieżka /usr/bin/log,
#  - wpisy poziomu `.info` nie są domyślnie pokazywane — stąd flaga --info.
echo "    Logi na żywo: /usr/bin/log stream --info --predicate 'subsystem == \"com.kubam.OneSheet\"'"
