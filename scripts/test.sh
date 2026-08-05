#!/usr/bin/env bash
#
# Uruchamia testy (swift-testing).
#
# Dlaczego to nie jest samo `swift test`:
# biblioteka swift-testing jest częścią Command Line Tools, ale SwiftPM szuka jej tam,
# gdzie kładzie ją Xcode. Na maszynie bez Xcode trzeba wskazać dwie ścieżki:
#   Library/Developer/Frameworks   → Testing.framework (kompilacja i linkowanie)
#   Library/Developer/usr/lib      → lib_TestingInterop.dylib (czas wykonania)
# Przy pełnym Xcode nie trzeba dokładać nic — skrypt sam to rozpoznaje.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="$(xcode-select -p)"

EXTRA_ARGS=()

if [[ "$DEVELOPER_DIR" == *CommandLineTools* ]]; then
	FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
	LIBRARIES="$DEVELOPER_DIR/Library/Developer/usr/lib"

	# Te ścieżki nie są udokumentowane przez Apple — aktualizacja Command Line Tools
	# może je przesunąć. Lepiej powiedzieć to wprost niż zostawić błąd linkera.
	for required in "$FRAMEWORKS/Testing.framework" "$LIBRARIES/lib_TestingInterop.dylib"; do
		if [[ ! -e "$required" ]]; then
			echo "BŁĄD: nie znaleziono $required" >&2
			echo "" >&2
			echo "swift-testing jest częścią Command Line Tools, ale najwyraźniej leży" >&2
			echo "gdzie indziej niż dotąd. Znajdź nową lokalizację:" >&2
			echo "  find $DEVELOPER_DIR -name 'Testing.framework' -o -name 'lib_TestingInterop.dylib'" >&2
			echo "i popraw ścieżki w tym skrypcie." >&2
			exit 1
		fi
	done

	EXTRA_ARGS=(
		-Xswiftc -F -Xswiftc "$FRAMEWORKS"
		-Xlinker -F -Xlinker "$FRAMEWORKS"
		-Xlinker -rpath -Xlinker "$FRAMEWORKS"
		-Xlinker -rpath -Xlinker "$LIBRARIES"
	)
fi

# Rozwinięcie z `+` zamiast zwykłego "${EXTRA_ARGS[@]}": pod `set -u` bash 3.2
# (ten z systemu) traktuje pustą tablicę jako niezdefiniowaną zmienną i przerywa.
swift test --package-path "$ROOT" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
