#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
prefix='https://raw.githubusercontent.com/iDvel/rime-ice/main'
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
# 仅导入已注音的表；tencent 为 text/weight 两列，需要 Rime 自动注音，不能直接读取。
for name in 8105 base ext others; do
  curl --fail --silent --show-error --location --retry 2 \
    "$prefix/cn_dicts/$name.dict.yaml" -o "$temporary/$name.dict.yaml"
  awk '$0 == "..." { found = 1 } END { exit !found }' "$temporary/$name.dict.yaml"
done
curl --fail --silent --show-error --location --retry 2 "$prefix/LICENSE" -o "$temporary/LICENSE"
{
  printf '# 来源：https://github.com/iDvel/rime-ice\n# 由 get-rime-ice-dict.sh 合并已注音词表，保留上游词频和注释。\n---\nname: rime_ice\n...\n'
  for name in 8105 base ext others; do
    printf '\n# 来源：cn_dicts/%s.dict.yaml\n' "$name"
    awk 'body { print; next } { print "# " $0 } $0 == "..." { body = 1 }' "$temporary/$name.dict.yaml"
  done
} > "$temporary/rime_ice.dict.yaml"
mkdir -p licenses
cp "$temporary/LICENSE" licenses/rime-ice-LICENSE.txt
mv "$temporary/rime_ice.dict.yaml" rime_ice.dict.yaml
echo '已导入雾凇字表、基础词库、扩展词库和杂项；重新构建加载后生效。'
