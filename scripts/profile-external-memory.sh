#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:-$PWD/build/Wubi.app}"
mkdir -p build/module-cache
xcrun swiftc -O -module-cache-path "$PWD/build/module-cache" \
  macos/CandidateIndex.swift macos/DictionaryRow.swift macos/Dictionary.swift \
  macos/PinyinDictionary.swift macos/DictionaryMerger.swift macos/DictionaryStore.swift \
  macos/Punctuation.swift macos/ManualPhrase.swift macos/InputEngine.swift \
  tests/ExternalQueryMemory/main.swift -o build/external-memory-profile
./build/external-memory-profile "$app"
