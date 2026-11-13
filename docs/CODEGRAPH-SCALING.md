# 大规模 BSP 树的 CodeGraph 分层建库策略

> 依据：`codegraph 1.6.2` 源码（`dist/*.d.ts` + 官方 README）与两棵真实 Android BSP 树的实测，2026-11-13。
> 本文只写**实测或源码确认**的结论；估计值标注「预计」，未验证的标注「需验证」。
> 样本 A：Android 13 / 5.10 内核 / 7 个一级库（已建库）。
> 样本 B：Android 14 / 6.1 内核 / 8 个一级库（配置已就位、尚未建库）。

---

## 0. 结论先行

**失败不是「建不出来」，是「查不动」。** 一级目录一个库在 3 GB 以上时，最简单的
`query -l 1` 要 25–45 秒，真实 `explore` 直接超过 50 秒；这会同时撞上 MCP 客户端请求超时
和 codegraph 自己的 45 秒 busy 回退，表现为「MCP 失败」或「返回一段忙碌提示、看起来像没查到」。

**解法不是换工具，是把库切小。** 官方明确支持 monorepo 里「只索引部分子服务、用 `projectPath`
选库」；本机实测子目录独立 `init` 后 `projectPath` 隔离正确、父子库共存不冲突。
现有 harness 的路由脚本按最长前缀 + `db_root` 工作，多级子库路径**原生支持，无需改代码**。

**量化目标**：单库 `codegraph.db ≤ 0.5 GB` / `≤ 6,000` 索引文件；硬红线 `1 GB` / `10,000` 文件。
验收：`query -l 1 < 8s`、`explore < 15s`、MCP 调用 `< 30s`。

**正确顺序**：排除先行 → 按耦合边界切 L2/L3 → 路由与规则迁移 → 构建/MCP 调优 → 基准验证。
跳过第 1 步会拆出远多于必要的库。

---

## 1. 实测证据

### 1.1 单库体量 → 查询耗时（样本 A，同一台机器、同一网络盘）

| 一级库 | db 大小 | 索引文件数 | `query -l 1` | 备注 |
|---|---:|---:|---:|---|
| kernel | 4.51 GB | 49,916 | **> 45s 被 KILL** | |
| frameworks | 3.12 GB | 27,783 | 25.6s | `explore "Binder"` **> 50s 被 KILL** |
| packages | 2.86 GB | 30,086 | 30.3s | 无 `codegraph.json`，走默认排除 |
| hardware | 0.77 GB | 13,914 | 7.4s | |
| system | 0.24 GB | 4,402 | 4.6s | |
| vendor | 16 MB | — | 1.7s | |
| device | 1.2 MB | 126 | 1.56s | **固定开销基线** |

耗时 ≈ `1.5s（进程/连接固定开销） + 5–10s/GB`，且超大库非线性恶化（换页、WAL、图遍历）。
注意上表是**最简查询**；`explore` 至少 2 倍。

### 1.2 大库里到底是什么占体积（`dbstat`，frameworks 3.2 GB）

| 类别 | 占比 | 含义 |
|---|---:|---|
| `edges` + 3 个 edges 索引 | **≈ 38%** | 跨文件调用/引用关系 |
| `unresolved_refs` + 其索引 | ≈ 18% | 解析不了的引用 |
| `nodes` + 其索引 | ≈ 20% | 符号本体 |
| `nodes_fts_*`（FTS5 全文索引） | **≈ 4%** | 搜词索引 |

**关键推论**：慢的不是「搜词」，是**图遍历**（FTS + RWR/PageRank + impact + 输出构建）。
所以：
- 减少无关目录 → `edges` 下降；把强耦合代码放同一库、切断弱耦合边界 → 跨库边直接不产生；
- 切库有**超线性收益**：小库约 `57 KB/索引文件`，3 GB 大库约 `100–115 KB/文件`；
- 单纯「减少符号数」或「排除 generated」收益很小——实测 generated 文件仅万分之几，
  噪声是**真实但无关的源码**（非目标架构、非目标 SoC 厂商、tests、xml 资源）。

### 1.3 索引文件的目录集中度和三级分布（样本 A `files` 表）

| 一级库 | 最大二级目录 | 占该库 | 典型三级热点 |
|---|---|---:|---|
| kernel | `drivers` 34,573 | 69% | `drivers/net` 11,282、`gpu` 5,611、`media` 2,538、`staging` 1,934 |
| frameworks | `base` 17,752 | 64% | `base/core` 5,179、`base/packages` 4,670、`base/services` 3,694 |
| packages | `apps` 15,529 + `modules` 10,092 | 85% | `apps/Settings` 3,997、`modules/Bluetooth` 3,649 |
| hardware | 非目标 SoC 厂商合计 ≈ 7,600 | **55%** | 其余为 `interfaces`、`libhardware` 等 |

**只切到二级仍然超标**（`drivers/net` 单独就 11,282 文件），必须下沉到三级；
而 `hardware` 靠排除就能砍掉一半以上，根本不必拆。

---

## 2. 根因（源码级，不是推测）

| 现象 | 源码依据 | 机制 |
|---|---|---|
| MCP 超时 / `Transport closed` | `mcp/query-worker.d.ts` | 共享 daemon 单 event loop + 同步 `node:sqlite`；`explore` CPU 密集，N 个并发把 microtask 队列占满，socket I/O 和定时器饿死，响应刷不出去 |
| 「查不到」但不是报错 | `mcp/query-pool.d.ts` | `softTimeoutMs` 默认 **45s**；超时返回 **SUCCESS-shaped「busy, retry」提示**（刻意不是 `isError`）。代理把它当查询结果 → 表现为查找失败 |
| 首次查询突然 >60s / 索引被杀 | `db/wal-valve.d.ts` | 大库 WAL 可涨到 2 GB；未 backfill 的 WAL 让首次读页阻塞 >60s，liveness watchdog 会杀掉健康索引 |
| 大文件查不到 | `file-limits.d.ts` | 单文件 > 1 MB 不解析，只存 size stamp |
| 并发越多越糟 | `mcp/query-pool.d.ts` | `CODEGRAPH_QUERY_POOL_SIZE` 默认 `clamp(cores-1, 1, 16)`。多核构建机上等于 16 个 worker 同时压 3 GB 库 |
| 两个 MCP 客户端互踢 | 官方 README | 一个 project 只允许一个 live writer；多实例抢 `writer.pid` |
| 改了排除规则没生效 | 官方 README | `exclude` 不支持否定规则；`sync` 不会把已入库文件踢出去，必须 `index -f` 重建 |
| 传错 `projectPath` | 官方 README | 指向无 `.codegraph/` 的目录时返回「干净的使用内置工具提示」，**不报错** —— 旧规则让代理传一级目录，拆库后就会静默查不到 |

---

## 3. 量化阈值与换算

| 项 | 目标 | 硬红线 | 依据 |
|---|---|---|---|
| `codegraph.db` | ≤ 0.5 GB | 1 GB | 0.24 GB→4.6s；0.77 GB→7.4s；≥2.8 GB→30s+ |
| 索引文件数 | ≤ 6,000 | 10,000 | 57–115 KB/文件 |
| `query -l 1` | < 8s | 15s | 留 2 倍余量给 `explore` |
| `explore` | < 15s | 30s | MCP 客户端常见 30–60s 超时 |
| 单库并发 | 1–2 路 | 4 路 | 避免 query-pool 打满 IO |

> 换算用的是**索引文件数**（`codegraph files` / `files` 表），不是 git 受控文件数——
> 后者含 res/xml/tests，通常是前者的 2–3 倍。每个子库建完必须实测复核，不要按预估写死。

---

## 4. 分层模型

| 层 | 内容 | 是否建库 | 说明 |
|---|---|---|---|
| L0 | 树根 | 否 | `cg-route` 拒绝 |
| L1 | 一级目录（`frameworks` / `kernel-6.1` / `packages`…） | **否**（改造后） | 旧一级库先保留作兜底，验证通过后再 `uninit` |
| L2 | 子系统目录（`frameworks/base`、`kernel-6.1/drivers`） | 是 | 主要 `projectPath` 层 |
| L3 | 巨型子系统下的功能片（`base/core`、`drivers/gpu`） | 是 | 只对 L2 仍超标的开 |
| 冷区 | `external` / `prebuilts` / `cts` / `docs` | 否 | 一律 ripgrep |

### 切分六原则

1. **排除先行**：先按实况排除，能砍 40–60%，很多库一步达标。
2. **按耦合边界切，不按文件数平均切**：把常一起改、互相调用的放一起；跨库边会消失，体积超线性下降。
3. **边界必须落在目录边界**：codegraph 只认「目录 + `codegraph.json` exclude」，没有子文件集选择器。
4. **单库不跨一级目录**，保留现有隔离语义与规则纪律。
5. **热点优先精切**：高频改动的目录单独成小库；冷门目录合并或干脆不建。
6. **一个库尽量只放一个语义层**，避免把 HAL / framework / app 混进同一图里制造噪声边。

---

## 5. 实施顺序

### 5.0 排除先行（改动最小、收益最大）

按**该目录实际存在的内容**生成 `codegraph.json`，而不是抄清单：

```
# 非目标平台/厂商（样本 A 的 hardware 靠这条砍掉 55%）
hardware/qcom/**   hardware/google/**   hardware/nxp/**  ...（只写确实存在的）
# 非目标架构
arch/<非 arm/arm64>/**     arch/arm64/configs/**
# 明确噪声目录
staging/**  samples/**  Documentation/**  tools/**  scripts/**
tests/**  vts/**  cts/**  demo/**  benchmarks/**  gen/**  out/**  build/**
# 编译产物与生成代码
**/*.o  **/*.a  **/*.ko  **/*.cmd  **/*.mod.c  **/*.dtb  **/*.dtbo
**/*_gen.cpp  **/*_gen.h  **/*.pb.cc  **/*.pb.h
# 规则里本就要求 ripgrep 的类型，不必入库
**/*.xml  **/*.json  **/*.aidl  **/*.hidl  **/*.dts  **/*.dtsi  **/*.bp  **/*.mk
```

两条纪律：
- `exclude` **不支持 `!` 否定**；`deprioritize` 只改排名、不改召回，别拿它当过滤器；
- 改完必须 `codegraph index -f <root>` 全量重建，`sync` 不会剔除已入库文件。

`cg-exclude` 目前把 `EXTRA_EXCLUDE` 无条件写进**每一个根**，子库数量变多后会产生大量
「该根并不存在」的无效规则（看起来生效、实际没挡住）。建议先改成按根实况过滤：
取模式里第一个 `/**` 之前的路径前缀，仅当 `<root>/<prefix>` 存在时才写入。

### 5.1 切分到 L2/L3

按第 3 节阈值，对排除后仍超标的目录开子库。**优先精切热点，其余合并**。
样本 A 的候选切分（预计值基于 `files` 表三级分组，建库后需复核）：

| 原一级库 | 建议子库（`projectPath`） | 预计索引文件 | 处理要点 |
|---|---|---:|---|
| kernel 4.51 GB | `kernel-5.10/drivers/net`（先排除非目标网卡驱动） | ≤ 6,000 | 排除后可能不必再切 |
| | `kernel-5.10/drivers/gpu` | 5,611 | 单独 |
| | `kernel-5.10/drivers/media` + `iio` + `video` + `input` | ≈ 4,300 | 高内聚合并 |
| | `kernel-5.10/` 核心片（`arch/arm64` `include` `kernel` `mm` `fs` `net` `lib`） | ≈ 6,000 | 需 `include`/`exclude` 精配 |
| | 其余 `drivers/*`（排除 `staging`） | ≈ 5,000 | 合并 1 库 |
| frameworks 3.12 GB | `frameworks/base/core` | 5,179 | 单独 |
| | `frameworks/base/packages` | 4,670 | 单独；最长前缀保证不落到顶层 `packages` |
| | `frameworks/base/services` | 3,694 | 单独 |
| | `frameworks/base/libs` + `media` + `telephony` + 小目录 | ≈ 3,000 | 合并 |
| | `frameworks/av` + `frameworks/native` | 5,934 | 可分 2 库 |
| | `frameworks/opt` + `rs` + `compile` + 其余 | ≈ 3,100 | 合并 |
| packages 2.86 GB | `packages/apps/Settings` | 3,997 | 热点，单独 |
| | `packages/modules/Bluetooth` | 3,649 | 热点，单独 |
| | `packages/apps` 其余（按功能分组 2–3 片） | 各 ≤ 6,000 | |
| | `packages/modules` 其余（2 片） | 各 ≤ 6,000 | |
| | `packages/services` + `providers` + `inputmethods` | ≈ 4,400 | 合并 |
| hardware 0.77 GB | **排除后整体一个库** | ≈ 6,300 | 排除比拆分有效得多 |
| system 0.24 GB | 保持 | 4,402 | 已达标 |
| vendor / device | 保持 | 很小 | 已达标 |

样本 B（6.1 内核）三级热点不同：`drivers/gpu` 7,177、`drivers/net` 6,006、
`frameworks/base/core` 18,738（git 受控，实际索引远小于此）、`packages/apps/Dialer` 7,828、
`modules/Bluetooth` 5,395。**必须按该树自己的 `files` 表重算，不要照搬样本 A 的切分表。**

### 5.2 路由与规则迁移（最容易漏、后果最严重）

拆库后 `projectPath` 不再是「一级顶层目录」。若规则正文不改，代理继续传一级目录，
codegraph 会**静默返回「请用内置工具」提示**（不报错），表现为「查找失败」。

- `features/harness.conf`：把 `ROOTS` 从一级目录改成子库路径数组；
  清理指向已不存在库的 `ALIASES`；`EXTRA_EXCLUDE` 按 per-root 需求重写。
- `cg-roots sync` 重生成路由表；`cg-route <路径>` 会因最长前缀自动命中 L2/L3。
- **规则正文**：把「`projectPath` 固定写一级顶层目录」改为
  「`projectPath` = `cg-route` 输出命中的最长前缀目录」，并重跑指针生成脚本刷新子目录入口。
- `codegraph-nav` skill 同步措辞；`cg-assert` / `cg-route` / `cg-build` / `feature-state`
  **无需改代码**（按 `db_root` 工作，`cg-build` 已把 `/` 转成日志 slug）。
- 路由表行数从 7–8 增到 20–30，`route_for` 是线性最长前缀扫描，无性能问题。

### 5.3 构建与 MCP 调优（均为官方支持的环境变量）

| 变量 / 开关 | 建议 | 依据 |
|---|---|---|
| `CODEGRAPH_QUERY_POOL_SIZE` | 显式设 **2–4**，不要留默认 | 默认 `clamp(cores-1,1,16)`，多核构建机上 16 worker 并发压库会雪崩 |
| `CODEGRAPH_NO_DAEMON=1` | Windows / SMB 建议开 | 避免多 MCP 实例抢 writer lock 与 `Transport closed` |
| `serve --no-watch` | 网络盘上开 | 文件监听会吃满 CPU |
| `CODEGRAPH_WAL_VALVE_MB` / `CODEGRAPH_WAL_HEAL_MB` | 建库期放宽、rest 维持 64 MB | 大库 WAL 可到 2 GB，未 backfill 会阻塞首读 |
| `CODEGRAPH_MCP_TOOLS` | 按需收窄 | 默认只暴露 `explore` |
| `BUILD_SERIAL=1` | 保持 | 串行建库，避免 IO 争抢、日志可归因 |
| `CG_PROBE_TIMEOUT` | 子库达标后降到 20–30s | 探活超时记 `INCOMPLETE`，不假绿 |

建库位置：**优先在源码所在服务器的本地路径执行**，不要跨 SMB 建全量索引。
框架已提供 `features/.harness/bin/cg-build-server`：按脚本自身位置推导树根，
串行逐库 `init`/`sync`、每库独立日志、默认压住查询池并发、建完自动跑 `cg-bench` 验收：

```bash
cd <服务器本地源码树路径>
bash features/.harness/bin/cg-build-server --check    # 体检，不写盘
bash features/.harness/bin/cg-build-server --dry-run  # 只看计划
bash features/.harness/bin/cg-build-server            # 建库 + 验收
```

产物落在同一棵树的各子库 `.codegraph/` 里，Windows 侧通过映射盘读到的是同一份。

### 5.4 基准验证（每个子库建完必做）

见第 8 节脚本。任一项超红线 → 继续排除或再切一层，不要靠调大客户端超时掩盖。

---

## 6. 代价、风险与回退

| 代价 | 说明 | 缓解 |
|---|---|---|
| **跨子库调用链断裂** | `impact` 只在单库内；跨一级库本来就断，拆库只是增加边界数 | 按高内聚切；跨库用 `cg-assert impact` + ripgrep 分段推进；结论里注明分段 |
| 库数量与总磁盘上升 | 20–30 个小库，单库小但总量略增（索引重复） | 旧一级库验证通过后再 `uninit`；冷区不建库 |
| 增量同步面变多 | 但每次 `sync` 只碰改动的子库，实际更快 | `cg-build --only <子库>` 按需 |
| 规则未同步 → 静默查不到 | 最危险，不报错 | 迁移时先改规则正文再切库；`cg-route` 抽查 5 条路径 |
| 旧一级库残留 | 占磁盘、且可能被误当 `projectPath` | 验证期保留作兜底，通过后再删（`uninit` 不可逆） |
| 跨 OS 共用索引 | Windows/WSL 共用同一 `.codegraph/` 会 `disk I/O error` | 用 `CODEGRAPH_DIR` 分离 |

**回退**：`ROOTS` 改回一级目录 + `cg-roots sync`，旧一级库若未删除可立即恢复；
路由表是生成物，切换成本为一条命令。

---

## 7. 落地到 harness 的改动清单

| 文件 | 改动 | 是否需改代码 |
|---|---|---|
| `features/harness.conf` | `ROOTS` → 子库路径；`ALIASES` 清理；`EXTRA_EXCLUDE` 重写 | 否（配置） |
| `features/.harness/codegraph-roots.tsv` | `cg-roots sync` 重生成 | 否（生成物） |
| 各子库 `codegraph.json` | `cg-exclude` 按实况生成 | 建议改进按根过滤 |
| 树根规则正文 + 子目录指针 | 「projectPath = 最长前缀命中目录」+ 刷新指针 | 否（文档） |
| `skills/codegraph-nav` | 措辞同步 | 否（文档） |
| `cg-route` / `cg-assert` / `cg-build` / `feature-state` | **无需改动** | 否 |

---

## 8. 附：可直接使用的基准脚本

```bash
#!/usr/bin/env bash
# 每个子库建完后跑一遍；超红线就继续排除/再切，不要调大客户端超时
TSV=features/.harness/codegraph-roots.tsv
ROOT=$(cd "$(dirname "$TSV")/../.." && pwd -P)
awk -F'\t' '!/^#/ && NF>=5 {print $5}' "$TSV" | sort -u | while IFS= read -r r; do
  native="$(cygpath -w "$ROOT/$r" 2>/dev/null || printf '%s' "$ROOT/$r")"
  db="$ROOT/$r/.codegraph/codegraph.db"
  mb=$(( $(stat -c %s "$db" 2>/dev/null || echo 0) / 1048576 ))
  s=$(date +%s%N)
  out=$(timeout -s KILL 20 codegraph query -p "$native" -l 1 "__cg_probe__" 2>&1); rc=$?
  ms=$(( ($(date +%s%N) - s) / 1000000 ))
  printf '%-38s %6d MB  query=%6dms  rc=%s\n' "$r" "$mb" "$ms" "$rc"
done
```

验收口径：`db ≤ 512 MB`、`query < 8000ms`、`rc=0`；再对每个库实打一次
`explore`（15s 上限）和一次 MCP 工具调用。超时记 **INCOMPLETE**，不得记为通过。

---

## 9. 一句话总结

**先排除、再按耦合边界把 3 GB 级大库切成 ≤0.5 GB 的 L2/L3 子库、把 `projectPath`
纪律从「一级目录」改成「路由命中的最长前缀」，并用 `CODEGRAPH_QUERY_POOL_SIZE`/
`NO_DAEMON`/WAL 三个变量压住并发与首读长尾**——框架脚本本身几乎不用动，
改动集中在配置、排除规则和规则正文。
