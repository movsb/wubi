#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
shopt -s nullglob

mkdir -p build
staging=$(mktemp -d "$PWD/build/.external-query.XXXXXX")
trap 'rm -rf "$staging"' EXIT
cp scripts/external-query/main.go "$staging/"
mkdir -p "$staging/dictionaries/external" "$staging/dictionaries/cn_dicts"
cp scripts/external-query/dictionaries/README.md "$staging/dictionaries/"
for dict in wubi*.txt; do
  if [ "$dict" != wubi86_jidian.txt ]; then
    cp "$dict" "$staging/dictionaries/external/"
  fi
done
ice_dicts=(cn_dicts/*.txt)
if [ ${#ice_dicts[@]} -gt 0 ]; then
  cp "${ice_dicts[@]}" "$staging/dictionaries/cn_dicts/"
fi
GOCACHE="$PWD/build/go-cache" go build -o "$1" "$staging"
