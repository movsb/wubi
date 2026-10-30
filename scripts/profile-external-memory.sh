#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:-$PWD/build/Wubi.app}"
if [ ! -d "$app/Contents/Resources/cn_dicts" ]; then
  echo '请先运行 ./get-ice-dicts.sh 和 ./scripts/build-macos.sh' >&2
  exit 1
fi
mkdir -p build/module-cache
xcrun swiftc -O -module-cache-path "$PWD/build/module-cache" \
  macos/CandidateIndex.swift macos/DictionaryRow.swift macos/Dictionary.swift \
  macos/PinyinDictionary.swift macos/DictionaryMerger.swift macos/DictionaryStore.swift \
  macos/Punctuation.swift macos/ManualPhrase.swift macos/InputEngine.swift \
  tests/ExternalQueryMemory/main.swift -o build/external-memory-profile
./build/external-memory-profile "$app"
