# <FEATURE> —— feature 上下文

> 本文件是该 feature 的完整上下文。把它复制到 `features/<FEATURE>/AGENTS.md` 后填空。
> 树根 `AGENTS.md` 的"当前 feature"段（宽 `<!-- HARNESS_FEATURE_START -->` 区间）由脚本维护，勿手改。

## A. 树级构建约束

- 平台 / 分支 / 产品：<平台与版本，例如 Android 13 TP1A；产品 out 目录>
- 构建位置：<构建容器 / 主机；明确"不在本机会话里跑长构建">
- 长构建纪律：唯一日志 + 后台执行 + 轮询 + `wait` 取子进程退出码；成功判据必须同时满足"日志含成功标记"和"产物 mtime 晚于本次开始"；
- 禁止手工编辑生成物目录：<out/ 、rockdev/ 、IMAGE/ 等>;
- 改 public/System API、sepolicy 的额外要求：<按平台填写>。

### 构建决策（不执行构建，只决定编什么）

| 改动位置 | 最小构建 | 需整包 | 需烧写 | 验收入口 |
|---|---|---|---|---|
| <一级根 A> | <最小构建命令> | <是/否> | <是/否> | <判定方式> |
| <一级根 B> | <最小构建命令> | <是/否> | <是/否> | <判定方式> |
| 判据 | `bash features/.harness/bin/verify-build --log <log> --artifact <产物>` | | | |

## B. feature 范围

允许修改（机器可读清单：`features/<FEATURE>/repos.tsv`）：

- `<一级根>/<子路径>`：<允许改什么>
- ...

明确**不改**：

- `out/`、`build/`、`prebuilts/` 等生成物与预编译目录；
- 别名目录（真实源码在别名指向的目录）；
- <其它禁区>。

## C. 流程路由

| 什么时候 | 读什么 / 跑什么 |
|---|---|
| 任何代码检索、调用链、影响面 | skill `codegraph-nav` |
| 决定编什么、编完怎么判成功 | 上方"构建决策"表 + `verify-build` |
| 要上机部署/验收 | skill `deploy-and-accept`（需显式授权 + `ANDROID_SERIAL`） |
| 写源码前 | `bash features/.harness/bin/check-drift <FEATURE>` |
| 交付前 | `bash features/<FEATURE>/verify-<FEATURE>.sh` |

## D. 证据与终结

四段证据：STATIC（codegraph，离线）→ BUILD（判定已有产物）→ DEVICE（adb）→ FEATURE（功能断言）。

| 结果 | 含义 | 退出码 |
|---|---|---|
| `RESULT PASS` | 全部必需断言通过，无 SKIP | 0 |
| `RESULT FAIL` | 任一断言失败或查询失败 | 非 0 |
| `RESULT INCOMPLETE` | 环境未就绪（无设备/未构建/库过期或损坏/功能断言未定义） | 非 0 |

- 查询失败不得当成"不存在"；缺数据不得当成空结果通过；
- `--demo` 只用于离线自测，不得作为验收证据；`--allow-skip` 只允许与 `--demo` 连用；
- 共享资源串行：同一 `out/` 的构建、同一设备的操作。

### 功能断言

| 环节 | 位置 |
|---|---|
| 阈值（唯一事实源） | `features/<FEATURE>/assertions.tsv` |
| 数据 | <产出指标 CSV 的命令> |
| 判定 | `bash features/<FEATURE>/verify-<FEATURE>.sh --metrics <csv>` |

规则：

1. 阈值**必须由人定**，代码里不预置任何数字；未配置时结果一定是 `RESULT INCOMPLETE`；
2. 指标列找不到、值为空或 `NA` → 输出 `SKIP`（数据不可判定），不当成满足阈值；
3. 指标名容忍单位后缀：`foo` 与 `foo_s` / `foo_ms` 等价；
4. `--demo` 生成的 CSV 只能证明链路通，**不得**作为验收证据。
