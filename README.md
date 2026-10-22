# WUBI

原来的 Go 命令行查词工具，以及基于 Apple InputMethodKit 的 macOS 原生五笔输入法。

## macOS 输入法

需要 macOS 13 或更新版本，以及 Xcode Command Line Tools（`xcode-select --install`）。无第三方运行时依赖。默认构建当前 Mac 架构，使用本地临时签名，适合本机使用；对外分发需另行 Developer ID 签名和公证。

```bash
./get-dicts.sh
./scripts/build-macos.sh
./scripts/install-macos.sh
```

安装到 `~/Library/Input Methods/Wubi.app`。首次安装后注销并重新登录，在「系统设置 → 键盘 → 文本输入 → 编辑 → + → 简体中文」中添加「五笔」。不需要辅助功能权限。仅构建时，产物位于 `build/Wubi.app`；双击 app 不会代替输入源注册。

词库沿用 [极点五笔 86 词库](https://github.com/KyleBing/rime-wubi86-jidian)，下载文件不提交到仓库。构建时打包根目录下的全部 `*.dict.yaml`，至少需要主词库 `wubi86_jidian.dict.yaml`。支持两列或带权重的多列 Rime 码表，按权重降序排列，同权重保留码表顺序，重复词条去重。扩展及用户词库可按需删除后重新构建。使用和分发词库时请查看上游的许可说明。

| 按键 | 功能 |
| --- | --- |
| 小写 a–z | 输入五笔编码 |
| 空格 | 上屏当前页首选词 |
| 1–9 | 选择当前页候选词 |
| 方向键、Page Up/Down、- / = | 候选翻页 |
| Backspace | 删除一个编码 |
| Escape | 取消当前编码 |
| Return | 原样输入编码 |
| 四码唯一候选 | 自动上屏 |
| 已输入四码后继续输入字母 | 上屏首选词，开始下一个编码 |

候选窗目前支持键盘选词，不支持鼠标点击。大写字母与常用系统快捷键交给应用处理。标点使用原键盘字符；暂未实现中文标点、拼音反查、学习调频及设置面板。候选只匹配完整编码，保留原程序行为。

更新前切换到其他输入法，移走已安装的旧 app，然后重新运行安装脚本并注销登录。卸载时先从系统设置移除输入源，再删除 `~/Library/Input Methods/Wubi.app`，注销登录。

验证词库解析与原有样例：

```bash
mkdir -p build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" macos/Dictionary.swift tests/main.swift -o build/dictionary-tests
./build/dictionary-tests
```

系统集成需安装后手动验证：在 TextEdit、浏览器输入框中测试 `q` + 空格、`imde`、重码数字选择、翻页、退格、取消、应用切换和 Command 快捷键。编译及词库测试通过并不等同于这些系统输入场景已通过。

## 原来的命令行工具

下载词库后运行 `go run .`。候选顺序保留词库顺序。

```bash
$ go run main.go 
Imported 89317 words
Input: q
[我 金]
Input: imde
[没有]
Input: qytr
[勿忘我]
Input: ihcq
[小鸡 錃 🐤]
Input: ugpg
[新型冠状病毒]
```
