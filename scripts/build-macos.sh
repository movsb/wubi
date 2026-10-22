#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
shopt -s nullglob
dicts=(*.dict.yaml)
if [ ${#dicts[@]} -eq 0 ]; then
  echo '没有词库，请先运行 ./get-dicts.sh' >&2
  exit 1
fi
if [ ! -f pinyin_simp.dict.yaml ]; then
  echo '没有拼音词库，请先运行 ./get-pinyin-dict.sh' >&2
  exit 1
fi
./scripts/test.sh
app="$PWD/build/Wubi.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/module-cache
cp macos/Info.plist "$app/Contents/Info.plist"
printf '%s\n' "$PWD" > "$app/Contents/Resources/DevelopmentSourcePath.txt"
rm -f "$app/Contents/Resources/"*.dict.yaml
cp "${dicts[@]}" "$app/Contents/Resources/"
ditto licenses "$app/Contents/Resources/licenses"
xcrun swiftc -O -module-cache-path "$PWD/build/module-cache" \
  -target "$(uname -m)-apple-macosx13.0" -framework Cocoa -framework InputMethodKit \
  macos/Dictionary.swift macos/PinyinDictionary.swift macos/Punctuation.swift macos/InputEngine.swift macos/KeyEvent.swift macos/InputController.swift macos/main.swift \
  -o "$app/Contents/MacOS/Wubi"
codesign --force --sign - "$app"
echo "构建完成：$app"
