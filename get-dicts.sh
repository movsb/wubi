#!/bin/bash

set -eu

PREFIX='https://raw.githubusercontent.com/KyleBing/rime-wubi86-jidian/master'
# 主词库常驻；两个 extra 词库由构建脚本打包为按需查询的外部词库。
DICTS=(wubi86_jidian.dict.yaml wubi86_jidian_extra.dict.yaml wubi86_jidian_extra_district.dict.yaml)

cd "$(dirname "$0")"
for dict in "${DICTS[@]}"; do
	target="${dict%.dict.yaml}.txt"
	trap 'rm -f "$target.download" "$target.tmp"' EXIT
	curl --fail --location --retry 2 "$PREFIX/$dict" -o "$target.download"
	awk -f scripts/rime-to-text.awk "$target.download" > "$target.tmp"
	mv "$target.tmp" "$target"
	rm "$target.download"
done
