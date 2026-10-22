#!/bin/bash

set -eu

PREFIX='https://raw.githubusercontent.com/KyleBing/rime-wubi86-jidian/master'
DICTS=(wubi86_jidian.dict.yaml wubi86_jidian_addition.dict.yaml wubi86_jidian_extra.dict.yaml wubi86_jidian_user.dict.yaml)

cd "$(dirname "$0")"
for dict in "${DICTS[@]}"; do
	curl --fail --location --retry 2 "$PREFIX/$dict" -o "$dict.tmp"
	mv "$dict.tmp" "$dict"
done
