# 拼音词库

`pinyin_simp.txt` 转换自上游的 `pinyin_simp.dict.yaml`，来自 [rime/rime-pinyin-simp](https://github.com/rime/rime-pinyin-simp)，上游采用 Apache License 2.0，完整许可见本目录的 `rime-pinyin-simp-LICENSE.txt`。

上游词库注明其来源为 Android 开源项目的 PinyinIME。词库通过 `get-pinyin-dict.sh` 原样下载，不提交到仓库；构建时将词库及本目录一同打包。

## 雾凇拼音扩展词库

`cn_dicts/` 由 `get-ice-dicts.sh` 从 [iDvel/rime-ice](https://github.com/iDvel/rime-ice/tree/main/cn_dicts) 下载，保留上游原始词库、来源注释及仓库 `LICENSE`。构建时将转换后的 TXT 和上游 `LICENSE` 一同打包到应用资源的 `cn_dicts/`，仅供 Go 扩展查词程序按需读取。
