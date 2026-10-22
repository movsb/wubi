#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash tests/dictionary-conversion.sh
mkdir -p build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" \
  macos/CandidateIndex.swift macos/DictionaryRow.swift macos/Dictionary.swift macos/PinyinDictionary.swift macos/DictionaryMerger.swift macos/DictionaryStore.swift macos/Punctuation.swift macos/ManualPhrase.swift macos/InputEngine.swift macos/KeyEvent.swift macos/ProcessLifecycle.swift \
  tests/InputEngineTests.swift tests/KeyEventTests.swift tests/PinyinTests.swift tests/DictionaryStoreTests.swift tests/ProcessLifecycleTests.swift tests/PrefixTests.swift tests/main.swift -o build/tests
./build/tests
