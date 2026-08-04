#!/usr/bin/env bash
#
# Składa OneSheet.app z binarki zbudowanej przez SwiftPM.
#
# Dlaczego to jest potrzebne: `swift build` produkuje samą binarkę, a NSStatusItem,
# LSUIElement i (w etapie 4) SMAppService wymagają prawdziwego pakietu .app z Info.plist.
#
# Użycie: ./scripts/bundle.sh [debug|release]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/OneSheet.app"

echo "==> Budowanie ($CONFIGURATION)"
swift build --package-path "$ROOT" -c "$CONFIGURATION"

BIN_PATH="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE="$BIN_PATH/OneSheet"

if [[ ! -x "$EXECUTABLE" ]]; then
	echo "Brak binarki: $EXECUTABLE" >&2
	exit 1
fi

echo "==> Składanie pakietu"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$EXECUTABLE" "$APP/Contents/MacOS/OneSheet"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "$ROOT/scripts/AppIcon.icns" ]]; then
	cp "$ROOT/scripts/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
	echo "    (ikona AppIcon.icns jeszcze nie istnieje — powstaje w etapie 6)"
fi

# Podpis ad-hoc. Bez niego macOS traktuje pakiet jako niezaufany przy każdym
# przeniesieniu, a SMAppService w etapie 4 w ogóle odmówi rejestracji.
echo "==> Podpisywanie (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> Gotowe: $APP"
