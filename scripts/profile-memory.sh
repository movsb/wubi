#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f rime_ice.dict.yaml ]; then
  echo '请先运行 ./get-rime-ice-dict.sh 下载雾凇词库。' >&2
  exit 1
fi
mkdir -p build/module-cache
xcrun swiftc -O -module-cache-path "$PWD/build/module-cache" \
  macos/CandidateIndex.swift macos/DictionaryRow.swift macos/Dictionary.swift \
  macos/PinyinDictionary.swift macos/DictionaryMerger.swift macos/DictionaryStore.swift \
  scripts/dictionary-builder/main.swift -o build/dictionary-builder
xcrun swiftc -O -module-cache-path "$PWD/build/module-cache" \
  macos/CandidateIndex.swift macos/DictionaryRow.swift macos/Dictionary.swift \
  macos/PinyinDictionary.swift macos/DictionaryMerger.swift macos/DictionaryStore.swift \
  tests/DictionaryMemory/main.swift -o build/memory-profile
./build/memory-profile "$PWD/build/dictionary-builder"
