#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
shopt -s nullglob
dicts=(wubi*.txt)
if [ ${#dicts[@]} -eq 0 ]; then
  echo '没有词库，请先运行 ./scripts/get-dicts.sh' >&2
  exit 1
fi
if [ ! -f pinyin_simp.txt ]; then
  echo '没有拼音词库，请先运行 ./scripts/get-pinyin-dict.sh' >&2
  exit 1
fi
dicts+=(pinyin_simp.txt)
app="$PWD/build/Wubi.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/module-cache
./scripts/test.sh
cp macos/Info.plist "$app/Contents/Info.plist"
xcrun swift -module-cache-path "$PWD/build/module-cache" scripts/generate-menu-icon.swift \
  "$app/Contents/Resources/CookieTemplate.tiff" "$PWD/build/menu-icon-preview.png"
printf '%s\n' "$PWD" > "$app/Contents/Resources/DevelopmentSourcePath.txt"
rm -f "$app/Contents/Resources/"*.dict.yaml "$app/Contents/Resources/"wubi*.txt "$app/Contents/Resources/pinyin_simp.txt"
rm -rf "$app/Contents/Resources/external" "$app/Contents/Resources/cn_dicts"
for dict in "${dicts[@]}"; do
  case "$dict" in
    wubi86_jidian.txt|pinyin_simp.txt) cp "$dict" "$app/Contents/Resources/" ;;
  esac
done
rm -rf "$app/Contents/Resources/licenses"
ditto licenses "$app/Contents/Resources/licenses"
ice_dicts=(cn_dicts/*.txt)
if [ ${#ice_dicts[@]} -gt 0 ]; then
  cp cn_dicts/LICENSE "$app/Contents/Resources/licenses/rime-ice-LICENSE.txt"
fi
xcrun swiftc -O -module-cache-path "$PWD/build/module-cache" \
  -target "$(uname -m)-apple-macosx13.0" -framework Cocoa -framework InputMethodKit \
  macos/CandidateIndex.swift macos/DictionaryRow.swift macos/Dictionary.swift macos/PinyinDictionary.swift macos/DictionaryMerger.swift macos/DictionaryStore.swift macos/Punctuation.swift macos/ManualPhrase.swift macos/InputEngine.swift macos/KeyEvent.swift macos/InputController.swift macos/main.swift \
  -o "$app/Contents/MacOS/Wubi"
xcrun swiftc -O -module-cache-path "$PWD/build/module-cache" \
  -target "$(uname -m)-apple-macosx13.0" \
  macos/CandidateIndex.swift macos/DictionaryRow.swift macos/Dictionary.swift \
  macos/PinyinDictionary.swift macos/DictionaryMerger.swift macos/DictionaryStore.swift \
  scripts/dictionary-builder/main.swift -o "$app/Contents/MacOS/WubiDictionaryBuilder"
./scripts/build-external-query.sh "$app/Contents/MacOS/WubiExternalQuery"
codesign --force --sign - "$app/Contents/MacOS/WubiExternalQuery"
# Remove the retired helper from app bundles built by an older version.
rm -rf "$app/Contents/Helpers/ManualPhrase.app"
codesign --force --sign - "$app/Contents/MacOS/WubiDictionaryBuilder"
codesign --force --sign - "$app"
echo "构建完成：$app"
