# Token 效率：AOSP 与调试场景还能压掉什么

> 结论先行：**token 不是被"代码"吃掉的，是被"日志、整文件读取、失败重试"吃掉的。**
> 本文按"漏斗大小 × 落地成本"排序给出方案；已落地三项（`log-digest` / `build-digest` / `cg-slice`），
> 其余按优先级排队。所有判断都以 AOSP 官方文档或公开实践为依据，并标注来源。

---

## 1. 四个漏斗

在一棵 Android BSP 树上做调试，上下文消耗大致按这个比例分布（按典型单轮任务估）：

| 漏斗 | 典型体积 | 占比 | 现状 |
|---|---|---|---|
| **日志摄入** | `m` 失败日志 200KB~2MB；10 分钟 logcat 3~8 万行；tombstone 数百行 | ~60% | 全靠人贴 / 模型 `tail`，一次就吃满窗口 |
| **整文件读取** | AOSP 大文件 `ActivityManagerService.java` 2 万+ 行、`View.java` 3 万+ 行 | ~20% | 只知道"符号在这个文件"，就 `Read` 整个文件 |
| **探索与重试** | 反复 grep、试错命令、WebFetch 抓 cs.android.com 失败 | ~15% | 无速查表，每次现场摸索 |
| **常驻注入** | `AGENTS.md`（35 库清单+冷区+命令表）、skills 描述 | ~5% | 每次请求都付，与当前任务无关也付 |

前三个漏斗都能用"**确定性预处理**"压掉 1~2 个数量级；第四个只能靠分层。

---

## 2. 已落地：日志摘要与源码切片

### 2.1 `log-digest` —— logcat / dmesg / 任意日志

```bash
adb logcat -b all -d | log-digest -
log-digest --kind kernel dmesg.txt
```

做法：**归一化 → 按签名聚合 → 按 严重度→次数 排序 → 每类留 1 条样本**。
归一化抹掉时间戳、pid/tid、十六进制地址、3 位以上数字、源码行号、引号内包名、ANSI 颜色——
这些字段一变就换签名，不抹掉等于没聚合。

三类关键设计（都来自实测踩坑）：

| 设计 | 为什么 |
|---|---|
| **崩溃块聚合** | `FATAL EXCEPTION` 后的 `at ...` 栈帧单独计数会把"1 次崩溃"算成"1+40 条"，还会把崩溃点从签名里拆散。现在签名形如 `FATAL EXCEPTION: main  @ com.x.Y.onCreate(Y.java:#)`，一次崩溃=1 条 |
| **`at` 必须带点** | 初版用 ` at [a-zA-Z]` 匹配栈帧，把内核的 `...dereference at virtual address` 整行吞掉了。收紧成 `at + 带点的类名` |
| **OTHER 限条数** | 日志里 `chatty: expire N lines` 之类的噪声占签名总数 90%，按次数排会挤掉真错误。OTHER 类单独限 3 条 |

实测（合成 8 万行 / 7.3MB logcat）：**3.3s，摘要 1778 字符，压缩约 4100:1**；
真实 4000 行混合日志：763 字符，5 类，崩溃点保留在签名里。
被隐藏的部分一律报 `# 未显示 N 类`，不制造"看全了"的假象。

### 2.2 `build-digest` —— soong / ninja 构建失败

```bash
build-digest --out out/            # 优先读 out/error.log
build-digest --log build.log
```

**为什么用 `out/error.log` 而不是 `tail build.log`**：AOSP 官方 `build/Usage.txt` 明确了三份日志的分工——

| 文件 | 内容 | 什么时候用 |
|---|---|---|
| `${OUT}/error.log` | **失败的动作及其输出** | 首选，通常几百 KB 以内 |
| `${OUT}/verbose.log.gz` | 每条命令的完整输出 | 只在需要命令上下文时 `zcat \| grep` |
| `${OUT}/soong.log` | soong_ui 的调试信息 | 构建图本身出问题时 |

工具做四件事：取首个 `FAILED:`、从 `.intermediates/<path>/<module>/android_*/` 推模块名（**标注为推断**）、
按 `BP / CC / JAVA / LINK / NINJA` 分类去重、给最小复现命令 `m <module>`。

结论只写日志能直接读出的事实，不猜根因。构建图层的典型处置是官方推荐的隔离动作：

```bash
m nothing     # 只让 soong 重新解析构建图，不产出
              # 报错 → 问题在 Android.bp / 依赖声明
              # 通过 → 问题在具体模块实现
```

**这两项都没有判"构建成功"的资格**，成功与否只能说 `verify-build` 的结论——
否则又回到"拿没验证的东西当证据"的老路。

---

### 2.3 `cg-slice` —— 只读那个函数，不读整个文件

```bash
cg-slice --file frameworks/base/Foo.java --symbol onCreate
cg-slice frameworks/base/Foo.java:128          # 日志里的 file:line
cg-slice frameworks/base/Foo.java#onCreate    # 简写
cg-slice --file frameworks/base/Foo.java --map
```

三种模式：`--symbol` 用 `codegraph query -j` 给的 `startLine/endLine` 精确定位；
`--line` 直接按行号切、**完全不依赖索引**；`--map` 只列符号地图（名字/类型/行号/签名），
不读正文。源码一律用 `sed` 从**磁盘**取，带原始行号输出。

**本机实测发现的一个真问题（codegraph 1.6.2）**：`codegraph node -f --offset`
读的是磁盘内容，行号却来自索引。给源文件开头插 1 行且不 `sync`，
它仍按旧行号 124 切片，屏幕上 124 是空行、目标方法其实在 125。
这正是本框架最忌讳的"拿过期索引当事实"。因此 cg-slice 强制做**锚点校验**：

| 结果 | 处置 |
|---|---|
| `anchor=exact` | 索引 startLine 那行含符号名，边界可信 |
| `anchor=shifted(N)` | 在 ±8 行内按符号名重定位并平移 endLine，输出明确标注 |
| 找不到 | `RESULT INCOMPLETE`，提示 `cg-build --sync-only`，**不切错内容** |
| `anchor=heuristic` | 无索引时退化为 grep + 括号配对，标注"不能据此判断函数体完整性" |

另外补了一层文件级新鲜度：`db_status` 只比 "db mtime vs 最近一次 commit"，
**看不出"文件改了但没提交、没 sync"**（实测此时仍报 `fresh`）。
cg-slice 额外比 `源文件 mtime` 与 `codegraph.db mtime`，输出 `file_vs_db=file_newer`
并发警告。

实测：造一个 20009 行 / 483830 字符的 `ActivityManagerService` 量级文件，
按符号切出 **9 行 / 267 字符，压缩 1812:1**（无索引时走启发式回退同样命中）。
134 行小文件切出 12 行（7.3:1）——小文件只看绝对行数，比例没有意义。
`--max-lines 200` / `--max-chars 12000` 两道硬上限，触发哪种就报哪种截断。

---

## 3. 排队中的方案（按杠杆排序）

> **P1 `cg-slice` 已落地**，详见 2.3。排队中的下一项从 P2 开始；
> 按"收益 / 成本"重新排序后建议先做 **P4 `handoff`**。

### P2 `cg-compdb` —— 让 C/C++ 有精确跳转

**做法**：`SOONG_GEN_COMPDB=1 SOONG_GEN_COMPDB_DEBUG=1 m nothing` →
`out/soong/development/ide/compdb/compile_commands.json`；引导 clangd / LSP 客户端使用它。

**依据**：
- Soong 官方 `docs/compdb.md`（`build/soong` 仓库）就是这个用法；
- 普通构建后 `out/soong/module_bp_cc_deps.json` 已存在，即使不生成 compdb 也能做 bp 级依赖分析；
- 社区实践（aosp-nav.nvim 等）用 compdb → clangd 做跨仓跳转。

**收益**：定义/引用从"grep 五个候选文件"变成 1 次精确查询。
**限制**：clangd 后台索引在 SMB 上很慢 → 只在服务器侧启用；客户端侧继续用 codegraph。

### P3 `aosp-src` —— 抓 AOSP/AndroidX 源码的正确姿势

**痛点**：查平台内部实现时，模型容易去 WebFetch `cs.android.com`，而它是 JS SPA，
抓回来是空壳，浪费一轮还得出"查不到"的错误结论。

**做法**：封装 Gitiles 原始文本接口
`https://android.googlesource.com/platform/<repo>/+/<ref>/<path>?format=TEXT` → `base64 -d`，
支持 `--tag android-14.0.0_rXX` 锁定版本；AndroidX 走 `raw.githubusercontent.com`；
工具内直接拒绝 `cs.android.com` 并说明原因。

**收益**：一次成功 + 只取需要的文件（base64 比 HTML 页面小一个数量级）。
**风险**：内网/离线环境不可用 → 明确 exit 3，不静默降级。

### P4 `handoff` —— 跨会话接续，而不是靠 compact

**做法**：`features/<feature>/handoff.md` 固定五段：
`做了什么 / 怎么验证的（命令+输出）/ 改了哪些文件（表）/ 当前阻塞 / 下一步（含文件路径）`。
新会话第一件事是读最近一份 handoff，子代理的 brief 直接复用同一份。

**依据**：AOSP 规模项目的公开实践（utzcoz: *Using Claude Code on AOSP-scale projects*）：
长 bug hunt 必须靠文件接力，"没有单一上下文窗口装得下，接力文档装得下"。

**为什么不用 `/compact` 代替**：compaction 本身要读全量上下文才产生摘要，而且会丢掉
失败假设与命令输出——恰恰是调试里最贵的部分。落文件是单向成本。

### P5 `AGENTS.md` 瘦身与分层

**现状**：根 `AGENTS.md` 承载 35 个库清单、冷区、命令表、debugdoc 说明，每次请求全量进入上下文。

**做法**：
- 库清单**不写进** `AGENTS.md`——`cg-route --list` 就是事实源，写明"禁止凭记忆列库，先查路由表"；
- 根文件只留：构建/验证命令、四段证据口径、红线（不改 out/、不动 prebuilts）、目录地图；
- 细节（boot-timing、perf-probe、adb 纪律）留在 skills，按需加载。

**依据**：官方建议 CLAUDE.md 控制在 200 行内，工作流细节放 skills；嵌套规则按目录触发。

**收益**：每轮都省，但不巨大（千级 token）。真正价值是**降低"规则被埋没"导致的错误**。

### P6 `errsig` —— 错误签名库（唯一越用越省的机制）

**做法**：`features/.harness/kb/errsig.tsv`，四列：
`归一化签名 \t 根因 \t 修法 \t 证据链接`。
`log-digest` / `build-digest` 出摘要时自动查表，命中就附一行"已知：…（见 …）"。

**收益**：同一类错误第二次出现时从"重新排查"变成"查表确认"。复利项，但需要人工沉淀。
**风险**：签名漂移漏命中 → 用宽松匹配 + 明确显示是"近似命中"。

### P7 症状 → 命令速查

一张表，每个症状 5 条以内命令 + 判断依据：

| 症状 | 首查 |
|---|---|
| Java 崩溃 | `logcat -b crash`（专用缓冲区，不必翻 main） |
| Native 崩溃 | `/data/tombstones/` + `debuggerd -b <pid>`；符号化 `ndk-stack -sym` 或 `development/scripts/stack` |
| 内核 oops/panic | `dmesg` → `scripts/decode_stacktrace.sh vmlinux` |
| ANR | `/data/anr/` + `dumpsys activity` 的 blocked 栈 |
| 开机卡住 | `logcat -b all -L`（含上次重启前的 pstore/ramoops） |
| SELinux 拒绝 | `avc: denied` 行 + `audit2allow` 只用于理解，不直接上策略 |
| 系统进程被杀 | `dmesg | grep -i watchdog\|lowmemorykiller` |

**收益**：省掉 5~10 轮探索命令。**风险**：容易写成百科 → 每症状限 5 条。

### P8 构建闭环提速（间接省 token）

| 做法 | 依据 |
|---|---|
| `m nothing` 先分"构建图问题 / 编译问题" | 官方 + 社区共识 |
| 单模块 `m <module>` 验证，不重跑全量 | 全量几十分钟 vs 单模块几秒 |
| `ccache` 50G + `compression=true` | 二次构建快一个数量级 |
| `repo forall -c` 做跨仓历史查询 | 避免逐仓 `git log` |

---

## 4. 反建议：这些事不要做

| 不要做 | 原因 |
|---|---|
| 再加 MCP server 来省 token | 工具定义常驻上下文；对已有 CLI 的领域，CLI 更省（官方明确建议优先 CLI） |
| 给 AOSP 每个仓写 `AGENTS.md` | 几百个仓，维护成本远超收益；只在 5 个一级目录 + 少数热点模块 |
| 把 `docs/` 全量注入上下文 | 文档是给人看的；模型要的是"查哪一份" |
| 用 subagent 跑单次 grep | subagent 有固定开销；只在"输出必然很大"时用（如全量构建、万行日志） |
| WebFetch `cs.android.com` | JS SPA，必失败，白烧一轮 |
| 用 `/compact` 替代落文件 | compaction 要读全量才产出摘要，且丢失败假设 |

---

## 5. 验收口径（新增工具必须自证）

1. **压缩比**：同类输入 ≥ 20:1（实测 log-digest ≈ 4100:1，build-digest ≈ 100:1）；
   cg-slice 按**绝对量**验收——≥1000 行文件切一个符号输出 ≤ 40 行，
   小文件（<200 行）不看比例、只看"没把整文件吐出来"；
2. **不隐藏丢弃量**：必须报"未显示 N 类"；
3. **数据缺失 ≠ 通过**：无输入 → `RESULT INCOMPLETE` + exit 3；
4. **不越权判定**：日志工具不判"构建成功"，那只能由 `verify-build` 说；
5. **回归覆盖正例 + 负例**：见 `harness/tests/test-harness.sh` 第 10 节。

---

## 6. 来源

- AOSP 构建日志分工：`platform/build/Usage.txt`（`verbose.log.gz` / `error.log` / `soong.log`）
- Soong compdb：`build/soong/docs/compdb.md`（`SOONG_GEN_COMPDB=1` + `m nothing`）
- Claude Code 成本与上下文：<https://code.claude.com/docs/en/costs>
- AOSP 规模下的代理工作流与 handoff：<https://utzcoz.github.io/2026/04/26/using-claude-code-on-aosp-scale-projects.html>
- clangd + compdb 社区实践：<https://github.com/yksnian/aosp-nav.nvim>
- `codegraph 1.6.2` `query -j` / `node -f` 行为：本机建小库实测（含"索引未 sync 时行号偏移"复现）
- 崩溃取证：Android 官方调试文档（debuggerd / tombstone / `stack` 脚本）、LineageOS 调试指南
