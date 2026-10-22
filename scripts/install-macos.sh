#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-macos.sh
destination="$HOME/Library/Input Methods/Wubi.app"
if [ -e "$destination" ]; then
  echo '输入法已安装。请先切换到其他输入法，将旧 Wubi.app 移走后重新运行安装。' >&2
  exit 1
fi
mkdir -p "$HOME/Library/Input Methods"
ditto build/Wubi.app "$destination"
echo '安装完成。请注销并重新登录，然后在系统设置 → 键盘 → 文本输入 → 编辑 → + → 简体中文中添加「五笔」。'
