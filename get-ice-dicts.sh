#!/bin/bash
# Download the upstream cn_dicts files and plain-text copies for later processing.
set -euo pipefail
cd "$(dirname "$0")"
prefix='https://raw.githubusercontent.com/iDvel/rime-ice/main'
dicts=(41448 8105 base ext others tencent)
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
for name in "${dicts[@]}"; do
  curl --fail --location --retry 2 "$prefix/cn_dicts/$name.dict.yaml" -o "$staging/$name.dict.yaml"
  awk -f scripts/rime-to-text.awk "$staging/$name.dict.yaml" > "$staging/$name.txt"
done
curl --fail --location --retry 2 "$prefix/LICENSE" -o "$staging/LICENSE"
mkdir -p cn_dicts
for name in "${dicts[@]}"; do
  mv "$staging/$name.dict.yaml" "$staging/$name.txt" cn_dicts/
done
mv "$staging/LICENSE" cn_dicts/LICENSE
echo '下载完成：cn_dicts/（保留上游原文件及转换后的 .txt）'
