# 上游 harness 同步差异报告

- 生成时间：2026-11-02 08:40:48 +0800
- 上游源：`Y:\RK3562Android\features\.harness`（只读，禁止写入）
- 本地仓库：`D:\workspace\user\android_bsp_harness`
- 本次同步：仅复制**新增**文件；内容不同的文件一律**未覆盖**，全部列在下方等人工合并。
- 差异方向：`- ` = 上游内容，`+ ` = 本地内容。
- 标记 **【受保护】** 的文件属本地增强（本地有独立修复），硬覆盖会回退功能，合并时请保留本地实现。

## 本次同步前已做的本地修复（非上游内容）

`harness/tests/test-harness.sh` 原先对 `*/bin/*` 下所有文件无条件执行 `bash -n` 与 shellcheck，
而上游新增的 `harness/bin/adb-device-guard` 是 python3 脚本（174 行），必然报语法错误。
已新增 `is_shell_script()`：按首行 shebang 判定，非 shell 实现跳过 `bash -n` 并记 SKIP；
shellcheck 同样只对 shell 脚本执行。合并上游测试脚本时请保留该函数及其调用点。

## 待合并差异清单（共 11 项）

1. `harness/bin/ab-experiment`
2. `harness/bin/cg-assert`
3. `harness/bin/check-drift`
4. `harness/bin/feature-state`
5. `harness/bin/prepare-feature`
6. `harness/lib/common.sh`
7. `harness/skills/ab-experiment/SKILL.md`
8. `harness/skills/boot-timing/SKILL.md`
9. `harness/skills/codegraph-nav/SKILL.md`
10. `harness/skills/deploy-and-accept/SKILL.md`
11. `harness/tests/test-harness.sh`

## 明细

### `harness/bin/ab-experiment`

- 上游 mtime：2026-10-31 10:39:24
- 本地 mtime：2026-10-30 11:43:18
- 状态：上游较新（本地 2026-10-30 11:43:18）—— 未覆盖，待人工合并

<details><summary>差异摘要（diff -u 前 20 行）</summary>

```diff
--- /y/RK3562Android/features/.harness/bin/ab-experiment	2026-10-31 10:39:24.500526000 +0800
+++ /d/workspace/user/android_bsp_harness/harness/bin/ab-experiment	2026-10-30 11:43:18.979735300 +0800
@@ -206,18 +206,10 @@
     warn "过滤后清单为空，未做任何修改"
     return 1
   fi
-  local ok=0 skip=0 miss=0 blocked=0
+  local ok=0 skip=0 miss=0
   for row in "${FILTERED_ROWS[@]}"; do
     IFS=$'\t' read -r g p r <<< "$row"
     [[ -z "$p" ]] && continue
-    # 系统硬依赖黑名单：PMS/SystemServer 启动期硬性要求，禁用必致 bootloop。
-    # 2026-10-31 因 com.android.sdksandbox 入清单实测 brick 设备，已修复。
-    # 即使清单误含这些包，apply 也只计入 skip 并拦截，绝不真正 disable。
-    case "$p" in
-      com.android.sdksandbox|com.android.systemui|com.android.launcher3|\
-      com.android.settings|android)
-        blocked=$((blocked + 1)); say "  ! $p  → 系统硬依赖，禁止禁用（已拦截）"; continue ;;
-    esac
     if ! pkg_installed "$p"; then
```

</details>

### `harness/bin/cg-assert`

- 上游 mtime：2026-10-30 14:14:43
- 本地 mtime：2026-10-30 09:09:53
- 状态：上游较新（本地 2026-10-30 09:09:53）—— 未覆盖，待人工合并

<details><summary>差异摘要（diff -u 前 20 行）</summary>

```diff
--- /y/RK3562Android/features/.harness/bin/cg-assert	2026-10-30 14:14:43.869533800 +0800
+++ /d/workspace/user/android_bsp_harness/harness/bin/cg-assert	2026-10-30 09:09:53.860254500 +0800
@@ -43,70 +43,35 @@
 cmd_env() {
   local probe="${1:-0}"
   local rc=0 seen="" dir mcp db langs dbroot state detail
-  # --probe：真正打一次查询，识别"mtime 很新但库已损坏"的假绿。
-  # 网络盘上单根 query 可能 >90s（实测 frameworks/system/hardware/packages/kernel 均超时），
-  # 串行 7 个根会跑 6 分钟以上 → 每根独立超时（默认 60s），超时记 TIMEOUT（环境未就绪），
-  # **不谎报 CORRUPT**。
-  #
-  # 刻意保持串行：并行跑多个 codegraph query 会在网络盘上互相争抢 I/O，
-  # 且 timeout 杀掉父进程后 codegraph 的子进程会残留（实测积压 42 个 node.exe），
-  # 导致越跑越慢。串行时每个 query 都能被干净回收。
-  local probe_timeout="${CG_PROBE_TIMEOUT:-45}"
-  local -a dbroots=()
   while IFS=$'\t' read -r dir mcp db langs dbroot || [[ -n "${dir:-}" ]]; do
     [[ -z "${dir:-}" || "$dir" == \#* ]] && continue
     case " $seen " in *" $dbroot "*) continue ;; esac
     seen="$seen $dbroot"
```

</details>

### `harness/bin/check-drift`

- 上游 mtime：2026-10-30 12:01:52
- 本地 mtime：2026-10-30 11:17:09
- 状态：**【受保护】** 本地增强，本地 mtime 2026-10-30 11:17:09 / 上游 2026-10-30 12:01:52 —— 不覆盖，需人工合并

<details><summary>差异摘要（diff -u 前 20 行）</summary>

```diff
--- /y/RK3562Android/features/.harness/bin/check-drift	2026-10-30 12:01:52.001791700 +0800
+++ /d/workspace/user/android_bsp_harness/harness/bin/check-drift	2026-10-30 11:17:09.723022200 +0800
@@ -8,7 +8,13 @@
 #   --strict：根仓出现范围外脏文件      -> DRIFT
 #   git 不可用 / 缺 baseline            -> INVALID (exit 2)
 #
-# 用法：check-drift [feature] [--strict] [--quiet] [--timeout SEC]
+# --strict 的"允许脏"名单按顺序取：
+#   1. features/<feature>/.drift-ignore   （每 feature 一份，优先）
+#   2. .drift-ignore                      （树根一份，全 feature 共用）
+#   每行一个 shell glob（相对树根），空行与 # 注释忽略。
+#   两个文件都不存在时使用内置默认值（见 DEFAULT_IGNORE）。
+#
+# 用法：check-drift [feature] [--strict] [--quiet]
 # 退出码：0 无漂移（可含 WARN）；1 DRIFT；2 INVALID
 set -uo pipefail
 
@@ -19,20 +25,15 @@
 feature=""
 strict=0
```

</details>

### `harness/bin/feature-state`

- 上游 mtime：2026-10-30 12:43:08
- 本地 mtime：2026-10-28 16:39:13
- 状态：上游较新（本地 2026-10-28 16:39:13）—— 未覆盖，待人工合并

<details><summary>差异摘要（diff -u 前 20 行）</summary>

```diff
--- /y/RK3562Android/features/.harness/bin/feature-state	2026-10-30 12:43:08.495479500 +0800
+++ /d/workspace/user/android_bsp_harness/harness/bin/feature-state	2026-10-28 16:39:13.159632000 +0800
@@ -56,11 +56,7 @@
     commit="$(git_q -C "$top" log -1 --format=%h -- "$rel" 2>/dev/null || true)"
   fi
   branch="$(git_branch "$abs")"
-  # 脏检查加超时：网络盘上 git status 可能跑几百秒。
-  # 超时按"脏"处理（保守）——baseline 记录脏状态，后续 check-drift 会给出 WARN，
-  # 比默默记成"干净"然后给出假绿安全。
-  dstate="$(git_dirty_to "${FEATURE_STATE_TIMEOUT:-30}" "$top" "$rel")"
-  if [[ "$dstate" == "1" || "$dstate" == "124" ]]; then
+  if [[ -n "$(git_q -C "$top" status --porcelain -- "$rel" 2>/dev/null | head -n 1)" ]]; then
     dirty=1
   else
     dirty=0
@@ -76,49 +72,15 @@
   baseline="$HARNESS_ROOT/features/$feature/baseline.tsv"
   tmp="$baseline.tmp.$$"
 
-  # 并行探测：网络盘上每个仓的脏检查要等超时（默认 30s），串行 4 个仓 = 2 分钟。
```

</details>

### `harness/bin/prepare-feature`

- 上游 mtime：2026-10-30 12:15:19
- 本地 mtime：2026-10-28 16:39:44
- 状态：上游较新（本地 2026-10-28 16:39:44）—— 未覆盖，待人工合并

<details><summary>差异摘要（diff -u 前 20 行）</summary>

```diff
--- /y/RK3562Android/features/.harness/bin/prepare-feature	2026-10-30 12:15:19.245703600 +0800
+++ /d/workspace/user/android_bsp_harness/harness/bin/prepare-feature	2026-10-28 16:39:44.619858800 +0800
@@ -33,13 +33,10 @@
 echo "[prepare-feature] 上下文：features/$feature/AGENTS.md"
 
 drift_rc=0
-# check-drift 加超时：网络盘上 git status 可能跑几百秒，不能卡死准备流程。
-# 超时按"不可用"处理（exit 2 语义），不谎报"无漂移"。
-timeout 180 bash "$SCRIPT_DIR/check-drift" "$feature" --timeout 20 || drift_rc=$?
+bash "$SCRIPT_DIR/check-drift" "$feature" || drift_rc=$?
 case "$drift_rc" in
   0) : ;;
   1) echo "error: 漂移守卫失败，拒绝准备上下文" >&2; exit 1 ;;
-  124) echo "error: 漂移守卫超时（网络盘 git 过慢），无法确认漂移状态" >&2; exit 1 ;;
   *) echo "error: 漂移守卫不可用（exit $drift_rc）" >&2; exit 1 ;;
 esac
 
```

</details>

### `harness/lib/common.sh`

- 上游 mtime：2026-10-30 14:14:20
- 本地 mtime：2026-10-30 12:03:33
- 状态：**【受保护】** 本地增强，本地 mtime 2026-10-30 12:03:33 / 上游 2026-10-30 14:14:20 —— 不覆盖，需人工合并

<details><summary>差异摘要（diff -u 前 20 行）</summary>

```diff
--- /y/RK3562Android/features/.harness/lib/common.sh	2026-10-30 14:14:20.240696900 +0800
+++ /d/workspace/user/android_bsp_harness/harness/lib/common.sh	2026-10-30 12:03:33.577711500 +0800
@@ -41,14 +41,35 @@
   esac
 }
 
-abs_path() {
-  local p
-  p="$(to_msys "$(norm_path "$1")")"
+# 物理路径归一化（**两边都要过这一关**）。
+#
+# 【坑，实测踩过两次】Git Bash / MSYS 下同一目录有多种写法，且 `cd` 会"记住"你进门的写法：
+#   /y/RK3562Android        ==  Y:/RK3562Android
+#   /tmp/x                  ==  C:/Users/<u>/AppData/Local/Temp/x
+# `cd C:\...\Temp/x && pwd -P`  ->  /tmp/x
+# `cd /c/Users/.../Temp/x && pwd -P` -> /c/Users/.../Temp/x   （同一目录，两种输出）
+# 只用 to_msys 或只用 cd+pwd -P 都会让「树根」和「入参」落到不同分支 → 前缀永不匹配 →
+# 报「未登记的一级目录：<自己树里的路径>」。
+#
+# 解法：用 cygpath -w（POSIX→Windows）再 to_msys 回到 /c/... 形式，两个方向都收敛到同一写法。
```

</details>

### `harness/skills/ab-experiment/SKILL.md`

- 上游 mtime：2026-10-31 10:42:54
- 本地 mtime：2026-10-30 11:43:50
- 状态：上游较新（本地 2026-10-30 11:43:50）—— 未覆盖，待人工合并

<details><summary>差异摘要（diff -u 前 20 行）</summary>

```diff
--- /y/RK3562Android/features/.harness/skills/ab-experiment/SKILL.md	2026-10-31 10:42:54.014528700 +0800
+++ /d/workspace/user/android_bsp_harness/harness/skills/ab-experiment/SKILL.md	2026-10-30 11:43:50.372493600 +0800
@@ -105,7 +105,7 @@
 | 组 | 包数 | 定位 | 风险 |
 |---|---|---|---|
 | `core` | 13 | 广播型包 + 无业务后台服务（广播风暴尾部） | 最保守的一档 |
-| `extra` | 25 | 无硬件支撑的媒体/工具/壁纸/屏保 | 低（已剔除 sdksandbox，见下方黑名单） |
+| `extra` | 26 | 无硬件支撑的媒体/工具/壁纸/屏保 | 低 |
 | `kioskA` | 4 | 确定无用（动态分区/相机/书签/备份确认） | 低 |
 | `kioskB` | 16 | 高度可能无用（电话附加件/文档/MTP/代理/厂商应用） | 中——见下 |
 
@@ -113,14 +113,6 @@
 
 **修改清单**：直接编辑 TSV，不要在脚本里加硬编码数组（那是本工具要消除的反模式）。
 
-> ⚠ **系统硬依赖黑名单（2026-10-31 血的教训）**：本清单曾误含 `com.android.sdksandbox`（归在 `extra`），
-> `apply` 全量禁用后设备**无限 bootloop**——`PackageManagerService` 在 `startBootstrapServices` 阶段
-> 硬性断言"必须恰好存在一个 sdk sandbox 包"，禁用它后 system_server 启动即 `FATAL EXCEPTION` →
-> init 杀 zygote → 重启 → 再崩溃。最终靠 root shell 重命名 `/data/system/users/0/package-restrictions.xml`
-> 才解除。因此 `ab-experiment apply` 已内置黑名单拦截（`sdksandbox`/`systemui`/`launcher3`/`settings`/`android`），
```

</details>

### `harness/skills/boot-timing/SKILL.md`

- 上游 mtime：2026-10-31 11:25:17
- 本地 mtime：2026-10-30 11:42:45
- 状态：上游较新（本地 2026-10-30 11:42:45）—— 未覆盖，待人工合并

<details><summary>差异摘要（diff -u 前 20 行）</summary>

```diff
--- /y/RK3562Android/features/.harness/skills/boot-timing/SKILL.md	2026-10-31 11:25:17.867988000 +0800
+++ /d/workspace/user/android_bsp_harness/harness/skills/boot-timing/SKILL.md	2026-10-30 11:42:45.973693200 +0800
@@ -112,15 +112,6 @@
 | 无 boot_progress | 输出 NODATA | events 环形缓冲被冲掉 |
 | T2 锚点缺失 | 输出 NOCOMPLETE | 本次启动未走到 sys.boot_completed=1，T2/T3 无意义 |
 
-## 上下文卫生（Token 纪律，2026-10-31 据 token 降本策略落地）
-
-本工具的设计目标之一就是把"开机分析"的 token 成本压到最低，使用时应遵守：
-
-- **只回紧凑摘要/CSV，绝不把原始 logcat 倒进对话**：`report` 内部算完只输出里程碑表 + 结论；`-o <csv>` 落盘结构化数据供 `verify` 判定。分析 3.6MB 级 logcat 时只在工具内算、回结论，原始日志不进上下文。
-- **离线自测优先 `--demo`**：验证脚本本身是否跑通时用 `--demo`（零 adb 调用），不要把"真实设备数据采集"和"脚本自测"混为一谈。
-- **非 codegraph 文件类型走 ripgrep**：`.xml/.mk/.sh/.dts/.bp/.json` 等不在 codegraph 索引内的类型，用 Grep/ripgrep 检索，不拉整文件进上下文。
-- 完整策略见 `features/.harness/docs/token-reduction-strategy.md`。
-
 ## 明确不做
 
 - 不编译、不部署、不改设备状态（`report` 全程只读）；
```

</details>

### `harness/skills/codegraph-nav/SKILL.md`

- 上游 mtime：2026-10-30 14:22:44
- 本地 mtime：2026-10-30 11:17:26
- 状态：上游较新（本地 2026-10-30 11:17:26）—— 未覆盖，待人工合并

<details><summary>差异摘要（diff -u 前 20 行）</summary>

```diff
--- /y/RK3562Android/features/.harness/skills/codegraph-nav/SKILL.md	2026-10-30 14:22:44.102714400 +0800
+++ /d/workspace/user/android_bsp_harness/harness/skills/codegraph-nav/SKILL.md	2026-10-30 11:17:26.943086300 +0800
@@ -1,13 +1,19 @@
 ---
 name: codegraph-nav
-description: 在 RK3562Android 的 7 个隔离 codegraph 库之间定位与检索代码。用于"这个符号在哪、谁调用它、改动影响面多大"这类结构性问题，以及需要判断该用哪个一级根、该不该回退 ripgrep 的场景。
+description: 在一棵树被切成多个隔离 codegraph 库的 BSP/Android 源码里定位与检索代码。用于"这个符号在哪、谁调用它、改动影响面多大"这类结构性问题，以及需要判断该用哪个一级根、该不该回退 ripgrep 的场景。
 ---
 
-# codegraph 检索与路由（RK3562Android）
+# codegraph 检索与路由
 
 ## 适用范围
 
-- 目标文件位于 `Y:\RK3562Android` 之下的**代码检索、调用链、引用、影响面**分析；
+- 目标文件位于**已安装 harness 的源码树**之下的**代码检索、调用链、引用、影响面**分析；
+- 树的根清单不写死，**永远以路由表为准**：
+
+  ```bash
+  bash features/.harness/bin/cg-route --list    # 已登记的根 + 库路径
```

</details>

### `harness/skills/deploy-and-accept/SKILL.md`

- 上游 mtime：2026-10-30 14:40:09
- 本地 mtime：2026-10-30 11:17:26
- 状态：上游较新（本地 2026-10-30 11:17:26）—— 未覆盖，待人工合并

<details><summary>差异摘要（diff -u 前 20 行）</summary>

```diff
--- /y/RK3562Android/features/.harness/skills/deploy-and-accept/SKILL.md	2026-10-30 14:40:09.726532600 +0800
+++ /d/workspace/user/android_bsp_harness/harness/skills/deploy-and-accept/SKILL.md	2026-10-30 11:17:26.943086300 +0800
@@ -1,9 +1,9 @@
 ---
 name: deploy-and-accept
-description: 把单文件产物部署到已确认的 RK3562 设备并完成验收（备份、原子替换、失败回滚、reboot 后 boot_id 与 sys.boot_completed 校验）。用于用户明确授权上机验证、且已经拿到本次构建产物时。
+description: 把单文件产物部署到已确认的 Android 设备并完成验收（备份、原子替换、失败回滚、reboot 后 boot_id 与 sys.boot_completed 校验）。用于用户明确授权上机验证、且已经拿到本次构建产物时。
 ---
 
-# 部署与验收（RK3562）
+# 部署与验收
 
 ## 前置条件（缺一即停）
 
@@ -19,7 +19,7 @@
 
 ## 事务契约（不可省略的 5 步）
 
-本仓库**当前没有**自动化部署脚本；以下契约要求在实现入口时逐条满足，手工执行时同样按序：
+本框架**不提供**自动化部署脚本；以下契约要求在实现入口时逐条满足，手工执行时同样按序：
```

</details>

### `harness/tests/test-harness.sh`

- 上游 mtime：2026-10-31 11:32:04
- 本地 mtime：2026-11-02 08:40:26
- 状态：**【受保护】** 本地增强，本地 mtime 2026-11-02 08:40:26 / 上游 2026-10-31 11:32:04 —— 不覆盖，需人工合并

<details><summary>差异摘要（diff -u 前 20 行）</summary>

```diff
--- /y/RK3562Android/features/.harness/tests/test-harness.sh	2026-10-31 11:32:04.491935000 +0800
+++ /d/workspace/user/android_bsp_harness/harness/tests/test-harness.sh	2026-11-02 08:40:26.265174400 +0800
@@ -1,251 +1,475 @@
 #!/usr/bin/env bash
-# features/.harness/tests/test-harness.sh
-# 离线回归：不需要设备、不执行构建。覆盖路由、库状态、基线、漂移、构建判定、三态协议、功能断言。
+# tests/test-harness.sh —— 在临时假树里端到端验证 harness。
 #
-# 运行：bash features/.harness/tests/test-harness.sh
+# 原则：
+#   - **不碰**任何真实源码树；全部在 mktemp -d 里跑，结束即删；
+#   - 不依赖 python3 / jq，只依赖 bash + git + coreutils + find/awk/sed；
+#   - codegraph 相关的"真建库"用例在 codegraph 缺失时记为 SKIP（不是 PASS）；
+#   - 断言全部是"命令退出码 + 输出内容"，不做模糊匹配。
+#
+# 用法：
+#   bash tests/test-harness.sh              # 全量
+#   bash tests/test-harness.sh --keep       # 保留临时目录便于排查
+#   bash tests/test-harness.sh --no-index   # 跳过真建库（磁盘/时间敏感时）
+#
```

</details>

