#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -framework Cocoa \
  macos/CandidateIndex.swift macos/DictionaryRow.swift macos/ManualPhrase.swift \
  macos/ManualPhraseWindow.swift tests/ManualPhraseWindow/main.swift \
  -o build/manual-phrase-window-tests
test_data=$(mktemp -d)
trap 'rm -rf "$test_data"' EXIT
./build/manual-phrase-window-tests "$test_data"
python3 - "$test_data/manual.txt" <<'PYTEST'
import pathlib, sys
assert pathlib.Path(sys.argv[1]).read_text() == "重行\tzhong xing\n"
print("PASS: double-click saves manual.txt and exits the helper")
PYTEST
