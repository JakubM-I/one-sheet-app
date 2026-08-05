#!/usr/bin/env bash
#
# Instaluje OneSheet w /Applications: buduje wydanie, podmienia zainstalowaną kopię
# i uruchamia ją.
#
# Dlaczego /Applications: wpis autostartu w systemie trzyma ścieżkę pakietu, a kopia
# w repozytorium jest nadpisywana przy każdym buildzie. Zainstalowana aplikacja żyje
# poza repozytorium i przeżywa `rm -rf .build` czy przełączenie gałęzi. Po pierwszym
# uruchomieniu z nowej lokalizacji aplikacja sama przepisuje rejestrację autostartu
# na siebie (mechanizm w `LaunchAtLogin.reconcileOnLaunch()`).
#
# Użycie: ./scripts/install.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="/Applications/OneSheet.app"

"$ROOT/scripts/bundle.sh" release

if [[ ! -w "/Applications" ]]; then
	echo "Brak prawa zapisu do /Applications — uruchom z konta administratora." >&2
	exit 1
fi

# SIGTERM przechodzi przez `applicationWillTerminate`, więc notatka zostaje
# zrzucona na dysk zanim podmienimy pakiet.
if pgrep -x OneSheet >/dev/null; then
	echo "==> Zatrzymywanie działającej instancji"
	killall OneSheet
	sleep 1
fi

echo "==> Instalowanie do $TARGET"
rm -rf "$TARGET"
ditto "$ROOT/OneSheet.app" "$TARGET"

echo "==> Uruchamianie"
open "$TARGET"

echo "==> Gotowe. Ikona kartki powinna być widoczna w belce systemowej."
