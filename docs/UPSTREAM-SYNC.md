# 上游同步报告

> 生成时间：2026-11-24 15:40
> 上游源：`Y:/RK3562Android/features/.harness`（只读）
> 本地仓库：`main`
> 上游框架文件已更新至 2026-11-23（`bin/harness-doctor`、`bin/harness-lease`、`LEASE-PROTOCOL.md` 构成一组租约协议）

## 摘要

| 类别 | 数量 |
|---|---|
| 本次新增（已复制） | 17 |
| 待人工合并（内容不同，未覆盖） | 24 |
| 仓库独有（保留，未删除） | 13 |

**不变式**：仓库只装框架，不装知识内容。内容不同的文件一律不覆盖，只在此记录待人工合并。

## 1. 本次新增（已复制到仓库）

| 文件 | 上游 mtime |
|---|---|
| `harness/bin/agents-slim` | 2026-11-14 17:12 |
| `harness/bin/build-digest` | 2026-11-14 17:12 |
| `harness/bin/cg-bench` | 2026-11-14 17:12 |
| `harness/bin/cg-build-server` | 2026-11-23 11:27 |
| `harness/bin/cg-retire-old-libs.sh` | 2026-11-17 14:55 |
| `harness/bin/cg-server-rebuild.sh` | 2026-11-17 14:15 |
| `harness/bin/cg-slice` | 2026-11-14 17:12 |
| `harness/bin/context-budget` | 2026-11-14 17:12 |
| `harness/bin/handoff` | 2026-11-14 17:12 |
| `harness/bin/harness-doctor` | 2026-11-23 11:40 |
| `harness/bin/harness-lease` | 2026-11-23 11:40 |
| `harness/bin/log-digest` | 2026-11-14 17:12 |
| `harness/bin/sync-agent-rules` | 2026-11-23 11:08 |
| `harness/skills/handoff/SKILL.md` | 2026-11-23 11:28 |
| `harness/templates/root-AGENTS.md` | 2026-11-14 17:12 |
| `harness/examples/codegraph-roots.example.tsv` | 2026-11-14 17:12 |
| `harness/docs/LEASE-PROTOCOL.md` | 2026-11-23 11:40 |

- `harness/docs/LEASE-PROTOCOL.md` 由上游根目录 `LEASE-PROTOCOL.md` 收纳而来（白名单扩充，2026-11-24 人工批准）。
- `bin/__pycache__` 为 Python 字节码缓存，**不随仓库分发**，同步时已排除。

## 2. 待人工合并（内容不同，未覆盖）

以下文件上游与仓库内容不同，**本次未覆盖**。带 🔒 的属于本地增强保护文件，硬覆盖会回退功能。

### 1. `harness/bin/ab-experiment`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+4 / -3 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/bin/ab-experiment	2026-11-14 17:12:14.000000000 +0800
+++ harness/bin/ab-experiment	2026-11-17 12:13:58.782979000 +0800
@@ -1,7 +1,8 @@
 #!/usr/bin/env bash
 # features/.harness/bin/ab-experiment
-# Android 设备侧可逆 A/B 试验（合并自项目内部早期采集脚本，2026-10-30）。
-# 单一事实源：本文件 + 清单 TSV。旧实现已冻结归档，勿再改、勿再引用。
+# RK3562 / Android 设备侧可逆 A/B 试验（合并自 debugdoc/tools/boot_ab.sh、_kiosk_trim.sh、
+# _gate_ab.ps1、_l1_eval.sh，2026-10-30）。
+# 单一事实源：本文件 + 清单 TSV。debugdoc/tools 下旧实现已冻结归档，勿再改。
 #
 # 设计要点：
 #   * 清单外置为 TSV（仿 repos.tsv），工具本身不硬编码任何包名。
@@ -55,7 +56,7 @@
   apply    按清单禁用包（可逆，不删 apk）
   revert   按清单恢复启用
   verify   重启后验证：里程碑 / BC 广播 / 进程数 / PLC / 温度
-  codesys-off / codesys-on  停 / 启容器化控制进程（可选扩展）
+  codesys-off / codesys-on  停 / 启 CODESYS 容器（RK3562 项目扩展）
 
```

### 2. `harness/bin/adb-device-guard`

- 上游 mtime：`2026-11-23 11:26`
- 差异规模：+15 / -109 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/bin/adb-device-guard	2026-11-23 11:26:54.938572100 +0800
+++ harness/bin/adb-device-guard	2026-11-17 12:13:58.797500100 +0800
@@ -1,5 +1,5 @@
 #!/usr/bin/env python3
-# adb-device-guard —— 设备安全 PreToolUse 护栏
+# adb-device-guard —— RK3562 设备安全 PreToolUse 护栏
 #
 # 作用：在任何 Bash 工具执行前拦截会把整机搞挂 / brick / 卡死的命令。
 #       命中红线 → 输出 {"decision":"block","reason":"..."} 并以退出码 1 阻止执行；
@@ -7,7 +7,7 @@
 #
 # 接入（Claude Code / OpenCode）：
 #   settings.json 的 PreToolUse hook，matcher 命中 Bash，command 指向本脚本：
-#     "python3 /path/to/tree/features/.harness/bin/adb-device-guard"
+#     "python3 Y:/RK3562Android/features/.harness/bin/adb-device-guard"
 #   本脚本从 stdin 读 JSON（含 tool_input.command），仅对 Bash 类工具生效。
 #
 # 设计纪律（与 asop-harness 一致）：
@@ -21,9 +21,6 @@
 import os
```

### 3. `harness/bin/boot-timing`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+2 / -2 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/bin/boot-timing	2026-11-14 17:12:14.000000000 +0800
+++ harness/bin/boot-timing	2026-11-17 12:13:58.811920200 +0800
@@ -1,7 +1,7 @@
 #!/usr/bin/env bash
 # features/.harness/bin/boot-timing
-# Android 开机耗时测量（合并自项目内部早期计时脚本，2026-10-30）。
-# 单一事实源：本文件。旧实现已冻结归档，勿再改、勿再引用。
+# RK3562 / Android 开机耗时测量（合并自 debugdoc/tools/boot_time.sh 与 boot_measure.sh，2026-10-30）。
+# 单一事实源：本文件。debugdoc/tools 下两个旧实现已冻结归档，勿再改。
 #
 # 测量口径（t=0 = 内核启动，全部为实测锚点，不靠估算）：
 #   base      = boot_progress_start 的 wall time − 它的 ms 值
```

### 4. `harness/bin/cg-build`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+1 / -1 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/bin/cg-build	2026-11-14 17:12:14.000000000 +0800
+++ harness/bin/cg-build	2026-11-17 12:13:58.845031100 +0800
@@ -17,7 +17,7 @@
 #   cg-build                 处理所有根
 #   cg-build --dry-run       只打印将要执行的命令
 #   cg-build --force         强制全量重建（codegraph index）
-#   cg-build --only kernel-<ver> --only frameworks
+#   cg-build --only kernel-5.10 --only frameworks
 #   cg-build --sync-only     只做增量，未初始化的根跳过（CI 用）
 #
 # 退出码：0 全部成功；1 有根失败；2 参数/配置错误；3 codegraph 不可用
```

### 5. `harness/bin/cg-ensure` 🔒

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+1 / -1 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/bin/cg-ensure	2026-11-14 17:12:14.000000000 +0800
+++ harness/bin/cg-ensure	2026-11-17 12:13:58.857889700 +0800
@@ -155,7 +155,7 @@
 fi
 
 # ---- 4. 已建库可用性（真打一次查询）--------------------------------------
-# 【实测】kernel 级库（2–4GB）上 `codegraph query` 单次可能 >90s；
+# 【实测】kernel 级库（3.2GB）上 `codegraph query` 单次可能 >90s；
 # 无超时会让人以为"检查卡死"。超时记 SKIP（结论不可判定），既不假绿也不误判为坏库。
 probe_timeout="${CG_PROBE_TIMEOUT:-${CODEGRAPH_PROBE_TIMEOUT:-60}}"
 have_timeout=0
```

### 6. `harness/bin/cg-exclude`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+16 / -70 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/bin/cg-exclude	2026-11-14 17:12:14.000000000 +0800
+++ harness/bin/cg-exclude	2026-11-17 12:13:58.870095100 +0800
@@ -6,17 +6,12 @@
 # 有的把 tests 平铺在顶层）。这里先扫描，再只写"确实存在"的条目 —— 写不存在的
 # 排除项会让配置看起来像生效了，实际什么都没挡住。
 #
-# EXTRA_EXCLUDE 同样按根实况过滤（arch/* 这类裁剪只写进真有该路径的根）。
-# 目录扫描一次 find 完成，网络盘上比逐候选扫描快一个数量级。
-#
 # 用法：
 #   cg-exclude                处理 harness.conf 里所有已存在的根
 #   cg-exclude <root>...      只处理指定根
 #   cg-exclude --dry-run      只打印将写入的内容
 #   cg-exclude --deep         全量遍历（慢；默认只看 3 层目录 / 4 层文件）
 #   cg-exclude --force        已存在 codegraph.json 且含其它键时强制覆盖（先备份）
-#   cg-exclude --prune-stale  合并旧 exclude 时，剔除该根下已不存在的路径规则
-#                             （从一级大库切到子库后用它清掉残留的 arch/* 之类规则）
 #
 # 退出码：0 全部成功（含"无需改动"）；1 有根失败；2 配置错误
 set -uo pipefail
```

### 7. `harness/bin/cg-route`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+2 / -2 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/bin/cg-route	2026-11-14 17:12:14.000000000 +0800
+++ harness/bin/cg-route	2026-11-17 12:13:58.892401800 +0800
@@ -49,7 +49,7 @@
   0) : ;;
   3) echo "error: 目标是源码树根，不属于任何一级根；请指定具体一级目录或子路径" >&2; exit 1 ;;
   2) echo "error: 路由表缺失 $ROOTS_TSV" >&2; exit 2 ;;
-  *) echo "error: 未登记的路径（不属于任何已登记库）：$target" >&2
+  *) echo "error: 未登记的一级目录：$target" >&2
      echo "       已登记：$(awk -F'\t' '!/^#/ && NF>=5 {printf "%s ", $1}' "$ROOTS_TSV" 2>/dev/null)" >&2
      exit 1 ;;
 esac
@@ -68,7 +68,7 @@
 native_root="$(to_native "$HARNESS_ROOT/$db_root")"
 
 cat <<EOF
-归属库（projectPath 目录）：$root
+归属一级目录：$root
 mcp_server:  codegraph（唯一 server；不是按根拆分的 server）
 mcp_arg:     projectPath=$native_root
 mcp_tools:   codegraph_explore | codegraph_search | codegraph_node | codegraph_callers | codegraph_callees | codegraph_impact
```

### 8. `harness/bin/feature-state`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+1 / -1 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/bin/feature-state	2026-11-14 17:12:14.000000000 +0800
+++ harness/bin/feature-state	2026-11-17 12:13:58.907531800 +0800
@@ -2,7 +2,7 @@
 # features/.harness/bin/feature-state
 # feature 基线管理：capture / show / list。
 #
-# 为什么不用分支名：全树几十个仓常共用同一分支，per-feature 分支往往不存在。
+# 为什么不用分支名：全树 529 仓同一分支（dis121c），per-feature 分支不存在。
 # 因此基线记录"**最后一次触及该路径的提交**"：
 #   - 目录自己是独立 git 仓 -> scope=repo，record = HEAD
 #   - 目录只是根仓的一部分 -> scope=path，record = 最近一次改动该路径的提交
```

### 9. `harness/bin/flash-verify`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+3 / -7 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/bin/flash-verify	2026-11-14 17:12:14.000000000 +0800
+++ harness/bin/flash-verify	2026-11-17 12:13:58.933404800 +0800
@@ -4,7 +4,7 @@
 #
 # 为什么需要：DTS/C 改动后最常见的假失败，是"改了、编了，但设备跑的是旧产物"。
 # 实测样例（2026-10-30）：
-#   本地 kernel-<ver>/arch/arm64/boot/Image  = #2 SMP PREEMPT ...
+#   本地 kernel-5.10/arch/arm64/boot/Image  = #2 SMP PREEMPT Fri Oct 30 11:16:14 CST 2026
 #   设备 /proc/version                      = #1 SMP PREEMPT Thu Oct 29 14:38:52 CST 2026
 #   -> 单看功能现象会误判成"补丁无效"，实际只是没刷。
 #
@@ -21,7 +21,7 @@
 #
 #   <node> 为设备树节点路径（可空或 "/" 表示根节点），<prop> 为属性名：
 #     --expect '/soc/ethernet@ffa80000:status=okay'
-#     --expect ':compatible=<vendor>,<board> <vendor>,<soc>'
+#     --expect ':compatible=rockchip,rk3562-evb2-ddr4-v10 rockchip,rk3562'
 #
 # 退出码：0 PASS；1 FAIL；3 INCOMPLETE（环境未就绪：无设备/无产物）
 set -uo pipefail
```

### 10. `harness/bin/kb-init`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+7 / -0 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/bin/kb-init	2026-11-14 17:12:14.000000000 +0800
+++ harness/bin/kb-init	2026-11-17 12:13:59.495359700 +0800
@@ -121,6 +121,14 @@
 EOF
 )"
 
+# ---- 解决台账（L-b 层：一行一问题，rg 快查；层级与闸门三问见 KB_PLAN 4.4）----
+# 表头行用真实 TAB 分隔（printf 生成，避免 heredoc 里 TAB 被编辑器改写成空格）。
+put "docs/debug/resolved-ledger.tsv" "$(cat <<'EOF'
+# 解决台账 resolved-ledger —— 一行一问题，rg 症状关键词快查；完整排查文档见同目录 *.md
+# 追加前先 rg 去重；落盘层级与闸门三问见 KB_PLAN.md 4.4；TAB 分隔 5 列。
+EOF
+)$(printf 'date\t症状/签名\t根因一句话\t修法\t关联(文件/文档)')"
+
 # ---- 内容仓目录 ----
 for d in "${DOCS_DIRS[@]}"; do
   put "docs/$d/README.md" "$(render "$KB_SRC/CATEGORY.md.template" "$d" "${PURPOSE[$d]}")"
```

### 11. `harness/bin/perf-probe`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+4 / -4 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/bin/perf-probe	2026-11-14 17:12:14.000000000 +0800
+++ harness/bin/perf-probe	2026-11-17 12:13:58.944004500 +0800
@@ -1,7 +1,7 @@
 #!/usr/bin/env bash
 # features/.harness/bin/perf-probe
-# Android 性能 / 温度 / 中断采样分析（合并自项目内部早期采样脚本，2026-10-30）。
-# 单一事实源：本文件。旧实现已冻结归档，勿再改、勿再引用。
+# RK3562 性能 / 温度 / 中断采样分析（合并自 debugdoc/tools 7 个采样脚本，2026-10-30）。
+# 单一事实源：本文件。debugdoc/tools 下旧实现已冻结归档，勿再改、勿再引用。
 #
 # 合并来源（旧 → 新）：
 #   probe   ← cpu_thermal_probe.sh（_cpu_sample.sh 被完全覆盖，不保留）
@@ -660,7 +660,7 @@
 PLCPID 994
 IRQ 12: 100 200 300 400  GICv3 27 arch_timer
 IRQ 30: 10 20 30 40  GICv3 133 eth0
-IRQ 45: 5 5 5 5  gpio-intc 25 gpio_keys
+IRQ 45: 5 5 5 5  rockchip_gpio 25 gpio_keys
 IRQ IPI0: 50 60 70 80  IPI
 UPTIME 3612.45
```

### 12. `harness/lib/common.sh` 🔒

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+4 / -4 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/lib/common.sh	2026-11-14 17:12:14.000000000 +0800
+++ harness/lib/common.sh	2026-11-17 12:13:58.987166500 +0800
@@ -44,12 +44,12 @@
 # 物理路径归一化（**两边都要过这一关**）。
 #
 # 【坑，实测踩过两次】Git Bash / MSYS 下同一目录有多种写法，且 `cd` 会"记住"你进门的写法：
-#   /y/some/tree            ==  Y:/some/tree
+#   /y/RK3562Android        ==  Y:/RK3562Android
 #   /tmp/x                  ==  C:/Users/<u>/AppData/Local/Temp/x
 # `cd C:\...\Temp/x && pwd -P`  ->  /tmp/x
 # `cd /c/Users/.../Temp/x && pwd -P` -> /c/Users/.../Temp/x   （同一目录，两种输出）
 # 只用 to_msys 或只用 cd+pwd -P 都会让「树根」和「入参」落到不同分支 → 前缀永不匹配 →
-# 报「未登记的路径：<自己树里的路径>」。
+# 报「未登记的一级目录：<自己树里的路径>」。
 #
 # 解法：用 cygpath -w（POSIX→Windows）再 to_msys 回到 /c/... 形式，两个方向都收敛到同一写法。
 # 没有 cygpath（Linux/macOS）时退化为 to_msys，行为不变。
@@ -276,9 +276,9 @@
 
 # ---- 变量初始化必须放在函数定义之后 ----
```

### 13. `harness/kb/KB.md.template`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+4 / -0 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/kb/KB.md.template	2026-11-14 17:12:14.000000000 +0800
+++ harness/kb/KB.md.template	2026-11-17 12:13:59.512290000 +0800
@@ -27,6 +27,9 @@
 | 官方 PDF 文档 | rkdocs | `index/rkdocs.md` |
 | 源码符号/调用链 | （走规则正文） | codegraph MCP，见树根规则正文 |
 
+- **解决台账**：`docs/debug/resolved-ledger.tsv`（一行一问题，TAB 分 5 列）。
+  查「某问题当年怎么修的」先 `rg` 台账再翻全文；追加前去重，层级与闸门见 `KB_PLAN.md` 4.4。
+
 ## 3. 披露协议（强制）
 - **R0** 只读本文件。
 - **R1** 任务→类别→只读命中类别 1–2 个 L1 索引（单文件 ≤5KB）。
@@ -34,7 +37,8 @@
 - **R3** 读候选文档头部摘要（L2）后，再决定读全文（L3）。
 - **R4** md 按节读；PDF 先转 md 落盘 `docs/rkdocs-md/` 再读；媒体证据按需单文件。
 - **R5** 单任务预算 ≤50K tokens（L0+L1 ≤3K，L2 ≤5K）；超限先出摘要再问。
-- **R6** 结论必须引用来源（相对路径 / [ID] / `RKDocs:<路径>`）；新结论落盘 `docs/` 对应类别。
+- **R6** 结论必须引用来源（相对路径 / [ID] / `RKDocs:<路径>`）；新结论按**落盘闸门**
+  （闸门三问，见 `KB_PLAN.md` 4.4）分级落盘：≥2 条写全文、1 条记台账、0 条只留 git + handoff。
 - **R7** 索引无条目即如实说明，禁止臆测文档内容。
```

### 14. `harness/kb/KB_PLAN.md.template`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+20 / -0 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/kb/KB_PLAN.md.template	2026-11-14 17:12:14.000000000 +0800
+++ harness/kb/KB_PLAN.md.template	2026-11-17 12:13:59.516825200 +0800
@@ -133,6 +133,32 @@
 - 引用格式：`[D-0001]`、`[P-0001]`、`[S-0001]`、`RKDocs:<相对路径>`、`debugdoc/docs/debug/xxx.md`。
 - **结论必须带来源引用**；索引/摘要无此条目时明确说「索引无此条目」，禁止臆测文档内容。
 
+### 4.4 解决台账与落盘闸门（防止索引被淹没）
+
+**不是每个已解决的问题都要写成完整文档。** 全部自动落盘有三个代价：
+L1 索引超预算（单索引 ≤5KB）、低复发问题成为噪声、以及把没有四段证据的
+「已解决」写成看似权威的记录（违反诚实性铁律）。按三层分级：
+
+| 层级 | 载体 | 适用 |
+|---|---|---|
+| L-a 默认层 | git 提交信息 + `handoff` 接力卡 | 一次性、低复发问题（不进知识库） |
+| L-b 台账层 | `docs/debug/resolved-ledger.tsv`（一行一问题） | 根因或修法值得记，但不需要全文 |
+| L-c 文档层 | 完整排查文档（4.1 命名 + 4.2 头部） | 闸门三问命中 ≥2 条 |
+
+**闸门三问**（写 L-b / L-c 前逐条判断）：
+1. **根因非显而易见？** 隔着协议层 / 构建系统 / 时序，一眼看不出；
```

### 15. `harness/templates/feature-AGENTS.md`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+0 / -7 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/templates/feature-AGENTS.md	2026-11-14 17:12:14.000000000 +0800
+++ harness/templates/feature-AGENTS.md	2026-11-17 12:13:59.137708800 +0800
@@ -41,8 +41,6 @@
 | 要上机部署/验收 | skill `deploy-and-accept`（需显式授权 + `ANDROID_SERIAL`） |
 | 写源码前 | `bash features/.harness/bin/check-drift <FEATURE>` |
 | 交付前 | `bash features/<FEATURE>/verify-<FEATURE>.sh` |
-| 会话开始接续上一轮 | `bash features/.harness/bin/handoff show <FEATURE>`（skill `handoff`） |
-| 一轮收尾 / 上下文将满 | `bash features/.harness/bin/handoff new <FEATURE> --note … --blocker … --next …` + `handoff check` |
 
 ## D. 证据与终结
 
@@ -72,12 +70,3 @@
 2. 指标列找不到、值为空或 `NA` → 输出 `SKIP`（数据不可判定），不当成满足阈值；
 3. 指标名容忍单位后缀：`foo` 与 `foo_s` / `foo_ms` 等价；
 4. `--demo` 生成的 CSV 只能证明链路通，**不得**作为验收证据。
-
----
-
-## E. 跨会话接力
-
```

### 16. `harness/skills/ab-experiment/SKILL.md`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+7 / -6 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/skills/ab-experiment/SKILL.md	2026-11-14 17:12:14.000000000 +0800
+++ harness/skills/ab-experiment/SKILL.md	2026-11-17 12:13:59.023021400 +0800
@@ -1,6 +1,6 @@
 ---
 name: ab-experiment
-description: 在 Android 设备上做可逆的 A/B 试验 —— 按包清单批量禁用/恢复应用，量开机时序对比，验证裁剪效果与故障假设。用于"禁用哪些包能缩短开机""这个崩溃是不是某包引起的""裁剪后 T3 改善了多少"这类问题。当需要修改设备状态（pm disable-user / pm enable / setprop / 停启容器）并需要留证据时使用。
+description: 在 RK3562Android 设备上做可逆的 A/B 试验 —— 按包清单批量禁用/恢复应用，量开机时序对比，验证裁剪效果与故障假设。用于"禁用哪些包能缩短开机""这个崩溃是不是某包引起的""裁剪后 T3 改善了多少"这类问题。当需要修改设备状态（pm disable-user / pm enable / setprop / 停启容器）并需要留证据时使用。
 ---
 
 # ab-experiment：设备侧可逆 A/B 试验
@@ -9,7 +9,7 @@
 
 - 在**真机**上批量禁用/恢复应用包，测量开机时序变化
 - 验证某个包是否为故障源（如 system_server 崩溃循环）
-- 容器化控制进程停/启的 A/B（可选扩展）
+- CODESYS 容器停/启的 A/B（RK3562 项目扩展）
 
 **不适用**：编译、刷机、root 提权、永久删除 APK、`pm uninstall`、修改 `/system` 分区。
 
@@ -43,13 +43,13 @@
```

### 17. `harness/skills/adb-device-debug/SKILL.md`

- 上游 mtime：`2026-11-23 11:20`
- 差异规模：+7 / -9 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/skills/adb-device-debug/SKILL.md	2026-11-23 11:20:13.517642100 +0800
+++ harness/skills/adb-device-debug/SKILL.md	2026-11-17 12:13:59.036047400 +0800
@@ -1,22 +1,15 @@
 ---
 name: adb-device-debug
-description: 通过 adb 对已连接的 Android 设备做只读取证/调试时的统一要求（序列号纪律、三条会把整机搞挂的红线、Git Bash 路径改写与 CRLF 陷阱、批量合并与脚本化、常用取证命令模板）。用于任何 adb 探测、日志取证、上机验证、现象复现的场合。
+description: 通过 adb 对已连接的 RK3562 设备做只读取证/调试时的统一要求（序列号纪律、三条会把整机搞挂的红线、Git Bash 路径改写与 CRLF 陷阱、批量合并与脚本化、常用取证命令模板）。用于任何 adb 探测、日志取证、上机验证、现象复现的场合。
 ---
 
-# adb 设备调试要求
+# adb 设备调试要求（RK3562）
 
 ## 何时用
 
 任何通过 adb 接触已连接设备的时候：取证、复现、验证、抓日志、读寄存器/GPIO。
 **目的**：把历史上真实搞挂过整机、以及大量返工的命令写法固化成硬规则。
 
-## ⛔ 主机前提（先判，2026-11-23 用户明确）
-
-- **设备只连在 Windows 端**；Linux 源码服务器不能、也不允许用 adb 调试。
```

### 18. `harness/skills/boot-timing/SKILL.md`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+9 / -5 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/skills/boot-timing/SKILL.md	2026-11-14 17:12:14.000000000 +0800
+++ harness/skills/boot-timing/SKILL.md	2026-11-17 12:13:59.060267500 +0800
@@ -1,12 +1,12 @@
 ---
 name: boot-timing
-description: Android 开机耗时测量与冷启动 A/B 对比（T1 首帧 / T2 就绪 / T3 末进程 / T4 真实空闲、boot_progress 里程碑、BC 广播拖尾归因）。用于"量开机时间""测 T1/T2/T3""冷启动对比""boot 时序""开机慢归因"这类测量场景；判定验收结论不使用本 skill（那是 verify 的事）。
+description: RK3562/Android 开机耗时测量与冷启动 A/B 对比（T1 首帧 / T2 就绪 / T3 末进程 / T4 真实空闲、boot_progress 里程碑、BC 广播拖尾归因）。用于"量开机时间""测 T1/T2/T3""冷启动对比""boot 时序""开机慢归因"这类测量场景；判定验收结论不使用本 skill（那是 verify 的事）。
 ---
 
-# boot-timing —— 开机耗时测量
+# boot-timing —— 开机耗时测量（RK3562）
 
-单一事实源：`features/.harness/bin/boot-timing`（合并自项目内部早期计时脚本，2026-10-30）。
-旧实现**已冻结归档**，勿再改、勿再引用。
+单一事实源：`features/.harness/bin/boot-timing`（合并自 `debugdoc/tools/boot_time.sh` 与 `boot_measure.sh`，2026-10-30）。
+debugdoc 下两个旧实现**已冻结归档**，勿再改、勿再引用。
 
 ## 适用范围
 
@@ -68,7 +68,7 @@
```

### 19. `harness/skills/codegraph-nav/SKILL.md`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+32 / -63 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/skills/codegraph-nav/SKILL.md	2026-11-14 17:12:14.000000000 +0800
+++ harness/skills/codegraph-nav/SKILL.md	2026-11-17 12:13:59.071269400 +0800
@@ -1,6 +1,6 @@
 ---
 name: codegraph-nav
-description: 在一棵树被切成多个隔离 codegraph 库的 BSP/Android 源码里定位与检索代码。用于"这个符号在哪、谁调用它、改动影响面多大"这类结构性问题，以及需要判断该用哪个子库、该不该回退 ripgrep 的场景。
+description: 在一棵树被切成多个隔离 codegraph 库的 BSP/Android 源码里定位与检索代码。用于"这个符号在哪、谁调用它、改动影响面多大"这类结构性问题，以及需要判断该用哪个一级根、该不该回退 ripgrep 的场景。
 ---
 
 # codegraph 检索与路由
@@ -8,44 +8,34 @@
 ## 适用范围
 
 - 目标文件位于**已安装 harness 的源码树**之下的**代码检索、调用链、引用、影响面**分析；
-- 树的库清单不写死，**永远以路由表为准**：
+- 树的根清单不写死，**永远以路由表为准**：
 
   ```bash
-  bash features/.harness/bin/cg-route --list    # 已登记的库 + 库路径
+  bash features/.harness/bin/cg-route --list    # 已登记的根 + 库路径
```

### 20. `harness/skills/debugdoc-kb/SKILL.md`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+20 / -1 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/skills/debugdoc-kb/SKILL.md	2026-11-14 17:12:14.000000000 +0800
+++ harness/skills/debugdoc-kb/SKILL.md	2026-11-17 12:13:59.534247800 +0800
@@ -31,13 +31,35 @@
 | R3 | 先读候选文档 L2 头部摘要 | 不跳过摘要直接读全文 |
 | R4 | md 按节读；PDF 先转 md 再定向抽取 | 禁止 PDF 整本加载；单次 ≤5K tokens |
 | R5 | 单任务 ≤50K tokens（L0+L1 ≤3K，L2 ≤5K） | 超预算先出摘要再问 |
-| R6 | 结论引用来源；新结论按命名规范落盘 | 引用 = 相对路径 / `[D-xxxx]` / `RKDocs:<路径>` |
+| R6 | 结论引用来源；新结论按**落盘闸门**分级落盘（见下节） | 引用 = 相对路径 / `[D-xxxx]` / `RKDocs:<路径>` |
 | R7 | 索引无条目即如实说明 | 禁止臆测文档内容 |
 
 类别路由（L1 文件）：`schematics` / `manuals` / `eval` / `plan` / `debug` /
 `patch` / `scripts` / `evidence` / `raw` / `rkdocs`，对应
 `debugdoc/index/debugdoc-<类>.md`（官方 PDF 为 `index/rkdocs.md`）。
 
+## 问题落盘闸门（R6 落盘前的强制三问）
+
+**不是每个已解决的问题都要写成完整文档。** 全部自动落盘会淹没 L1 索引预算
+（单索引 ≤5KB），也会把没有证据支撑的「已解决」写成看似权威的记录。
+R6 落盘前先过**闸门三问**：
+
```

### 21. `harness/skills/flash-verify/SKILL.md`

- 上游 mtime：`2026-11-23 11:20`
- 差异规模：+8 / -8 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/skills/flash-verify/SKILL.md	2026-11-23 11:20:21.409597500 +0800
+++ harness/skills/flash-verify/SKILL.md	2026-11-17 12:13:59.099132100 +0800
@@ -3,17 +3,15 @@
 description: 在拿设备功能现象下结论之前，证明"设备上跑的确实是本次构建的产物"（本地 Image ↔ boot.img ↔ 设备 /proc/version ↔ 设备 DTB 属性回读）。用于改动 kernel/DTS/init.rc/sepolicy 后上机验证、或现象与预期不符时先排除"没刷/刷了旧的/没重打包"。
 ---
 
-# 刷机产物身份判定
-
-> ⛔ **主机前提**：设备只连在 Windows 端。Linux 源码服务器无 adb，`flash-verify` 只能在 Windows 上跑；在服务器上先 `command -v adb`，缺失就停止并提示切到 Windows 会话（`adb-device-guard` 也会拦截）。
+# 刷机产物身份判定（RK3562）
 
 ## 为什么必须做
 
 最贵的返工不是改错代码，而是**拿旧产物判断新补丁**。实测（2026-10-30）：
 
 ```
-本地 kernel-<ver>/arch/arm64/boot/Image : #2 SMP PREEMPT ...
-设备 /proc/version                     : #1 SMP PREEMPT ...
+本地 kernel-5.10/arch/arm64/boot/Image : #2 SMP PREEMPT Fri Oct 30 11:16:14 CST 2026
+设备 /proc/version                     : #1 SMP PREEMPT Thu Oct 29 14:38:52 CST 2026
```

### 22. `harness/skills/perf-probe/SKILL.md`

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+10 / -5 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/skills/perf-probe/SKILL.md	2026-11-14 17:12:14.000000000 +0800
+++ harness/skills/perf-probe/SKILL.md	2026-11-17 12:13:59.111066000 +0800
@@ -1,12 +1,14 @@
 ---
 name: perf-probe
-description: Android 性能/温度/中断/常驻进程占用采样与分析（probe 一体化、snap 快照、rank 进程排名、threads 线程细分、irq 中断、trend 趋势 CSV）。用于"看 CPU 占用""温度多少""谁在吃 CPU""中断多少""控制进程负载""降频没"这类采样场景；判定验收结论不使用本 skill（那是 verify 的事）。
+description: RK3562 性能/温度/中断/PLC 占用采样与分析（probe 一体化、snap 快照、rank 进程排名、threads PLC 线程、irq 中断、trend 趋势 CSV）。用于"看 CPU 占用""温度多少""谁在吃 CPU""中断多少""PLC 负载""降频没"这类采样场景；判定验收结论不使用本 skill（那是 verify 的事）。
 ---
 
-# perf-probe —— 性能/温度/中断采样分析
+# perf-probe —— 性能/温度/中断采样分析（RK3562）
 
-单一事实源：`features/.harness/bin/perf-probe`（合并自项目内部早期采样脚本，2026-10-30）。
-旧实现**已冻结归档**，勿再改、勿再引用。
+单一事实源：`features/.harness/bin/perf-probe`（合并自 `debugdoc/tools` 7 个采样脚本，2026-10-30：
+`cpu_thermal_probe.sh` `_sys_snapshot.sh` `_proc_rank.sh` `_thread_rank.sh` `_irq_top.sh`
+`_temp_trend.sh` `_cpu_sample.sh`）。
+debugdoc 下旧实现**已冻结归档**，勿再改、勿再引用。
 
 ## 适用范围
```

### 23. `harness/tests/test-harness.sh` 🔒

- 上游 mtime：`2026-11-14 17:12`
- 差异规模：+1 / -178 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/tests/test-harness.sh	2026-11-14 17:12:14.000000000 +0800
+++ harness/tests/test-harness.sh	2026-11-17 12:13:59.152094400 +0800
@@ -438,221 +438,7 @@
 # =============================================================================
 echo
 echo "=============================================================="
-echo " 10. log-digest / build-digest（日志摄入压缩）"
-echo "=============================================================="
-
-LOGD="$WORK/logs"; mkdir -p "$LOGD"
-{
-  for i in 1 2 3; do
-    printf '11-14 10:00:0%s.000  1001  1001 E AndroidRuntime: FATAL EXCEPTION: main\n' "$i"
-    printf '11-14 10:00:0%s.001  1001  1001 E AndroidRuntime: \tat com.dl.car.MainActivity.onCreate(MainActivity.java:12%s)\n' "$i" "$i"
-  done
-  for i in 1 2; do
-    printf "11-14 10:00:1%s.000  2002  2002 E lowmemorykiller: Kill 'com.x' (1), uid 1000, oom_score_adj 900 to free 8192kB\n" "$i"
-  done
-  printf '[   12.000000] Unable to handle kernel NULL pointer dereference at virtual address 0000000000000018\n'
-} > "$LOGD/boot.log"
```

### 24. `harness/examples/codegraph-roots.rk3562.tsv`

- 上游 mtime：`2026-11-17 12:03`
- 差异规模：+40 / -39 行（`-` = 仓库独有，`+` = 上游独有）
- 差异摘要（`diff -u` 前 20 行）：

```diff
--- /y/RK3562Android/features/.harness/codegraph-roots.tsv	2026-11-17 12:03:29.729498300 +0800
+++ harness/examples/codegraph-roots.rk3562.tsv	2026-11-17 12:13:58.974672700 +0800
@@ -1,40 +1,41 @@
-# 本文件由 cg-roots sync 生成，勿手改（改 features/harness.conf 后重新生成）
+# features/.harness/codegraph-roots.tsv —— 唯一路由事实源
 # 列：dir<TAB>tag<TAB>db_rel<TAB>langs<TAB>db_root
-# langs 为 unknown 时跑 cg-assert langs <root> 实测；或 cg-roots sync --langs
-#dir	tag	db_rel	langs	db_root
-kernel-5.10/drivers/gpu	kernel-5.10	kernel-5.10/drivers/gpu/.codegraph	unknown	kernel-5.10/drivers/gpu
-kernel-5.10/drivers/net	kernel-5.10	kernel-5.10/drivers/net/.codegraph	unknown	kernel-5.10/drivers/net
-kernel-5.10/drivers/media	kernel-5.10	kernel-5.10/drivers/media/.codegraph	unknown	kernel-5.10/drivers/media
-kernel-5.10/drivers/clk	kernel-5.10	kernel-5.10/drivers/clk/.codegraph	unknown	kernel-5.10/drivers/clk
-kernel-5.10/drivers/usb	kernel-5.10	kernel-5.10/drivers/usb/.codegraph	unknown	kernel-5.10/drivers/usb
-kernel-5.10/drivers/input	kernel-5.10	kernel-5.10/drivers/input/.codegraph	unknown	kernel-5.10/drivers/input
-kernel-5.10/drivers/video	kernel-5.10	kernel-5.10/drivers/video/.codegraph	unknown	kernel-5.10/drivers/video
-kernel-5.10/drivers/iio	kernel-5.10	kernel-5.10/drivers/iio/.codegraph	unknown	kernel-5.10/drivers/iio
-kernel-5.10/drivers/misc	kernel-5.10	kernel-5.10/drivers/misc/.codegraph	unknown	kernel-5.10/drivers/misc
-kernel-5.10/drivers/pinctrl	kernel-5.10	kernel-5.10/drivers/pinctrl/.codegraph	unknown	kernel-5.10/drivers/pinctrl
-kernel-5.10/drivers/tty	kernel-5.10	kernel-5.10/drivers/tty/.codegraph	unknown	kernel-5.10/drivers/tty
-kernel-5.10/drivers/gpio	kernel-5.10	kernel-5.10/drivers/gpio/.codegraph	unknown	kernel-5.10/drivers/gpio
```

## 3. 有意分叉说明

以下分叉已在此前人工裁决中确认，**不是待合并缺陷**，保留本地版本：

| 文件 | 分叉原因 |
|---|---|
| `harness/lib/common.sh` 🔒 | `canon_path()`：Git Bash 下 `Y:/` 与 `/y/`、`C:/.../Temp` 与 `/tmp` 路径收敛；缺失会导致全部路由失败 |
| `harness/tests/test-harness.sh` 🔒 | 按 shebang 过滤非 shell 脚本；`--no-index` 下 `.codegraph` 断言改 SKIP |
| `harness/bin/check-drift` | 已与上游一致（上游采纳了本地 `.drift-ignore` 支持），本次为 SAME |
| `harness/bin/cg-ensure` 🔒 | 探活 `CG_PROBE_TIMEOUT` 超时 + workbuddy/codex 客户端识别 |
| `harness/skills/codegraph-nav/SKILL.md` | 去掉硬编码项目路径，改为通用描述 |
| `harness/skills/boot-timing/SKILL.md` | 删除指向不随仓库分发的 `token-reduction-strategy.md` 死链 |

## 4. 未同步（白名单外或按规则排除）

| 上游路径 | 原因 |
|---|---|
| `docs/device-guard-hook.md` | 不在允许的 docs 白名单（仅 DESIGN / CODEGRAPH / TROUBLESHOOTING / UPSTREAM-SYNC） |
| `docs/token-reduction-strategy.md` | 同上；仓库已删除对它的引用 |
| `.state/`、`.installed.tsv`、`.harness-version` | 运行时状态，按规则不同步 |
| `bin/__pycache__/` | Python 字节码缓存 |
| `codegraph-roots.tsv` 的项目实例内容 | 仓库保留 `harness/examples/codegraph-roots.rk3562.tsv`，上游通配版本不覆盖（见第 2 节） |

## 5. 仓库独有文件（保留）

`harness/bin/cg-roots`、`harness/bin/sync-skills`、`harness/bin/verify-build`、`harness/bootstrap.sh`、
`harness/examples/codegraph-roots.rk3562.tsv`、`docs/*`、`examples/rk3562/*`、`install.sh`、`uninstall.sh`。

## 附录：2026-11-04 合并明细（历史）

首次「以本地为准」合并时的 11 项裁决，现已全部落地，保留作为决策溯源：

1. `bin/ab-experiment` — 保留本地
2. `bin/cg-assert` — 保留本地
3. `bin/check-drift` — 保留本地（`.drift-ignore`）
4. `bin/feature-state` — 保留本地
5. `bin/prepare-feature` — 保留本地
6. `lib/common.sh` — 保留本地（`canon_path`）
7. `skills/ab-experiment` — 保留本地
8. `skills/boot-timing` — 保留本地（删死链）
9. `skills/codegraph-nav` — 保留本地（去硬编码）
10. `skills/deploy-and-accept` — 保留本地（通用化）
11. `tests/test-harness.sh` — 保留本地（shebang 过滤）
