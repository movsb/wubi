#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
prefix='https://raw.githubusercontent.com/rime/rime-pinyin-simp/master'
mkdir -p licenses
trap 'rm -f pinyin_simp.txt.download pinyin_simp.txt.tmp' EXIT
curl --fail --location --retry 2 "$prefix/pinyin_simp.dict.yaml" -o pinyin_simp.txt.download
awk -f scripts/rime-to-text.awk pinyin_simp.txt.download > pinyin_simp.txt.tmp
mv pinyin_simp.txt.tmp pinyin_simp.txt
rm pinyin_simp.txt.download
curl --fail --location --retry 2 "$prefix/LICENSE" -o licenses/rime-pinyin-simp-LICENSE.txt.tmp
mv licenses/rime-pinyin-simp-LICENSE.txt.tmp licenses/rime-pinyin-simp-LICENSE.txt
