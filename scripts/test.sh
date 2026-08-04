#!/usr/bin/env bash
#
# Uruchamia testy.
#
# `swift test` nie działa na tej maszynie — Command Line Tools nie zawierają XCTest
# ani swift-testing. Testy są zwykłym programem; szczegóły w Tests/OneSheetTests/TestHarness.swift.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swift run --package-path "$ROOT" OneSheetTests
