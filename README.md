# android-bsp-harness

把 AI 编码代理（Claude Code / OpenCode / Codex / Cursor…）接到**一棵真实的 Android / BSP 源码树**上，
让它: 知道自己在哪、查得到符号、改得动代码、**并且无法把"没验证"说成"验证通过"**。

针对的场景很具体：几百 GB 的 Android BSP，几十上百个 git 仓，`out/` 与 `prebuilts/` 里全是生成物，
一次全量索引要几小时，一次构建要几十分钟，一次上机要重启。在这种树上，模型最容易犯的不是"不会写代码"，
而是**拿过期索引当事实、拿没跑过的构建当证据、把"无法判定"讲成"没问题"**。

本框架用四件事把这条路堵住：

| 目标 | 手段 |
|---|---|
| 索引不过期 | 把树切成多个隔离库，路由到根，新鲜度可测（`cg-route` / `cg-assert`） |
| 检索不乱来 | 语言以**实测**为准，不做扩展名白名单；失败即明确回退 ripgrep |
| 验收不注水 | 四段证据 STATIC → BUILD → DEVICE → FEATURE，无法判定一律 `INCOMPLETE` |
| 范围不越界 | 基线 + 脏集的漂移守卫，跨根影响面断言（`check-drift` / `cg-assert impact`） |

---

## 0. 依赖

- **bash 4.4+**（Linux / macOS / Windows Git Bash 均可；脚本纯 bash，**不依赖 python3 / jq**）
- **git**
- **Node.js ≥ 18 + npm**（用于安装 codegraph）
- **codegraph**（`@colbymchenry/codegraph`）—— 缺失时 `cg-ensure` 会装
- 可选：`adb`（DEVICE 段）、`shellcheck`（测试）

> Windows 上必须用 **Git Bash**，不要在 PowerShell 里直接跑 `.sh`。

---

## 1. 四步到位

```bash
# 0) 装进你的源码树（只复制到 <tree>/features/.harness，不动任何源码）
bash install.sh --tree /path/to/android

# 1) 确认 codegraph CLI / MCP 可用，缺什么装什么
bash /path/to/android/features/.harness/bin/cg-ensure

# 2) 配置要建库的目录 → 生成路由表
$EDITOR /path/to/android/features/harness.conf     # 改 ROOTS
bash /path/to/android/features/.harness/bin/cg-roots sync

# 3) 按每个目录的**实际内容**生成 codegraph.json 排除配置
bash /path/to/android/features/.harness/bin/cg-exclude

# 4) 在相应目录自动建库（长任务，建议后台 + 日志）
bash /path/to/android/features/.harness/bin/cg-build
```

`bootstrap.sh` 把 1–4 串起来：

```bash
bash /path/to/android/features/.harness/bootstrap.sh --dry-run    # 先看计划
bash /path/to/android/features/.harness/bootstrap.sh              # 真跑
bash /path/to/android/features/.harness/bootstrap.sh --skip-build # 只做 1-3
```

### 这四步分别在解决什么

**① `cg-ensure` —— MCP 不看配置，看能不能用**

检查 CLI 版本、`codegraph serve --mcp` 子命令、客户端注册（Claude Code / OpenCode / WorkBuddy / Codex），
**并对每个已建库真打一次查询**。只判 mtime 会漏掉 `database disk image is malformed` 这种"文件在、库已烂"的假绿。
大库（3.2GB 级）上单次探活可能 >60s，超时记 `SKIP`（结论 `INCOMPLETE`），不假绿也不误判；
超时上限用 `CG_PROBE_TIMEOUT` 调。

**② `cg-roots` —— 目录由你定**

`features/harness.conf` 的 `ROOTS` 是唯一事实源。每个根 = 一个独立 `.codegraph/` = 一个 `projectPath`。
`cg-roots sync` 生成 `features/.harness/codegraph-roots.tsv`（路由表），`cg-route` / `cg-assert` 都读它。
`ALIASES` 支持"目录带版本号但代码里习惯写不带版本号"（如 `kernel=kernel-5.10`）。

**③ `cg-exclude` —— 排除项按实况生成**

不写死清单，而是**扫描该根**：只有确实存在的 `out/`、`prebuilts/`、`**/*.o` 才写进 `codegraph.json`。
写不存在的规则看起来"配置生效了"，实际什么也没挡住——这是最隐蔽的一类自欺。

它对已有 `codegraph.json` 很保守：只含 `exclude` 时会合并；含 `extensions`/`include` 等其它键时**拒绝覆盖**（除非 `--force`，且先备份）。

**④ `cg-build` —— 在相应目录建库**

首次走 `codegraph init -y`（`index` 在未初始化的目录上会被拒绝），之后 `sync` 增量，`--force` 走 `index` 重建。
逐根一个日志（`features/.harness/.state/cg-build-<root>-<ts>.log`），单根失败不中断后续，最后汇总并非 0 退出。

---

## 2. 日常命令

| 命令 | 作用 |
|---|---|
| `cg-route <路径>` | 这个文件属于哪个根、该用哪个库、库新不新鲜 |
| `cg-route --list` | 列出所有已登记的根 |
| `cg-assert env [--probe]` | 全部根的库状态；`--probe` 真打查询（识破假绿） |
| `cg-assert fresh <根>` | 单根新鲜度：`fresh` / `stale` / `missing` |
| `cg-assert langs <根>` | 该根**实测**已索引的语言分布（同时是完整性探针） |
| `cg-assert exists <根> <符号>` | 符号是否在该根索引里 |
| `cg-assert impact <根> <符号> [repos.tsv]` | 改动影响面是否越出 feature 范围 |
| `cg-build [--dry-run\|--force\|--only R\|--sync-only]` | 批量建库 / 增量同步 |
| `cg-exclude [--dry-run\|--deep\|--force] [根...]` | 生成排除配置 |
| `cg-roots list\|add\|rm\|sync [--langs]` | 维护根清单与路由表 |
| `feature-state capture\|show\|list [feature]` | 取 / 看 feature 基线 |
| `check-drift [feature] [--strict]` | 写代码前：范围内有没有被别人改过 |
| `prepare-feature [feature]` | 会话开场：校验结构 + 跑漂移 + 写快照 |
| `verify-build --log <log> [--artifact P] [--since E]` | 判定**已有**构建是否有效（不执行构建） |
| `boot-timing <子命令>` | 开机耗时测量：T1 首帧 / T2 就绪 / T3 末进程 / T4 真实空闲 |
| `perf-probe <子命令>` | 性能/温度/中断采样：`probe` `snap` `rank` `threads` `irq` `trend` |
| `ab-experiment <子命令>` | 设备侧**可逆** A/B：批量 `pm disable-user` / `pm enable` |
| `sync-skills [--dry-run]` | 把 skills 分发到 `.claude/skills` / `.opencode/skills` |

设备侧三个工具（`boot-timing` / `perf-probe` / `ab-experiment`）都**要求显式 `ANDROID_SERIAL`**，
多设备在线时拒绝猜目标；`boot-timing rounds` 会重启设备，必须显式授权。

所有脚本的退出码有统一语义：

| 码 | 含义 |
|---|---|
| `0` | 通过 / 成功 |
| `1` | 断言失败（stale、未找到、越界、漂移、有根失败） |
| `2` | 参数或配置错误 |
| `3` | **数据不可用**（工具缺失、库损坏、输出无法解析）→ 调用方必须记 SKIP/INCOMPLETE |

---

## 3. 建一个 feature

```bash
mkdir -p features/my-feature
cp harness/templates/feature-AGENTS.md       features/my-feature/AGENTS.md
cp harness/templates/feature-repos.tsv       features/my-feature/repos.tsv
cp harness/templates/feature-assertions.tsv  features/my-feature/assertions.tsv
cp harness/templates/feature-drift-ignore    features/my-feature/.drift-ignore
sed 's/<FEATURE>/my-feature/g' harness/templates/verify-feature.sh > features/my-feature/verify-my-feature.sh
chmod +x features/my-feature/verify-my-feature.sh

bash features/.harness/bin/feature-state capture my-feature   # 取基线
bash features/.harness/bin/check-drift my-feature             # 写代码前
bash features/my-feature/verify-my-feature.sh                 # 交付前
```

**断言阈值由人写**（`assertions.tsv`）。文件里没有生效行时，`verify-<feature>.sh` 的 FEATURE 段固定 `SKIP`，
最终结果必然是 `RESULT INCOMPLETE` —— **不是通过**。这是刻意的：宁可交不出结论，也不许编一个。

---

## 4. 目录结构

```
.
├── install.sh                 # 装进源码树（复制，不覆盖已有文件）
├── uninstall.sh               # 移除框架（保留 conf / feature / 索引）
├── harness.conf.example       # 配置模板
├── harness/
│   ├── bootstrap.sh           # 四步串联
│   ├── lib/common.sh          # 共用函数（路径归一化、git 包装、路由、新鲜度）
│   ├── bin/
│   │   ├── cg-ensure          # ① codegraph CLI/MCP 检查与安装
│   │   ├── cg-roots           # ② 根清单 → 路由表
│   │   ├── cg-exclude         # ③ 按实况生成 codegraph.json
│   │   ├── cg-build           # ④ 批量 init/sync/index
│   │   ├── cg-route           # 路径 → 根 / projectPath / 库状态
│   │   ├── cg-assert          # 静态断言（env/fresh/langs/exists/impact）
│   │   ├── check-drift        # 漂移守卫
│   │   ├── feature-state      # 基线 capture/show/list
│   │   ├── prepare-feature    # 会话开场
│   │   ├── verify-build       # 构建产物判定器（不构建）
│   │   ├── boot-timing        # 设备侧开机耗时测量
│   │   ├── perf-probe         # 设备侧性能/温度/中断采样
│   │   ├── ab-experiment      # 设备侧可逆 A/B
│   │   └── sync-skills        # skills 分发
│   ├── skills/                # codegraph-nav / deploy-and-accept / boot-timing
│   │                          # / perf-probe / ab-experiment / reserved
│   ├── templates/             # feature 骨架 + verify 模板
│   ├── examples/              # 真实落地的路由表样例（RK3562 7 根）
│   └── tests/test-harness.sh  # 临时假树里端到端自测
├── docs/
│   ├── DESIGN.md              # 四段证据、退出码、诚实性铁律
│   ├── CODEGRAPH.md           # codegraph 1.6.2 的事实
│   ├── TROUBLESHOOTING.md     # 假绿、路径写法、SMB、锁
│   └── kb/                    # 本地镜像（.gitignore，不入库；正文在 <源码树>/debugdoc）
└── examples/rk3562/           # 一个真实落地实例
```

---

## 5. 知识库：留在源码树上，不进仓库

这套框架是从一次真实的 RK3562 Android BSP 调试里长出来的，但**调试知识库本身不随仓库分发**：
里面是客户项目的评估报告、评审记录、原理图结论、补丁与测量数据，属于项目内部资产，
不适合放进一个可被复制/检索的代码仓库。

- **权威位置**：`<源码树>/debugdoc/`，入口是该目录的 `KB.md`（类别路由表 + 渐进式披露协议 R0–R7，
  先读它、按类别取，禁止全量加载）。规则正文在 `debugdoc/KB_PLAN.md`。
- **本地镜像（可选）**：如果希望在仓库目录旁也能翻阅，把它复制到 `docs/kb/` —— 该目录已在
  `.gitignore` 里，`git status` 永远干净，不会被推上去。
- **二进制大件**（原理图 PDF、录音、`.so`、trace、超大日志）本就不适合版本库，留在原树。

### 知识 → 框架的提炼结果（这部分随仓库分发）

库里的原始采集脚本被提炼成框架层的工具与 skill，旧实现冻结归档，只保留一个单一事实源：

| 原始材料 | 提炼产物 |
|---|---|
| `boot_time.sh` + `boot_measure.sh` + 多轮 A/B 记录 | `harness/bin/boot-timing` + `skills/boot-timing` |
| 7 个 CPU/温度/中断采样脚本 | `harness/bin/perf-probe` + `skills/perf-probe` |
| `boot_ab.sh` + `_kiosk_trim.sh` + `_gate_ab.ps1` | `harness/bin/ab-experiment` + `skills/ab-experiment` |

同一件事有两份实现，早晚有人改错那一份——所以提炼后旧脚本一律冻结，不再引用。

---

## 6. 验证状态（2026-10-30 实测）

| 项 | 结果 |
|---|---|
| `harness/tests/test-harness.sh --no-index` | `PASS=80 FAIL=0 SKIP=4`（shellcheck 未装 / --no-index 相关 3 条） |
| `cg-ensure --check`（真实树） | codegraph 1.6.2、`serve --mcp` 可用、claude/opencode 均已注册、7 个库中已建的均"可查询" |
| `cg-route` 真实树 | `system` / `packages` / `frameworks`（含 `frameworks/base/packages` 消歧）/ `device/rockchip` 全部命中正确 |
| 路径写法 | `Y:/...`、`/y/...`、`C:/Users/.../Temp/...` 三种入参收敛到同一路由结果 |

> 已知限制：kernel 级库（3.2GB）单次探活查询可能 >60s，`cg-ensure` 会记 `SKIP / INCOMPLETE`
> 而不是假绿；需要更长的超时用 `CG_PROBE_TIMEOUT=180`。

---

## 7. 自测

```bash
bash harness/tests/test-harness.sh             # 全量（含真建库，约 1-3 分钟）
bash harness/tests/test-harness.sh --no-index  # 跳过真建库
bash harness/tests/test-harness.sh --keep      # 保留临时目录
```

测试全程在 `mktemp -d` 的假树里跑：`install → cg-roots → cg-route → cg-exclude → cg-build →
cg-assert → feature 生命周期 → check-drift → verify-build → verify-<feature> → uninstall`。
codegraph 缺失时相关用例记 **SKIP**（不是 PASS）。

---

## 8. 设计取舍（为什么不是另一种做法）

**为什么切成多个库，而不是一个大库？**
一个 300GB 的树建单库，索引一次几小时、`status` 两分钟、改一行要重扫全树。切成按目录的库后，
每次 `sync` 只碰你实际改动的那个根，`projectPath` 明确，也不会出现"用 A 根的库查 B 根的符号"。

**为什么新鲜度看 `db mtime` + `git log -1`，而不是 `codegraph status`？**
`status` 在 3.2GB 的库上要 >2 分钟，放不进任何 hook。mtime 判"索引时间"，`git log -1` 判"代码时间"，
两者比较足够判 stale，且是 O(1)。代价是它不会告诉你"库里少了哪些文件"——那种精查留给人手动跑。

**为什么不用分支名做漂移守卫？**
真实 BSP 常见"全树几十个仓同一分支"（例如 `dis121c`），per-feature 分支并不存在。
所以基线记的是"**最后一次触及该路径的提交**"：目录自己是仓就看 HEAD，只是根仓的一部分就看
`git log -1 -- <path>`。这样"别人在你范围外改了这些路径"会体现为漂移，"别处有提交"不会误报。

**为什么阈值必须由人写？**
模型很擅长"补一个看起来合理的数字"。一旦阈值由代码预置，`RESULT PASS` 就变成了自我实现。
所以 `assertions.tsv` 只有注释时，机制固定输出 `SKIP` → `RESULT INCOMPLETE`。

**为什么不用软链分发 skills？**
SMB / Windows 共享上 `ln -s` 会静默退化成复制（实测）。复制 + 内容比对更笨，但行为可预测。

---

## 9. 已知边界

- `codegraph.json` 的 `exclude` 是 gitignore 风格，**不支持否定规则**；排除后想再捞回来只能改配置重建。
- `cg-exclude` 默认只采 3 层目录 / 4 层文件（快）；深目录噪声要 `--deep` 全量探测（慢）。
- `verify-build` **不执行构建**。构建执行能力是刻意预留的（不同 BSP 的构建入口差异太大，硬编码等于骗人）。
- DEVICE 段只做只读查询；部署的 5 步事务契约写在 skill `deploy-and-accept` 里，由人或后续脚本实现。
- 索引本身不含 git 历史语义：`stale` 只表示"代码比索引新"，不表示"索引错了"。

---

## 10. 文档

- [`docs/DESIGN.md`](docs/DESIGN.md) —— 四段证据、退出码语义、诚实性铁律
- [`docs/CODEGRAPH.md`](docs/CODEGRAPH.md) —— codegraph 1.6.x 的事实（命令、MCP、`codegraph.json` schema）
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) —— 假绿、损坏库、Windows/Git Bash、SMB 的坑
- `<源码树>/debugdoc/KB.md` —— 调试知识库入口（**不随仓库分发**，位置与理由见第 5 节）
- [`examples/rk3562/`](examples/rk3562/) —— 真实落地实例与踩坑记录（含实测的 7 根路由表）

## 开发模式（不装进树，直接跑仓库里的脚本）

脚本默认按"自己在 `<树>/features/.harness/`"推导树根。在仓库里直接跑时显式给树根：

```bash
HARNESS_ROOT=Y:/RK3562Android bash harness/bin/cg-route "Y:/RK3562Android/system/libbinder/IBinder.cpp"
HARNESS_ROOT=/y/RK3562Android bash harness/bin/cg-ensure --check
```

不带这个变量会按"仓库位置向上三级"推导，指向错误目录，报
`error: 路由表缺失 .../features/.harness/codegraph-roots.tsv`。

## License

MIT
