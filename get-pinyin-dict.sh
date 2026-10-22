#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
prefix='https://raw.githubusercontent.com/rime/rime-pinyin-simp/master'
mkdir -p licenses
curl --fail --location --retry 2 "$prefix/pinyin_simp.dict.yaml" -o pinyin_simp.dict.yaml.tmp
mv pinyin_simp.dict.yaml.tmp pinyin_simp.dict.yaml
curl --fail --location --retry 2 "$prefix/LICENSE" -o licenses/rime-pinyin-simp-LICENSE.txt.tmp
mv licenses/rime-pinyin-simp-LICENSE.txt.tmp licenses/rime-pinyin-simp-LICENSE.txt
