# 开发说明

[返回 README](../README.md)

## 构建与运行

需要 macOS 13 或更新版本和 Xcode Command Line Tools。首次构建先下载词库：

```bash
./get-dicts.sh
./get-pinyin-dict.sh
./scripts/build-macos.sh
```

产物为 `build/Wubi.app`，默认目标为当前 Mac 架构，使用本地临时签名。运行时不依赖 Python。安装及输入源注册步骤见 [README](../README.md#安装)。

主程序和辅助程序随 app 一同打包：

| 程序 | 职责 |
| --- | --- |
| `Wubi` | InputMethodKit 输入服务、按键处理与候选窗 |
| `WubiDictionaryBuilder` | 读取词库、生成合并索引及报告，完成后退出 |
| `ManualPhrase.app` | 普通系统文本框、即时拼音组合和手动造词保存 |

造词小程序不包含输入引擎，不拦截输入按键、不绘制输入候选；通过系统使用当前输入法。保存后以分布式通知触发主程序重载词库。

## 词库与索引

构建时打包项目根目录的 `wubi*.txt` 和 `pinyin_simp.txt`，忽略旧生成表 `wubi_merged.txt`。至少需要 `wubi86_jidian.txt`。内置码表支持两列或带权重的多列数据，同词同码去重。用户添加词库仅加载数据目录根部的 `manual.txt`；`excluded.txt` 按完整词语过滤内置及手动词条，过滤发生在拼音索引构建和五笔自动补词之前。

启动或重载时，由独立构建进程生成紧凑索引，主进程只读映射索引文件。构建完成后辅助进程退出，映射建立后删除临时索引文件；已建立的映射继续有效。重载失败时保留上次可用索引，不改写 app 包和原始词库。

索引用 UTF-8 字节及偏移量存储，避免重复保留完整字符串词表。合并完成后释放词频和组词临时数据；前缀缓存最多保留 4,096 个候选。完整报告逐条写入 `tmp/`，进程内只保留统计及各类前 30 条示例。

生成五笔词组码时，单字多编码优先最长码，再比较原权重和来源顺序。缺少单字编码或包含非汉字的词跳过，已有词不额外猜测新编码。具体取码规则见 [README](../README.md#五笔词库补充)。

候选初始排序规则：

- 一至三码保留原五笔顺序。
- 四码按拼音词频统一排序，同词多读音取最高词频，缺失词频视为零；同频保留原五笔顺序。
- 精确匹配优先于补全候选；补全初始按词频排列，同频时优先剩余编码较短的词，同词不重复显示。
- 个人词频仅影响五笔四码与拼音，按精确和补全两组分别调整，不改变两组的先后关系。

用户数据文件、纯文本格式和备份范围见 [README](../README.md#编辑与备份)。程序不包含旧词库目录或旧 JSON 词频的自动迁移逻辑。

## 更新流程

```bash
./scripts/reload-macos.sh
```

更新脚本先构建、测试并校验完整的新 app，临时切换到备用键盘，按实际 PID 停止输入法进程，再替换 app、启动并验证原输入源恢复。替换期间保留旧版本，失败时尝试回退并恢复输入源。

输入法菜单中的「重新构建并加载输入法」后台运行同一脚本，依赖构建时记录的本机源码路径。日志写入 `~/Library/Logs/Wubi/reload.log`。

## 测试

### 核心回归测试

```bash
./scripts/test.sh
```

无需安装输入法或下载词库。覆盖输入引擎、原生修饰键事件、中英文与拼音切换、选词翻页、标点、前缀匹配、个人词频、用户词库重载、合并规则、报告、坏文件恢复及进程生命周期。本地存在下载的词库时，额外检查真实词库样例、原词条保留和简码顺序。

构建脚本自动执行这些测试；测试失败时，更新会在停止旧输入法前中止。

### 造词窗口测试

在已登录的 macOS 桌面执行：

```bash
bash scripts/test-manual-phrase-window.sh
```

测试会短暂打开窗口，验证原生文本框焦点、系统输入上下文、单行输入与粘贴、即时拼音列表，以及双击保存后退出。仅使用临时数据，不改动个人词库。

### 内存检查

先下载五笔和拼音词库，再执行：

```bash
./scripts/profile-memory.sh
```

在独立测试进程中检查首次加载、大前缀查询和重载，不切换系统输入法。输出 RSS 和物理内存占用，默认物理占用上限为 128 MiB，可用 `WUBI_MEMORY_LIMIT_MB` 调整；实测受系统版本和词库内容影响。

### 手动验证

自动测试不能替代 InputMethodKit 集成验证。安装后仍需在 TextEdit、浏览器等应用中检查输入、焦点、候选窗位置、字体、外观切换及系统通知。

## 扩展查词程序（Go）

`./scripts/external-query` 是无第三方依赖的 Go 命令行程序，macOS 构建脚本将其编译并签名为 `Contents/MacOS/WubiExternalQuery`。Windows 可使用相同源码和协议编译 `.exe`。

```text
WubiExternalQuery RESOURCE_DIRECTORY USER_DIRECTORY CODE [--index-dir DIRECTORY]
```

输入为一至四个小写字母编码。程序读取资源根目录的 `wubi*.txt`、资源目录的 `external/*.txt` 和用户目录的 `external/*.txt`；后两者不存在时跳过。格式为 `词语<Tab>五笔码[<Tab>权重]`，权重不参与扩展结果排序。另外读取资源目录和用户目录的 `cn_dicts/*.txt`，依据常驻五笔单字码按现有组词规则生成编码。文件流式扫描，不构建完整词库索引。返回 UTF-8 JSON 对象 `{"words": ["词语"], "readings": {"字": ["zi"]}}` 到 stdout，精确匹配优先，其后按文件名和行顺序排列，同词去重；无匹配返回 `{"words": [], "readings": {}}`。遵守用户目录的 `excluded.txt`。失败时 stderr 输出错误并以非零状态退出。`readings` 仅包含匹配词涉及的单字读音，由输入法与现有单字读音合并，用于后续拼音组合选择。程序不写用户数据。

输入法在后台使用查询开始时的五笔快照反查过滤已有词（覆盖所有编码），并读取 `manual.txt` 排除已保存、尚未完成后台刷新或仅加入拼音的个人词条。过滤保持外部结果的顺序。macOS 调用时指定 `--index-dir`，Go 在指定目录写入 `words.index`、`readings.index`，stdout 不输出整批 JSON。两个文件使用与 `CandidateIndex.swift` 相同的 `WUBIIDX1` 格式：8 字节魔数、两个 little-endian UInt64（记录数、字节区长度），每条记录为四个 UInt32（词语偏移、词语长度、编码偏移、编码长度）及一个 Double 权重，末尾为 UTF-8 字节区。词语文件的编码为空以保留查询顺序；读音文件按单字编码排序。查询失败时丢弃整个临时目录。

输入法映射结果文件，只保留通过过滤的 UInt32 行号，候选窗及方向键每次最多读取 5 行。选中词后释放扩展列表，拼音组合使用 `ManualReadings.spelling(at:)` 按索引生成，避免分配所有组合。映射建立后在 macOS 上删除临时文件，映射随候选取消或选词释放；其他平台可在解除映射后清理文件。未指定 `--index-dir` 时仍返回上述 JSON，便于命令行调试。

运行 `./scripts/profile-external-memory.sh` 可独立测量三次 `w*` 展开、翻页及取消后的物理占用，并检查 2.44 亿种拼音组合仅生成当前页。需要先下载 cn_dicts 并构建；基准要求常驻词库加载成功、每次展开超过 5 万个新词，展开及浏览后的占用相对基线增量不得超过 8 MiB。

输入法异步调用程序，以请求 ID 丢弃编码修改、取消、模式切换或离开输入上下文后的旧结果。确认拼音后，输入法复用 `ManualReadings.save` 保存，立即上屏，再调用 `DictionaryStore.reloadInBackground`。后台在独立 Store 中构建并映射快照，在主线程发布最新请求的结果；过期结果丢弃，失败时保留旧词库。刷新完成前，新词已写入磁盘，当前输入继续使用旧快照。

```bash
go test ./scripts/external-query
# 检查 Windows 编译（无需 Windows 运行环境）
GOOS=windows GOARCH=amd64 go build -o build/WubiExternalQuery.exe ./scripts/external-query
```
