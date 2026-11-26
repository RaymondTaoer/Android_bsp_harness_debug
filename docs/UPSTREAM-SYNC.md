# 上游同步与合并记录

> 更新时间：2026-11-26 17:55
> 上游源：`Y:/RK3562Android/features/.harness`（只读）
> 本地仓库：`main`
> 状态：**待合并 0 项** —— 24 项差异已于 2026-11-26 全部裁决完毕；同日 17:26–17:35 上游再更新，已二次吸收

## 摘要

| 类别 | 数量 | 处置 |
|---|---|---|
| 本次吸收上游 | 17 | 覆盖为上游版本（上游通用化或含实质修复） |
| 有意分叉（保留本地） | 7 | 本地新增功能，上游无对应内容 |
| 待人工合并 | **0** | — |

**不变式**：仓库只装框架，不装知识内容。`docs/kb/`、`debugdoc/`、`KB.md` / `KB_PLAN.md` 实例一律不入索引。

## 1. 本次吸收上游（17 项）

### 1.1 含实质改进，必须吸收

| 文件 | 上游 mtime | 改进内容 |
|---|---|---|
| `harness/bin/py-run` | 2026-11-26 17:26 | **新增脚本**。Windows 上 `python3` 可能是 MS Store 占位 shim：`command -v python3` 存在但执行即退出 49，导致 PreToolUse hook 静默失效、三条 adb 红线形同虚设。py-run 选真正可用的解释器再执行 |
| `harness/bin/adb-device-guard` | 2026-11-26 17:35 | 经 py-run 调用；支持 stdin 的 `cwd`；`grep -rn foo features 2>/dev/null` 不再被红线#2 误拦（先剥离重定向再判）；强制 UTF-8 修 cp936 乱码。自检 36/36 |
| `harness/bin/cg-exclude` | 2026-11-14 17:12 | 新增 `--prune-stale`（一级大库切子库后清残留规则）；目录扫描由「每候选各跑一次 find」改为「一次 find 收集」，SMB 网络盘 8 根从 11 分钟降到可接受；`EXTRA_EXCLUDE` 按根实况过滤 |
| `harness/bin/cg-build-server` | 2026-11-23 11:27 | 接入 `harness-lease` 双主机租约：服务器与 Windows 共享同一份 `.codegraph/`，建库串行化，租约被占时退出码 4 |
| `harness/skills/adb-device-debug/SKILL.md` | 2026-11-26 17:34 | 新增「⛔ 主机前提」（设备只连 Windows）；拦截类由 5 条扩到 **8 条**：补 `system/sepolicy` 宿主改写、无授权刷机/清数据、网络盘 git 写操作；接入示例改 py-run |
| `harness/skills/flash-verify/SKILL.md` | 2026-11-23 11:20 | 新增主机前提；`kernel-<ver>` 示例统一 |
| `harness/skills/handoff/SKILL.md` | 2026-11-23 11:28 | 新增「两端接力（服务器 ↔ Windows）」按租约交接流程；路径一律树内相对路径 |
| `harness/templates/feature-AGENTS.md` | 2026-11-14 17:12 | 新增 handoff 用法表行 + 「E. 跨会话接力」整节（本地模板缺失） |

### 1.2 上游通用化（剥离项目实例，符合分发定位）

| 文件 | 上游 mtime | 差异 |
|---|---|---|
| `harness/bin/ab-experiment` | 2026-11-14 17:12 | 注释去项目路径（`debugdoc/tools/*` → 「项目内部早期采集脚本」）；`CODESYS 容器` → `容器化控制进程` |
| `harness/bin/boot-timing` | 2026-11-14 17:12 | 同上，注释通用化 |
| `harness/bin/cg-build` | 2026-11-14 17:12 | 帮助示例 `--only kernel-5.10` → `kernel-<ver>` |
| `harness/bin/cg-ensure` | 2026-11-14 17:12 | 注释 `3.2GB` → `2–4GB`（`CG_PROBE_TIMEOUT` 逻辑两侧一致） |
| `harness/bin/cg-route` | 2026-11-14 17:12 | 错误文案「未登记的一级目录」→「未登记的路径」；`归属库（projectPath）` → `归属一级目录` |
| `harness/bin/feature-state` | 2026-11-14 17:12 | 注释 `529 仓同一分支（dis121c）` → 「几十个仓常共用同一分支」 |
| `harness/bin/flash-verify` | 2026-11-14 17:12 | 实测样例 `kernel-5.10` / `rk3562-evb2-ddr4-v10` → `kernel-<ver>` / `<vendor>,<board>` |
| `harness/bin/perf-probe` | 2026-11-14 17:12 | 注释通用化；`IRQ 45` demo 数据 `rockchip_gpio` → `gpio-intc` |
| `harness/lib/common.sh` | 2026-11-14 17:12 | **仅注释举例**：`/y/RK3562Android` → `/y/some/tree`。`canon_path()` 函数体两侧完全一致，无功能差异 |
| `harness/skills/ab-experiment/SKILL.md` | 2026-11-14 17:12 | `RK3562Android 设备` → `Android 设备`；evidence 路径去项目实例 |
| `harness/skills/boot-timing/SKILL.md` | 2026-11-14 17:12 | 同上；`RK3562 无 RTC 电池` → `开发板无 RTC 电池` |
| `harness/skills/perf-probe/SKILL.md` | 2026-11-14 17:12 | 同上；`codesyscontrol` → `目标控制进程（名字可配）` |

## 2. 有意分叉（保留本地，7 项）

这些是本地新增能力，上游没有对应内容，**不是待合并缺陷**。

| 文件 | 上游 mtime | 本地内容 |
|---|---|---|
| `harness/bin/kb-init` | 2026-11-14 17:12 | +8 行：生成 `docs/debug/resolved-ledger.tsv` 台账（L-b 层）表头 |
| `harness/kb/KB.md.template` | 2026-11-14 17:12 | +3 行台账说明；R6 改为「按落盘闸门分级落盘」 |
| `harness/kb/KB_PLAN.md.template` | 2026-11-14 17:12 | +26 行「4.4 解决台账与落盘闸门」：L-a/L-b/L-c 三层 + 闸门三问 + 台账格式 |
| `harness/skills/debugdoc-kb/SKILL.md` | 2026-11-14 17:12 | +21 行「问题落盘闸门（R6 前的强制三问）」+ 命中数→层级映射表 |
| `harness/skills/codegraph-nav/SKILL.md` | 2026-11-14 17:12 | 本地为分层建库版：L2/L3 子库、`projectPath` = 最长前缀、传一级目录静默失败、`docs/CODEGRAPH-SCALING.md`、`context-budget` / `agents-slim` 引用 |
| `harness/tests/test-harness.sh` | 2026-11-14 17:12 | 本地重写：按 shebang 过滤非 shell 脚本（python 脚本走 SKIP 而非 FAIL）；`--no-index` 下 `.codegraph` 断言改 SKIP。上游版无本地缺失的用例 |
| `harness/examples/codegraph-roots.rk3562.tsv` | 2026-11-17 12:03 | 本地为**手写样例**（41 行，带列说明）；上游为 `cg-roots sync` 生成物（40 行，`langs=unknown`）。项目实例，不随生成物覆盖 |

## 3. 未同步（白名单外或按规则排除）

| 上游路径 | 原因 |
|---|---|
| `docs/device-guard-hook.md` | 不在允许的 docs 白名单 |
| `docs/token-reduction-strategy.md` | 同上；仓库已删除对它的引用 |
| `.state/`、`.installed.tsv`、`.harness-version` | 运行时状态 |
| `bin/__pycache__/` | Python 字节码缓存 |

## 4. 仓库独有文件（保留）

`harness/bin/cg-roots`、`harness/bin/sync-skills`、`harness/bin/verify-build`、`harness/bootstrap.sh`、
`harness/docs/LEASE-PROTOCOL.md`、`docs/*`、`examples/rk3562/*`、`install.sh`、`uninstall.sh`。

## 附录：历史裁决（决策溯源）

| 日期 | 事项 | 结果 |
|---|---|---|
| 2026-11-04 | 首次「以本地为准」合并 11 项 | 全部保留本地，已落地 |
| 2026-11-24 | 同步上游 11-14/11-23 更新 | 新增 17 文件，24 项差异仅记录（`ce39706`） |
| 2026-11-26 | 24 项差异裁决 | 16 吸收上游 / 7 保留本地 / 待合并归零 |
| 2026-11-26 17:26–17:35 | 上游再次更新（py-run 安全修复、租约、8 条拦截类） | 二次吸收 3 项 + 补上遗漏的 `bin/flash-verify`；A14 同步吸收 11 项 |
| 2026-11-24 | `docs/KNOWLEDGE-BASE.md` 与 `harness/kb/*.template` 入库 | 人工核查：方法论与空骨架，无项目资料，放行 |
