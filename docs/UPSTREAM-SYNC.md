# 上游 harness 同步与合并记录

- 生成时间：2026-11-04 16:52 +0800
- 上游源：`Y:\RK3562Android\features\.harness`（只读）
- 本地仓库：`D:\workspace\user\android_bsp_harness`
- 裁决原则：**以本地为准**——本地已有的增强一律保留；上游功能与本地不冲突的吸收，冲突的以本地实现为准。
- 当前状态：**待合并 0 项**。11 项历史差异已全部裁决完毕。

## 本次合并明细（共 11 项）

| # | 文件 | 处理 | 说明 |
|---|---|---|---|
| 1 | `harness/bin/ab-experiment` | 采用上游 | 新增系统硬依赖黑名单（`sdksandbox`/`systemui`/`launcher3`/`settings`/`android`）拦截，输出改四态计数。本地此前无独有内容 |
| 2 | `harness/bin/cg-assert` | 采用上游 | `--probe` 加超时（`CG_PROBE_TIMEOUT`）、新增 `TIMEOUT` 态（不再谎报 `CORRUPT`）、`files` 加超时与进程回收 |
| 3 | `harness/bin/check-drift` | **合并** | 本地 `.drift-ignore` 机制 + 上游 `--timeout`／超时降级（`124` → `WARN` 不判定）并存；内置默认名单补入 `sync-agent-rules.ps1` |
| 4 | `harness/bin/feature-state` | 采用上游 | 脏检查走 `git_dirty_to`（超时按脏处理，保守）+ 多仓并行探测，输出仍按 `repos.tsv` 原序 |
| 5 | `harness/bin/prepare-feature` | 采用上游 | 调 `check-drift --timeout 20` 并新增 `124` 分支（超时按"不可用"退出，不谎报无漂移） |
| 6 | `harness/lib/common.sh` | **合并** | 保留本地 `canon_path()`／`abs_path()`（`Y:/` 与 `/y/`、`C:/.../Temp` 与 `/tmp` 收敛，去掉则路由全部失败）；吸收上游 `git_to` / `git_dirty_to` / `codegraph_query_to` / `codegraph_files_to` / `_kill_tree` |
| 7 | `harness/skills/ab-experiment/SKILL.md` | 采用上游 | 补黑名单成因（sdksandbox 致 bootloop 实测）、`extra` 组 26 → 25、四态计数说明 |
| 8 | `harness/skills/boot-timing/SKILL.md` | 采用上游 | 新增「上下文卫生（Token 纪律）」节；**删去**指向 `features/.harness/docs/token-reduction-strategy.md` 的一行——该文档不随仓库分发，装到树里会是死链 |
| 9 | `harness/skills/codegraph-nav/SKILL.md` | **合并** | 保留本地通用化表述（不写死 RK3562 根清单）；吸收上游 `env --probe`、`TIMEOUT` 态、网络盘 `CG_PROBE_TIMEOUT`/`CG_FILES_TIMEOUT` 说明、`taskkill /IM node.exe` 禁令 |
| 10 | `harness/skills/deploy-and-accept/SKILL.md` | 保留本地 | 本地已通用化（"RK3562 设备" → "Android 设备"），并把平台专属检查移出 skill、指向 `verify-<feature>.sh`。上游的 Rockchip 判定属具体项目知识，不进框架 |
| 11 | `harness/tests/test-harness.sh` | 保留本地 | 本地是全量重写（475 行 vs 上游 251 行），含 `is_shell_script()` 按 shebang 过滤（`adb-device-guard` 是 python3）、`--no-index` 下 `.codegraph` 断言改 SKIP。上游版本无对应能力 |

## 有意分叉（今后比对仍会显示差异，属正常，勿再列为"待合并"）

- `harness/lib/common.sh` —— 上游 `abs_path()` 已被本地 `canon_path()` 取代；上游重复堆叠的超时函数注释已合并为一段。
- `harness/bin/check-drift` —— 上游用硬编码 `case` 名单，本地用 `.drift-ignore` + `ignored()`。
- `harness/skills/codegraph-nav/SKILL.md` —— 本地去 RK3562 硬编码。
- `harness/skills/deploy-and-accept/SKILL.md` —— 同上。
- `harness/tests/test-harness.sh` —— 本地重写版。

## 回归

`bash harness/tests/test-harness.sh --no-index` → `SUMMARY PASS=80 FAIL=0 SKIP=5`（与合并前基线一致）。

合并后新增的依赖关系：`check-drift --timeout` → `common.sh:git_to/git_dirty_to`；
`cg-assert` → `common.sh:codegraph_query_to/codegraph_files_to`；`feature-state` → `git_dirty_to`。
改动这几个文件时请一并检查。
