#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp}/clipkeep-tests.XXXXXX")
trap 'rm -rf "$TEST_BUILD"' EXIT
swiftc -O -module-cache-path "${CLIPKEEP_MODULE_CACHE:-$TEST_BUILD/modules}" Sources/ClipKeep/AbbreviationText.swift Sources/ClipKeep/AbbreviationValidator.swift Tests/AbbreviationValidatorTests.swift -o "$TEST_BUILD/validator-tests"
"$TEST_BUILD/validator-tests"

SOURCES=()
for source in Sources/ClipKeep/*.swift; do
    [[ "$source" == "Sources/ClipKeep/main.swift" ]] || SOURCES+=("$source")
done
swiftc -O -module-cache-path "${CLIPKEEP_MODULE_CACHE:-$TEST_BUILD/modules}" "${SOURCES[@]}" Tests/PanelTests.swift -lsqlite3 -o "$TEST_BUILD/panel-tests"
"$TEST_BUILD/panel-tests"
