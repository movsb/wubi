#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f pinyin_simp.dict.yaml ] || [ ! -f wubi86_jidian.dict.yaml ]; then
  echo '请先运行 ./get-dicts.sh 和 ./get-pinyin-dict.sh 下载词库。' >&2
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
