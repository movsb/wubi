# 拼音词库

`pinyin_simp.txt` 转换自上游的 `pinyin_simp.dict.yaml`，来自 [rime/rime-pinyin-simp](https://github.com/rime/rime-pinyin-simp)，上游采用 Apache License 2.0，完整许可见本目录的 `rime-pinyin-simp-LICENSE.txt`。

上游词库注明其来源为 Android 开源项目的 PinyinIME。词库通过 `get-pinyin-dict.sh` 原样下载，不提交到仓库；构建时将词库及本目录一同打包。

## 雾凇拼音扩展词库

`cn_dicts/` 由 `get-ice-dicts.sh` 从 [iDvel/rime-ice](https://github.com/iDvel/rime-ice/tree/main/cn_dicts) 下载，保留上游原始词库、来源注释及仓库 `LICENSE`。构建时将转换后的 TXT 嵌入 Go 扩展查词程序供按需读取，上游 `LICENSE` 随应用放入 `Resources/licenses/rime-ice-LICENSE.txt`。

## Unicode 搜索数据

`internal/unicodesearch/data/` 内嵌以下数据文件的 gzip 压缩版。数据文件采用 Unicode License v3，完整许可见 `unicode-LICENSE.txt`。

- Unicode 18.0 的 [DerivedName.txt](https://www.unicode.org/Public/18.0.0/ucd/extracted/DerivedName.txt)、[NameAliases.txt](https://www.unicode.org/Public/18.0.0/ucd/NameAliases.txt) 和 [emoji-test.txt](https://www.unicode.org/Public/18.0.0/emoji/emoji-test.txt)。
- CLDR 49 的英文注释 [annotations/en.xml](https://github.com/unicode-org/cldr/blob/release-49/common/annotations/en.xml) 和 [annotationsDerived/en.xml](https://github.com/unicode-org/cldr/blob/release-49/common/annotationsDerived/en.xml)。

项目补充的英文别名维护在同目录的 `aliases.tsv`。
