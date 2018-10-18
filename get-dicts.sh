#!/bin/bash

set -eu

PREFIX='https://github.com/KyleBing/rime-wubi86-jidian/raw/master/'
DICTS=(wubi86_jidian.dict.yaml wubi86_jidian_addition.dict.yaml wubi86_jidian_extra.dict.yaml wubi86_jidian_user.dict.yaml)

for dict in ${DICTS[@]}; do
	wget "$PREFIX/$dict"
done
