#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" \
  macos/DictionaryRow.swift macos/Dictionary.swift macos/PinyinDictionary.swift macos/DictionaryMerger.swift macos/DictionaryStore.swift macos/Punctuation.swift macos/InputEngine.swift macos/KeyEvent.swift \
  tests/InputEngineTests.swift tests/KeyEventTests.swift tests/PinyinTests.swift tests/DictionaryStoreTests.swift tests/main.swift -o build/tests
./build/tests
