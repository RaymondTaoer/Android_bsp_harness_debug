# 上游 harness 同步报告

- 生成时间：2026-11-06 14:05 +0800
- 上游源：`Y:\RK3562Android\features\.harness`（只读，本次未写入任何文件）
- 本地仓库：`D:\workspace\user\android_bsp_harness`
- 同步范围：`harness/`（bin / lib / skills / templates / tests / examples）+ 根文件

## 本次结果

| 项 | 数量 |
|---|---|
| 上游新增（仓库无） | 0 |
| 内容不同（未覆盖，需人工判断） | 6 |
| 其中「有意分叉」（已裁决，非待合并） | 6 |
| 仓库独有（上游无，保留） | 6 |
| 待人工合并 | **0** |

**上游自 2026-10-31 13:51 后无任何框架文件改动**（全树 mtime 未变），本次比对结果与 2026-11-04 合并后基线完全一致：无新增、无新分叉。

## 差异明细（源 → 仓库，`diff -u` 摘要）

判定方向统一为「上游版本 → 本地仓库版本」，即 `+` 行为仓库独有内容。

### 1. `harness/lib/common.sh`（保护文件）

- 上游 mtime：2026-10-30 14:14
- 规模：69 行差异
- 摘要：本地以 `canon_path()` 取代上游 `abs_path()`。Git Bash 下 `Y:/…` 与 `/y/…`、`C:/…/Temp` 与 `/tmp` 是同一目录的多种写法，本地用 `cygpath -w` + `to_msys` 双向收敛；去掉它会导致「未登记的一级目录：<自己树里的路径>」并使全部路由失败。本地另吸收上游 `git_to` / `git_dirty_to` / `codegraph_query_to` / `codegraph_files_to` / `_kill_tree`。**不可覆盖。**

### 2. `harness/bin/check-drift`（保护文件）

- 上游 mtime：2026-10-30 12:01
- 规模：60 行差异
- 摘要：本地支持 `.drift-ignore`（每 feature 一份优先、树根一份共用，每行一个相对树根的 glob），上游为硬编码 `case` 名单；本地同时保留上游 `--timeout`（默认 30s，超时记 WARN 不判定为干净）与内置默认名单补入 `sync-agent-rules.ps1`。**不可覆盖。**

### 3. `harness/tests/test-harness.sh`（保护文件）

- 上游 mtime：2026-10-31 11:32
- 规模：678 行差异（本地 475 行 vs 上游 251 行，属全量重写）
- 摘要：本地在 `mktemp -d` 假树里端到端跑，含 `is_shell_script()` 按 shebang 过滤（`adb-device-guard` 是 python3，不能进 `bash -n`）、`--no-index` 下 `.codegraph` 断言改 SKIP、`--keep` 保留现场。上游无对应能力。**不可覆盖。**

### 4. `harness/skills/boot-timing/SKILL.md`

- 上游 mtime：2026-10-31 11:25
- 规模：3 行差异（1 个 hunk，仅删除 1 行正文）
- 摘要：本地有意删除 `完整策略见 features/.harness/docs/token-reduction-strategy.md` 一行——该文档属项目内部资产、不随仓库分发，装了是死链。属 2026-11-04 合并明细第 8 项的既定处理。

### 5. `harness/skills/codegraph-nav/SKILL.md`

- 上游 mtime：2026-10-30 14:22
- 规模：50 行差异
- 摘要：本地去 RK3562 硬编码（`description` 与标题改为通用表述），根清单改为「永远以路由表为准」并给出 `cg-route --list` 自查命令；同时吸收上游 `env --probe`、`TIMEOUT` 态、网络盘 `CG_PROBE_TIMEOUT`/`CG_FILES_TIMEOUT` 说明、`taskkill /IM node.exe` 禁令。

### 6. `harness/skills/deploy-and-accept/SKILL.md`

- 上游 mtime：2026-10-30 14:40
- 规模：13 行差异
- 摘要：本地已通用化（「RK3562 设备」→「Android 设备」、「本仓库」→「本框架」），平台专属检查移出 skill 并指向 `verify-<feature>.sh`。上游的 Rockchip 判定属具体项目知识，按「框架不带项目知识」原则不进仓库。

## 有意分叉（今后比对仍会显示差异，属正常，勿再列为「待合并」）

以上 6 项全部为有意分叉，已由人工于 2026-11-04 裁决完毕（「以本地为准」），待合并恒为 0。
其中 `lib/common.sh`、`bin/check-drift`、`tests/test-harness.sh` 另受硬性保护：上游即使更新也**不覆盖**，只记录差异。

## 仓库独有（上游无对应文件，保留不删）

`harness/bin/cg-build`、`harness/bin/cg-ensure`、`harness/bin/cg-exclude`、`harness/bin/cg-roots`、
`harness/bootstrap.sh`、`harness/templates/*`（4 个模板 + `verify-feature.sh`）、
`examples/rk3562/*`、`docs/DESIGN.md`、`docs/CODEGRAPH.md`、`docs/TROUBLESHOOTING.md`。

说明：上游 `docs/` 仅含 `device-guard-hook.md`、`token-reduction-strategy.md` 两份项目内部文档，
不在同步映射内，故不同步；仓库三个 docs 为通用化重写版。

## 回归

`bash harness/tests/test-harness.sh --no-index` → `SUMMARY PASS=80 FAIL=0 SKIP=5`。

## 知识内容闸门

- `.gitignore:19` 覆盖 `docs/kb/`；`docs/kb/` 9 个文件（含 `KB.md`、`KB_PLAN.md`）留在工作区，被忽略、不提交、不删除。
- 提交前 `git diff --cached --name-only | grep -E '^docs/kb/|^debugdoc/|(^|/)KB(_PLAN)?\.md$'` 为空。
- 推送前 `git ls-tree -r --name-only HEAD | grep -E '^docs/kb/|^debugdoc/'` 为空。

---

## 附录：2026-11-04 历史合并记录（11 项裁决，commit `949fe91`）

| # | 文件 | 处理 | 说明 |
|---|---|---|---|
| 1 | `harness/bin/ab-experiment` | 采用上游 | 新增系统硬依赖黑名单（`sdksandbox`/`systemui`/`launcher3`/`settings`/`android`）拦截，输出改四态计数 |
| 2 | `harness/bin/cg-assert` | 采用上游 | `--probe` 加超时（`CG_PROBE_TIMEOUT`）、新增 `TIMEOUT` 态（不再谎报 `CORRUPT`）、`files` 加超时与进程回收 |
| 3 | `harness/bin/check-drift` | 合并 | 本地 `.drift-ignore` + 上游 `--timeout`／超时降级（`124` → `WARN`）并存；默认名单补入 `sync-agent-rules.ps1` |
| 4 | `harness/bin/feature-state` | 采用上游 | 脏检查走 `git_dirty_to`（超时按脏处理）+ 多仓并行探测，输出按 `repos.tsv` 原序 |
| 5 | `harness/bin/prepare-feature` | 采用上游 | 调 `check-drift --timeout 20` 并新增 `124` 分支（超时不谎报无漂移） |
| 6 | `harness/lib/common.sh` | 合并 | 保留 `canon_path()`／`abs_path()`，吸收上游超时函数族 |
| 7 | `harness/skills/ab-experiment/SKILL.md` | 采用上游 | 补黑名单成因、`extra` 组 26 → 25、四态计数说明 |
| 8 | `harness/skills/boot-timing/SKILL.md` | 采用上游 | 新增「上下文卫生（Token 纪律）」节；**删去**指向 `token-reduction-strategy.md` 的死链 |
| 9 | `harness/skills/codegraph-nav/SKILL.md` | 合并 | 保留通用化表述；吸收 `env --probe`、`TIMEOUT` 态、超时变量、`taskkill` 禁令 |
| 10 | `harness/skills/deploy-and-accept/SKILL.md` | 保留本地 | 已通用化，平台专属检查移出 skill |
| 11 | `harness/tests/test-harness.sh` | 保留本地 | 本地全量重写，含 `is_shell_script()` 与 SKIP 修复 |

合并后新增的依赖关系：`check-drift --timeout` → `common.sh:git_to/git_dirty_to`；
`cg-assert` → `common.sh:codegraph_query_to/codegraph_files_to`；`feature-state` → `git_dirty_to`。
改动这几个文件时请一并检查。
