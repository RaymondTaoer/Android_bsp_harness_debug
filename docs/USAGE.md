# 工具使用方案

本文件只讲**怎么用**：一套 bash 工具如何把 AI 编码代理约束在一棵大型 Android / BSP 源码树上，
让它的每句结论都可被验证。不含任何具体项目、板卡、客户或内部资料信息，全部路径用占位符：

| 占位符 | 含义 |
|---|---|
| `<TREE>` | 源码树根（`/path/to/tree`、`Y:/path/to/tree` 等） |
| `<ROOT>` | 树下一个一级目录（= 一个独立索引库） |
| `<FEATURE>` | 一次改动的任务名（如 `boot-opt`） |
| `<VER>` | 版本号（如内核目录后缀） |

---

## 1. 管理思路：先管住结论，再管住代码

大树上 AI 翻车不是"不会写代码"，而是四类**结论造假**。工具与它们一一对应：

| 造假方式 | 具体表现 | 对应机制 | 用什么工具 |
|---|---|---|---|
| 拿过期索引当事实 | 用三天前的索引回答"谁调用这个函数" | 索引新鲜度可测 | `cg-route` / `cg-assert fresh` / `cg-ensure` |
| 拿没跑过的构建当证据 | 贴一段上次的编译日志 | 构建产物身份判定 | `verify-build` / `flash-verify` |
| 把"无法判定"说成"没问题" | 设备不在线就说"应该没事" | 四段证据 + `INCOMPLETE` | `verify-<feature>.sh` |
| 顺手改到范围外 | 改了 feature 之外的文件 | 基线 + 漂移守卫 | `feature-state` / `check-drift` |

**一句话原则**：宁可交不出结论，也不许编一个。所有机制都围绕这条设计——所以会出现
`RESULT INCOMPLETE`，它不是失败，是"没有结论"。

---

## 2. 心智模型：树 → 根 → 库 → feature

```
<TREE>/                        源码树根（通常是根 git 仓）
├── <ROOT-A>/                  ← 一个一级目录 = 一个独立索引库
│   └── .codegraph/            ← codegraph.db，互不共享
├── <ROOT-B>/
├── <ROOT-C>/
└── features/
    ├── harness.conf           ← ROOTS 定义的唯一事实源
    ├── .harness/              ← 框架本体（install.sh 装进来）
    │   └── codegraph-roots.tsv ← 路由表（cg-roots sync 生成）
    └── <FEATURE>/             ← 一次改动的上下文
        ├── AGENTS.md
        ├── repos.tsv           ← 本次允许改动的仓/路径
        ├── assertions.tsv      ← 人写的阈值
        ├── baseline.tsv        ← feature-state capture 生成
        └── verify-<FEATURE>.sh
```

三条规则决定了整套工具的形态：

1. **一个根一个库**。全树建单库，索引几小时、状态查询几分钟、改一行要重扫全树；切根后
   `sync` 只碰你改的那一块，`projectPath` 唯一，坏一个库不影响其它根。
2. **必须先路由**。库多了就存在"用 A 根的库查 B 根的符号"的风险，所以任何查询前先问
   `cg-route`：这个文件属于哪个根。判据永远是工具输出，不是路径里的字样。
3. **根清单是配置，不是代码**。换树、加减根只改 `harness.conf`，脚本不动。

---

## 3. 首次部署：四步到位

### 3.1 依赖

- bash 4.4+（Linux / macOS / Windows Git Bash；纯 bash，不需要 python3 / jq）
- git
- Node.js ≥ 18（装 codegraph 用）
- 可选：`adb`（设备段）、`shellcheck`（测试）

> Windows 上必须用 **Git Bash**，不要在 PowerShell 里直接跑 `.sh`。

### 3.2 装进树

```bash
bash install.sh --tree <TREE>
```

只往 `<TREE>/features/.harness/` 复制，不碰任何源码；已存在的文件不覆盖。

### 3.3 决定"切几个根"

编辑 `<TREE>/features/harness.conf` 的 `ROOTS`。选根的三条经验：

| 判据 | 说明 |
|---|---|
| git 仓边界 | 目录自己是独立 git 仓 → 天然适合做一个根 |
| 语言与检索习惯 | 平时会"在这个子树里找符号"的粒度，就是一个根 |
| 体量与改动频率 | 单根索引 > 4GB 或每次 sync 超过几分钟 → 再往下切 |

目录带版本号（`kernel-<ver>`）而代码里习惯写不带版本号时，用 `ALIASES` 建别名：

```bash
ALIASES=( "kernel=kernel-<ver>" )
```

别名行只做路由，不额外建库。

### 3.4 建库并自检

```bash
B=<TREE>/features/.harness/bin

bash $B/cg-ensure          # ① CLI / MCP / 客户端注册，缺什么装什么
bash $B/cg-roots sync      # ② ROOTS → 路由表
bash $B/cg-exclude         # ③ 按每个根的实际内容生成排除配置
bash $B/cg-build           # ④ 逐根 init / sync（长任务，逐根日志）

bash $B/cg-assert env --probe   # 验收：每个库真打一次查询
```

`bootstrap.sh` 把 ①–④ 串起来：

```bash
bash $B/../bootstrap.sh --dry-run     # 先看计划
bash $B/../bootstrap.sh               # 真跑
bash $B/../bootstrap.sh --skip-build  # 只做 1-3
```

**第 ③ 步为什么不能抄别人的清单**：`cg-exclude` 会先探测该根下是否真的存在
`out/`、`prebuilts/`、`**/*.o` 之类，只把确实存在的写进 `codegraph.json`。
写不存在的规则看起来"配置生效了"，实际什么都没挡住。

**第 ④ 步的预期**：kernel 级目录首次索引可能数小时；逐根串行、每根一个日志、
单根失败不中断后续，最后汇总并非 0 退出。

---

## 4. 日常循环：一次任务的标准动作

```
开场 → 定位 → 改 → 验 → 收尾
```

### 4.1 开场（30 秒）

```bash
B=<TREE>/features/.harness/bin
bash $B/prepare-feature <FEATURE>
```

做三件事：校验 feature 结构完整 → 跑一次漂移检查 → 写基线快照。
结构不全或范围外有脏文件，当场报出来，不要等到改完才发现。

### 4.2 定位（决定用 codegraph 还是 ripgrep）

```bash
bash $B/cg-route "<TREE>/<ROOT>/path/to/File.cpp"
# 输出：归属根 / projectPath / 库状态（fresh | stale | missing）
```

然后按文件类型与实测语言决定检索方式：

| 情况 | 用什么 |
|---|---|
| 符号、调用链、引用、影响面，且该根索引里确实有这门语言 | codegraph（见 skill `codegraph-nav`） |
| `.xml .mk .bp .sh .dts .dtsi .aidl .json`、配置、字符串/注释/宏 | ripgrep，**不要**硬塞给 codegraph |
| 索引 `stale` 但等不及重建 | 可以用，但结论必须标注"基于旧索引" |
| 查询报 `parse produced no symbols` | 立刻切 ripgrep |

语言是否存在要**实测**，不要靠扩展名猜：

```bash
bash $B/cg-assert langs <ROOT>
```

### 4.3 改之前先看漂移

```bash
bash $B/check-drift <FEATURE>            # 范围内有没有被别人改过
bash $B/check-drift <FEATURE> --strict   # 额外检查范围外的脏文件
```

漂移不是"报错"，是"你脚下的地基变了"。看到 DRIFT 要么先同步、要么把变化纳入本次改动。

### 4.4 验收：四段证据

```bash
bash features/<FEATURE>/verify-<FEATURE>.sh
```

固定四段，缺一段就是 `INCOMPLETE`：

| 段 | 回答的问题 | 判定依据 | 依赖工具 |
|---|---|---|---|
| STATIC | 符号/引用是否如声称 | 索引可查 + 符号存在 + 影响面不越界 | `cg-assert exists/impact` |
| BUILD | 构建是否真成功、产物是否真更新 | 成功标记 + 产物 mtime + 无 `error:` | `verify-build` |
| DEVICE | 设备上实际是什么状态 | `getprop` / `dumpsys` 只读输出 | `adb` |
| FEATURE | 功能指标是否达标 | **人写的阈值**（`assertions.tsv`） | 模板脚本 |

**阈值必须由人写**。`assertions.tsv` 只有注释时，FEATURE 段固定 `SKIP`，
整体必然 `INCOMPLETE`。这是刻意的：阈值一旦由代码预置，`RESULT PASS` 就成了自我实现。

### 4.5 收尾

证据落 `features/<FEATURE>/` 下（时序 CSV、采样 CSV、判定日志），不要写回工具目录。
下次有人问"当时凭什么说过了"，答案在证据里，不在对话里。

---

## 5. 场景速查

| 我想…… | 命令 |
|---|---|
| 知道这个文件属于哪个库、库新不新 | `cg-route "<path>"` |
| 列出所有根 | `cg-route --list` |
| 全部库体检（识破"文件在、库已烂"） | `cg-assert env --probe` |
| 单根新鲜度 | `cg-assert fresh <ROOT>` |
| 某根实测索引了哪些语言 | `cg-assert langs <ROOT>` |
| 符号是否在索引里 | `cg-assert exists <ROOT> <symbol>` |
| 改动是否越出 feature 范围 | `cg-assert impact <ROOT> <symbol> [repos.tsv]` |
| 重建/增量某几根 | `cg-build --only <ROOT>` / `--sync-only` / `--force` |
| 重新生成排除配置 | `cg-exclude --dry-run` → `cg-exclude` |
| 取/看基线 | `feature-state capture <FEATURE>` / `show` / `list` |
| 判定已有的构建日志是否有效 | `verify-build --log <log> [--artifact <p>]` |
| 从 `out/error.log` 定位构建失败（省 token） | `build-digest --out out/` |
| 把 logcat / dmesg 压成签名摘要 | `log-digest <file\|->` |
| 只看某个符号的实现，不读整个文件 | `cg-slice --file <f> --symbol <S>` |
| 按报错给的行号切一小段源码 | `cg-slice <file>:<line>` |
| 不读正文，只列文件的符号地图 | `cg-slice --file <f> --map` |
| 判定设备跑的是不是这次的产物 | `flash-verify --serial <S> [--kernel-image <p>]` |
| 量开机时序 | `boot-timing <subcommand>` |
| 采样 CPU/温度/中断 | `perf-probe <subcommand>` |
| 设备侧可逆 A/B | `ab-experiment <subcommand>` |
| 把 skills 分发到各客户端 | `sync-skills [--dry-run]` |

**退出码是接口，不是装饰**：

| 码 | 含义 | 应该做什么 |
|---|---|---|
| `0` | 通过 | 继续 |
| `1` | 断言失败（stale / 未找到 / 越界 / 漂移） | 修问题 |
| `2` | 参数或配置错误 | 改调用方式 |
| `3` | **数据不可用**（工具缺失 / 库损坏 / 输出无法解析） | 记 `SKIP` / `INCOMPLETE`，**不要**当成失败或通过 |

把 `3` 和 `1` 分开是刻意的：库损坏不等于代码错，设备没连不等于功能失败。
混在一起，人就分不清"改代码"还是"修环境"。

---

### 5.1 日志摄入：先压再读

一次 `m` 失败的日志通常 200KB~2MB，十分钟 logcat 常见 3~8 万行。
**不要把这些整段贴进上下文**——同样的错误重复几十次，真正有用的往往只有第一处。

| 输入 | 命令 | 输出 |
|---|---|---|
| soong / ninja 构建失败 | `build-digest --out out/` | 首个 `FAILED` + 推断模块名 + 去重错误 + `m <module>` |
| 没有 `out/`（手工 tee 的日志） | `build-digest --log build.log` | 同上 |
| logcat / dmesg | `log-digest -`（管道）或 `log-digest dmesg.txt` | 按 `KERNEL_OOPS / JAVA_CRASH / NATIVE / WATCHDOG / ANR / LMK / SELINUX / BINDER / TIMEOUT / BOOT` 分类的签名摘要 |

两个工具都遵守同一条纪律：**报告"没显示多少"**（`# 未显示 N 类`），
且**不判构建成功**——成功与否只能由 `verify-build` 说。

```bash
adb logcat -b all -d | log-digest - --max 10
build-digest --out out/                 # 缺 error.log 时返回 INCOMPLETE，不当成"没错误"
```

判读顺序：先看 `## 首个失败` / 第一条签名定层次（BP / CC / JAVA / LINK），
再决定是 `m nothing`（构建图问题）还是 `m <module>`（实现问题）。

### 5.2 源码切片：别为了一个方法读两万行

找到符号之后用 `cg-slice`，而不是整文件 `Read`：

```bash
bash features/.harness/bin/cg-slice --file frameworks/base/Foo.java --symbol onCreate
bash features/.harness/bin/cg-slice frameworks/base/Foo.java:128 --context 2
bash features/.harness/bin/cg-slice --file frameworks/base/Foo.java --map
```

| 场景 | 模式 |
|---|---|
| 知道符号名 | `--symbol`（索引给精确起止行，附 kind / signature / qualifiedName） |
| 日志报了 `Foo.java:128` | `--line` / `<file>:<line>`，**不依赖索引** |
| 不知道有什么可看 | `--map`，只列符号地图 |

头部四个字段决定结论可信度：`anchor=exact` / `shifted(N)` / `heuristic`，
以及 `file_vs_db=file_newer`。`--symbol` 会校验索引行号那一行是否真含符号名，
索引过期且 ±8 行内找不到时返回 `INCOMPLETE` 并提示 `cg-build --sync-only`，
**不会拿旧行号的内容充数**。细节见 `docs/TOKEN-EFFICIENCY.md` 2.3 节。

---

## 6. 设备侧纪律

| 规则 | 原因 |
|---|---|
| 必须显式 `--serial` 或 `ANDROID_SERIAL` | 多设备在线时自动挑一台 = 随机改机器 |
| 重启类操作必须显式授权 | `boot-timing rounds` 会重启，不能藏在默认行为里 |
| 只读优先 | DEVICE 段只做查询；写操作走部署契约 |
| 可逆优先 | A/B 用 `pm disable-user` 而不是卸载；随时能 `revert` |
| 部署五步事务 | 备份 → 停写 → 原子替换 → 校验 → 失败回滚（见 skill `deploy-and-accept`） |

高危命令建议加一道机械护栏（`adb-device-guard`）：以 PreToolUse hook 形式挂在客户端上，
拦截会把整机搞挂的命令（递归遍历 `/proc`、误停系统硬依赖包、无超时的 `logcat`/`wait-for`）。
它是**最后一道防线**，不是替代判断。

---

## 7. 常见误区

| 误区 | 实际 |
|---|---|
| "建一个大库更省事" | 索引几小时、查询几分钟、改一行重扫全树；且丢失 `projectPath` 唯一性 |
| "`codegraph status` 更准，应该用它判新鲜度" | 大库上 >2 分钟，放不进 hook；用 db mtime + `git log -1` 做 O(1) 判断 |
| "库文件在、mtime 很新，就是好的" | 可能是 `database disk image is malformed`；必须 `--probe` 真打一次查询 |
| "排除规则写全一点更保险" | 写了不存在的规则等于没写；让 `cg-exclude` 按实况生成 |
| "扩展名能判断语言" | 以 `cg-assert langs` 实测为准；不在索引里的语言一律 ripgrep |
| "没配阈值也先跑个 PASS 看看" | 机制会输出 `INCOMPLETE`，这就是正确行为 |
| "漂移报警是误报，忽略即可" | 漂移说明范围外有人动过，先确认再改 |

---

## 8. 一页清单

**首次部署**

- [ ] `install.sh --tree <TREE>`
- [ ] `harness.conf` 的 `ROOTS` 已按 git 仓边界 + 体量切好
- [ ] `cg-ensure` → `cg-roots sync` → `cg-exclude` → `cg-build`
- [ ] `cg-assert env --probe` 全绿（或明确记 INCOMPLETE 的原因）
- [ ] `bash harness/tests/test-harness.sh --no-index` → `FAIL=0`

**每次任务**

- [ ] `prepare-feature <FEATURE>` 无异常
- [ ] 定位前先 `cg-route`，检索方式按实测语言定
- [ ] 改前 `check-drift`，改后 `cg-assert impact` 不越界
- [ ] `verify-<FEATURE>.sh` 四段齐全；`INCOMPLETE` 不当通过
- [ ] 证据落 `features/<FEATURE>/`
- [ ] 汇报时区分 `PASS` / `FAIL` / `SKIP`，不合并成一个"基本没问题"

**换树/换板**

- [ ] 只改 `harness.conf` 与 `device/<vendor>` 相关路径，不动工具本体
- [ ] 重新 `cg-roots sync` + `cg-exclude`，旧路由表不可复用
- [ ] 平台专属检查写进 `verify-<FEATURE>.sh`，不塞进通用 skill

---

## 9. 边界（刻意不做的事）

- `verify-build` **不执行构建**：不同 BSP 的构建入口差异太大，硬编码等于骗人。
- DEVICE 段只做只读查询；部署能力由 skill 描述契约，由人或项目脚本实现。
- 索引不含 git 历史语义：`stale` 只表示"代码比索引新"，不表示"索引错了"。
- 不猜设备、不猜根、不猜语言：三者都以工具输出为准。
- 框架不带项目知识：板级差异、客户约束、内部结论留在项目自己的目录里，不进本仓库。

---

相关文档：`DESIGN.md`（为什么这样设计）、`CODEGRAPH.md`（codegraph 的事实）、
`TROUBLESHOOTING.md`（假绿、路径写法、SMB、锁）。
