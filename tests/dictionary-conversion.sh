#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
printf '# copyright\r\n---\r\nname: fixture\r\n...\r\n甲\tabcd\t100\tstem\r\n# comment\r\n乙\tefgh\t2' > "$temporary/source"
printf '# copyright\n# ---\n# name: fixture\n甲\tabcd\t100\tstem\n# comment\n乙\tefgh\t2\n' > "$temporary/expected"
awk -f scripts/rime-to-text.awk "$temporary/source" > "$temporary/actual"
cmp "$temporary/expected" "$temporary/actual"
printf 'invalid download\n' > "$temporary/invalid"
if awk -f scripts/rime-to-text.awk "$temporary/invalid" > /dev/null 2>&1; then
  echo 'FAIL: invalid downloaded dictionary was accepted' >&2
  exit 1
fi
echo 'PASS: downloaded dictionary conversion preserves rows, weights and attribution'
