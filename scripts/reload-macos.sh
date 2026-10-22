#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
destination="$HOME/Library/Input Methods/Wubi.app"
if [ ! -d "$destination" ]; then
  echo '请先运行 ./scripts/install-macos.sh 安装并在系统设置添加「小桃的五笔」。' >&2
  exit 1
fi
# Build everything before interrupting the active input method.
./scripts/build-macos.sh
xcrun swiftc -module-cache-path "$PWD/build/module-cache" \
  scripts/input-source.swift -o build/input-source
original=$(./build/input-source stop)
# ditto retains files absent from the source bundle. Remove old dictionary copies
# so switching between original and merged tables preserves the resource seal.
rm -f "$destination/Contents/Resources/"*.dict.yaml
ditto build/Wubi.app "$destination"
codesign --verify --strict "$destination"
open -g "$destination"
./build/input-source select "$original"
echo '小桃的五笔已更新并重启，无需注销。'
if [ "${1:-}" = '--notify-success' ]; then
  ./build/input-source notify-success
fi
