# codegraph 事实手册（以 1.6.2 实测为准）

> 本文件只记录**实测或源码确认**的行为。凡是没验证过的，标 `未验证`，不写成结论。
> 版本：`codegraph --version` = `1.6.2`（2026-10 实测）。

## 1. 命令行命令

| 命令 | 作用 | 备注 |
|---|---|---|
| `init [path]` | 初始化项目并建首次索引 | **首次必须走它**；`index` 在未 init 的目录上会拒绝 |
| `index [path]` | 全量重建索引 | 等价于对已 init 项目重跑 init |
| `sync [path]` | 增量同步 | `-q` 静默，适合 git hook |
| `status [path]` | 索引状态与统计 | 大库上很慢（3.2GB 库 >2min），别放进 hook |
| `query <搜索词>` | 符号搜索 | `-p <path>` 选根，`-l <n>` 限条数 |
| `explore <query...>` | 一次拿到相关符号源码 + 调用路径 | 与 MCP `codegraph_explore` 同输出 |
| `node [name]` | 单符号源码 + 调用者/被调用者 | 也可按文件读（带行号 + dependents） |
| `context <task...>` | 为任务构建上下文 | |
| `callers <symbol>` / `callees <symbol>` | 调用者 / 被调用者 | |
| `impact <symbol>` | 改动影响面 | |
| `files` | 列索引中的文件结构 | `-j` 出 JSON；`--no-metadata` 去语言/符号数 |
| `serve --mcp` | 以 MCP stdio server 启动 | 另有 `-p`、`--no-watch` |
| `install -t <ids> -l global` | 把 MCP 注册进客户端 | `-t claude,opencode,...`；`--print-config <id>` 只打印不写 |
| `uninit [path]` | 删除 `.codegraph/` | 不可逆，重建可能要几小时 |
| `unlock [path]` | 清掉阻塞索引的 stale lock | 索引被中断后常见 |
| `daemon` | 管理后台 daemon | |

`init` 的可用开关：`-y/--yes`（非交互，脚本用）、`-f/--force`（对家目录或文件系统根也照样建）、`-v`（worker 生命周期与内存细节）。

## 2. MCP：只有一个 server，选根靠参数

**事实**：客户端只注册一个 MCP server `codegraph`，命令为 `codegraph serve --mcp`（stdio）。
不存在 `mcp__codegraph_<一级根>` 这类按根拆分的 server，也**没有** `--root` 参数。

工具名固定 8 个：

```
codegraph_explore   codegraph_search   codegraph_node    codegraph_callers
codegraph_callees   codegraph_impact   codegraph_files   codegraph_status
```

选根参数是 **`projectPath`**（绝对路径）。三端参数纪律不同，**不要混**：

```bash
# CLI
codegraph explore -p "Y:/RK3562Android/system" "IBinder transact"
# MCP
codegraph_explore({ query: "IBinder transact", projectPath: "Y:/RK3562Android/system" })
# DSH / 其它客户端
projectPath=Y:/RK3562Android/system
```

`cg-ensure` 就是按这个事实做体检的：

1. CLI 是否存在、版本是否 ≥ `CODEGRAPH_MIN_VERSION`；
2. `codegraph serve --help` 是否可用（stdio 服务不能直接跑，只能验子命令）；
3. 客户端配置里是否有 `codegraph` 条目（JSON 看 `"codegraph"`，TOML 看 `[mcp_servers.codegraph]`）；
4. **对每个已建库真打一次查询**——只判 mtime 会漏掉 `database disk image is malformed` 这种"文件在、库已烂"的假绿。

> 第 4 步在大库上可能超过 60s。`cg-ensure` 用 `timeout`（`CG_PROBE_TIMEOUT`，默认 60s）包住，
> 超时记 **SKIP / 结论 INCOMPLETE**，既不假绿也不误判为坏库。

### 客户端注册的实际情况（2026-10 实测）

| 客户端 | 配置文件 | 形态 | 备注 |
|---|---|---|---|
| Claude Code | `~/.claude.json` | `{"type":"stdio","command":"codegraph","args":["serve","--mcp"]}` | `codegraph install -t claude` 写入 |
| OpenCode | `~/.config/opencode/opencode.jsonc` | `codegraph: {type:"local", command:["codegraph","serve","--mcp"]}` | `codegraph install -t opencode` 写入 |
| WorkBuddy | `~/.workbuddy/mcp.json` | `{"command":"cmd.exe","args":["/d","/c","codegraph","serve","--mcp"]}` | **`codegraph install` 不支持该客户端**，需手工加；Windows 上套 `cmd.exe /d /c` 才能解析 npm 的 `.cmd` 垫片 |
| Codex CLI | `~/.codex/config.toml` | `[mcp_servers.codegraph]` | TOML 形式，`cg-ensure` 按此判读 |

写进 WorkBuddy 的 `mcp.json` 后**不会自动生效**：需要在连接器管理页的"自定义连接器"处点 **Trust**，
或重启会话。

## 3. `codegraph.json`：可选的项目级配置

文件名固定 `codegraph.json`，位置在**项目根**（即你传 `-p` / `projectPath` 的那个目录）。
缺这个文件**不代表没有库**——只是走默认排除策略。

支持 5 个键（源码 `dist/project-config.d.ts` 确认）：

| 键 | 语义 |
|---|---|
| `extensions` | 自定义扩展名 → 语言 id，如 `{".foo": "c"}` |
| `exclude` | gitignore 风格，**即使被 git 跟踪也排除**（`.gitignore` 做不到这点） |
| `include` | gitignore 风格，**强制纳入**即使 `.gitignore` 排掉（如 SVN 下被 ignore 的真实源码） |
| `includeIgnored` | 只针对"被 ignore 目录里的嵌套 git 仓"，是否仍索引 |
| `deprioritize` | 仍索引、但不与一方代码抢搜索排名（`exclude` 是召回杠杆，这个是相关性杠杆） |

注意两点：

- `exclude` **不支持否定规则**（gitignore 风格但没有 `!`），排除后想捞回来只能改配置重建；
- 内置默认已排除一批（`node_modules`、`dist` 等）、`.git` 与 codegraph 自己的数据目录；
  显式 `exclude` 优先级更高。

所以 `cg-exclude` 对已有配置很保守：**只含 `exclude`** 时才合并；含 `extensions` / `include` 等键时
拒绝覆盖（除非 `--force`，且先 `codegraph.json.bak.<ts>` 备份）——因为这些键表达的人工意图无法被推断。

## 4. 语言支持：以索引实测为准

codegraph 支持 C/C++/Java/Kotlin/Rust/Python/Go/C#/Swift/Dart/Scala/PHP/Ruby/ObjC 等 30 种语言，
但**能不能查取决于该根索引里是否真有这门语言**。所以：

```bash
# 该根实测语言分布（同时是库完整性探针）
bash features/.harness/bin/cg-assert langs <root>
```

文件语言在该根的 `langs` 里 → 可用 codegraph；不在 → 一律 ripgrep。

典型不该用 codegraph 的：`.aidl` `.hidl` `.dts` `.dtsi` `.bp` `.mk` `.xml` `.json` `.sh`、
配置、字符串/注释/宏查找，以及路径命中 `tests/ vts/ samples/ gen/ out/ build/` 的文件。

遇到 `parse produced no symbols`：该文件解析失败，**立刻切 ripgrep**，不要硬分析。

## 5. 索引与磁盘

- 每个根各一个 `.codegraph/`（内含 `codegraph.db`），互不共享；
- 索引体积可观：本项目的 `kernel-5.10` 库约 3.2GB；
- 首次 `init` 是长任务（kernel 级目录在机械盘 / SMB 上可能数小时）；
  `cg-build` 因此逐根串行、每根一个日志、失败不中断后续；
- 慢文件系统（WSL2 `/mnt`、SMB）上建议 `serve --no-watch` 关掉文件监听，否则 CPU 被吃满；
- 索引被中断后若报 lock 冲突：`codegraph unlock <path>`。

## 6. SMB / 网络盘上的两个坑

1. `git` 会因 `dubious ownership` 直接失败 —— `lib/common.sh` 里所有 git 调用都显式带
   `-c safe.directory='*'`，不要改成裸 `git`。
2. `ln -s` 在 SMB 上会静默退化为复制（实测），所以 skills 分发用**复制 + 内容比对**，不用软链。

## 7. Windows / Git Bash 的路径写法

同一个目录在 MSYS 下有多种写法，且 `cd` 会"记住"你进门的写法：

```
Y:/RK3562Android  ==  /y/RK3562Android
C:/Users/<u>/AppData/Local/Temp/x  ==  /tmp/x
```

`cd C:\...\Temp/x && pwd -P` → `/tmp/x`；`cd /c/Users/.../Temp/x && pwd -P` → `/c/Users/.../Temp/x`。
两者是同一目录，**输出却不同**。

如果"树根"和"传入路径"各自被规范化到不同分支，前缀比较就永远不匹配，表现为
`error: 未登记的一级目录：<自己树里的路径>`。

`lib/common.sh` 的 `canon_path()` 用 `cygpath -w` 转成 Windows 形式再 `to_msys` 回 `/c/...`，
把两个方向收敛到同一写法。修改路径逻辑时，**两边都要过 canon_path**，只改一边必然复发。
