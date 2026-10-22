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
  macos/ProcessLifecycle.swift scripts/input-source.swift -o build/input-source

# Verify a complete replacement before interrupting the current input method.
staging=$(mktemp -d "$HOME/Library/Input Methods/.Wubi-update.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto build/Wubi.app "$staging/Wubi.app"
codesign --verify --strict "$staging/Wubi.app"
original=$(./build/input-source current)
backup="$staging/previous.app"

recover() {
  status=$?
  trap - ERR
  set +e
  if [ -d "$backup" ]; then
    ./build/input-source stop >/dev/null 2>&1
    if [ -e "$destination" ]; then
      if ! mv "$destination" "$staging/failed.app"; then
        trap - EXIT
        echo "无法移开失败的新版本，旧版本保留在：$backup" >&2
        exit "$status"
      fi
    fi
    if ! mv "$backup" "$destination"; then
      trap - EXIT
      echo "无法自动恢复，旧版本保留在：$backup" >&2
      exit "$status"
    fi
  fi
  ./build/input-source register "$destination"
  open -g "$destination"
  ./build/input-source select "$original"
  if [ "${1:-}" = '--notify-success' ]; then
    ./build/input-source notify-failure
  fi
  echo '重新加载失败，已尝试恢复原版本和输入源。' >&2
  exit "$status"
}
trap 'recover "${1:-}"' ERR
./build/input-source stop >/dev/null
mv "$destination" "$backup"
mv "$staging/Wubi.app" "$destination"
codesign --verify --strict "$destination"
./build/input-source register "$destination"
open -g "$destination"
./build/input-source select "$original"
trap - ERR
echo '小桃的五笔已更新并重启，无需注销。'
if [ "${1:-}" = '--notify-success' ]; then
  ./build/input-source notify-success
fi
