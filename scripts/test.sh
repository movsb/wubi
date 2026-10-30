#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash tests/dictionary-conversion.sh
mkdir -p build/module-cache
GOCACHE="$PWD/build/go-cache" go test ./scripts/external-query
GOCACHE="$PWD/build/go-cache" go build -o build/test-external-query ./scripts/external-query
xcrun swiftc -module-cache-path "$PWD/build/module-cache" \
  macos/CandidateIndex.swift macos/DictionaryRow.swift macos/Dictionary.swift macos/PinyinDictionary.swift macos/DictionaryMerger.swift macos/DictionaryStore.swift macos/Punctuation.swift macos/ManualPhrase.swift macos/InputEngine.swift macos/KeyEvent.swift macos/ProcessLifecycle.swift \
  tests/InputEngineTests.swift tests/KeyEventTests.swift tests/PinyinTests.swift tests/DictionaryStoreTests.swift tests/ProcessLifecycleTests.swift tests/PrefixTests.swift tests/main.swift -o build/tests
./build/tests
