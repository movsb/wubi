# 拼音词库

`pinyin_simp.dict.yaml` 来自 [rime/rime-pinyin-simp](https://github.com/rime/rime-pinyin-simp)，上游采用 Apache License 2.0，完整许可见本目录的 `rime-pinyin-simp-LICENSE.txt`。

上游词库注明其来源为 Android 开源项目的 PinyinIME。词库通过 `get-pinyin-dict.sh` 原样下载，不提交到仓库；构建时将词库及本目录一同打包。

## 雾凇拼音

`rime_ice.dict.yaml` 由 `get-rime-ice-dict.sh` 合并 [iDvel/rime-ice](https://github.com/iDvel/rime-ice) 的 `cn_dicts/8105.dict.yaml`、`base.dict.yaml`、`ext.dict.yaml` 和 `others.dict.yaml`，保留原始词条、权重、注释与各表版本号。上游仓库采用 GNU GPL v3，完整许可见 `rime-ice-LICENSE.txt`；各表注明的原始数据来源保留在合并文件中。未导入需要 Rime 自动注音的 `tencent.dict.yaml`。

词库下载文件不提交到仓库；重新运行下载脚本后重新构建即可更新。运行时优先加载雾凇，未提供时回退到袖珍词库，避免混用不同词频尺度。
