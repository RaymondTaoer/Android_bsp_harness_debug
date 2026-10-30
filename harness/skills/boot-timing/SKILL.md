---
name: boot-timing
description: RK3562/Android 开机耗时测量与冷启动 A/B 对比（T1 首帧 / T2 就绪 / T3 末进程 / T4 真实空闲、boot_progress 里程碑、BC 广播拖尾归因）。用于"量开机时间""测 T1/T2/T3""冷启动对比""boot 时序""开机慢归因"这类测量场景；判定验收结论不使用本 skill（那是 verify 的事）。
---

# boot-timing —— 开机耗时测量（RK3562）

单一事实源：`features/.harness/bin/boot-timing`（合并自 `debugdoc/tools/boot_time.sh` 与 `boot_measure.sh`，2026-10-30）。
debugdoc 下两个旧实现**已冻结归档**，勿再改、勿再引用。

## 适用范围

- 测当前这次启动的开机时序（**只读**，不重启）；
- 多轮冷启动测量 / 裁剪前后 A/B 对比（`rounds`，**会重启设备**）；
- 为 `verify-boot-opt.sh` 的 FEATURE 段提供时序数据（断言判定在 verify，不在本工具）。

## 前置条件（缺一即停）

1. `ANDROID_SERIAL` 必须由人显式设置——不猜、不取第一个设备；
2. `rounds` 子命令会**重启设备 N 次**，必须先拿到用户的显式授权；
   部署/烧写/清数据**不在**本工具授权范围内；
3. 建议 userdebug + root（`dmesg` 读 U-Boot 段需要 root；缺失时该行显示 n/a，不猜）。

```bash
: "${ANDROID_SERIAL:?设置 ANDROID_SERIAL 为已确认的目标序列号}"
```

## 命令

| 场景 | 命令 |
|---|---|
| 测当前启动（只读） | `bash features/.harness/bin/boot-timing report` |
| 测当前启动并落盘 | `bash features/.harness/bin/boot-timing report -o <csv>` |
| 多轮冷启动（需授权） | `bash features/.harness/bin/boot-timing rounds -n 5 -o <csv>` |
| 收尾等待调长 | 追加 `-w 120`（默认 90s，等 BC 广播完成上报出现） |
| 等 boot_completed 超时调长 | 追加 `-t 400`（默认 240s；超时判本轮作废） |
| 离线自测 | 追加 `--demo`（模拟数据、**零 adb 调用**，不是测量证据） |

## 测量口径（全部为实测锚点，不靠估算）

t=0 = 内核启动；`base = boot_progress_start 的 wall time − 其 ms 值`。

| 锚点 | 来源 | 含义 |
|---|---|---|
| T1 首帧 | `sf_stop_bootanim`（events） | bootanim 结束 / launcher 首帧可见 |
| T2 就绪 | init `processing action (sys.boot_completed=1)`（main） | 系统就绪 |
| T3 末进程 | 开机窗口内最后一个 `am_proc_start`（BC 后 60s 截止） | **最后一个进程被拉起**（不等于机器空闲！） |
| T4 真实空闲 | `BOOT_COMPLETED_BROADCAST_COMPLETION_LATENCY_REPORTED`（BroadcastQueue） | **BC 广播全部接收者完成**＝机器真没活了 |
| bc_post | `Posting BOOT_COMPLETED` − T2 | 广播队列启动延迟 |
| 里程碑链 | `boot_progress_*`（events） | zygote / preload / system_run / pms / ams / enable_screen |

### ★ T3 会严重低估真实空闲时间（2026-10-30 实测铁证）

真机实测（45bfd85c89194875）：

```
T1=45.38s  T2=46.79s  T3=52.74s   ← 旧口径只报到 52.74s
T4=114.09s                            ← 真实空闲点，晚 61.35s
```

原因：`com.android.phone/.vvm.VvmSimStateTracker` 的 BOOT_COMPLETED 接收者卡死，
`BroadcastQueue` 报 `Timeout of broadcast ... started 60003ms ago`，
导致整个 BC 广播的 `completeLatency` = **66477ms（66.5 秒）**。

**结论：判断"机器真的空下来"必须看 T4（`bc_done_s` 列），不能只看 T3。**
本工具的 report 段会自动抓 `Timeout of broadcast` / `Receiver during timeout` 行做归因。

### 其它口径要点

- 数据源：一次 `logcat -b all -d -v epoch`（boot_progress 在 events，boot_completed 在 main，BC 完成上报在 BroadcastQueue，缺一不可）+ `dmesg` 首行（U-Boot 段）；
- **时钟跳变与残留锚点**：RK3562 无 RTC 电池时，开机早期日志带假时钟（如 2017 年），events 缓冲还可能残留上次启动的 boot_progress。base 一律按 `/proc/stat btime` 从锚点候选中选取，检测到跳变时报告注明；`dmesg` 首行晚于 zygote 视为环形已轮转（非开机时刻），显示 n/a；
- **窗口下限**：T3 的进程统计窗口下界 = base − 2s，排除上次启动遗留的 `am_proc_start`；
- **窗口退化已修**：旧实现当 T2/BC 锚点缺失时 `lim=0`，会把**全部历史进程**算进 T3 —— 曾产出"164 进程 / T3=355s"的假数据。现在 T2 缺失时输出 `NOCOMPLETE` 并失败退出；
- 时间基线：events 环形缓冲被冲掉时报告 NODATA 并**失败退出**，提示改用 `rounds -n 1`；
- 查询失败 ≠ 无数据：logcat 非零退出按 `FAIL <查询失败>` 处理，不输出假结果。

## CSV schema（20 列，新文件自动写表头）

```
round,wall_time,T1_first_frame_s,T2_boot_completed_s,T3_last_proc_s,proc_count,
zygote_s,preload_start_s,preload_end_s,system_run_s,pms_start_s,pms_ready_s,
ams_ready_s,enable_screen_s,bc_post_s,bc_done_s,bc_receivers,bc_complete_ms,
plc_cpu_pct,soc_temp_mc
```

- 时间列单位统一为秒（`*_ms` 除外）；`plc_cpu_pct` = codesyscontrol 的 CPU%（top 取样）；
- `bc_done_s` = T4（BC 广播全部接收者完成的时刻）；`bc_complete_ms` = completeLatency（原生即 ms，**勿 ×1000**）；
- **表头不符拒绝追加**：旧口径 CSV（boot_time/boot_measure 时期 19 列 schema）请另起新文件，不要混写。
  已归档的旧基线：`debugdoc/docs/evidence/boot-baseline-2026-10-30.csv`（19 列，无 bc_done_s）；
- 位置约定：测量证据落 `debugdoc/docs/evidence/`（KB 的 evidence 类别）或明确指定路径，不写入 `debugdoc/tools/`（那是脚本仓）。

## 与验收闭环的关系

- 本工具只产出**测量数据**，不产出 `RESULT PASS/FAIL`；
- 开机时序断言的判定入口是 `bash features/boot-opt/verify-boot-opt.sh --timing <csv>`；阈值写在 `features/boot-opt/assertions.tsv`，未配置时如实输出 `SKIP 功能断言未定义` + `RESULT INCOMPLETE`；
- A/B 对比纪律：每组 ≥5 轮取**中位数**再比；冷启动用 `adb reboot`（断电口径不稳定）；
- **病理轮次要单独归因，不能混入中位数**：某轮 boot_completed 超时未置位（`-t` 耗尽）或输出 `NOCOMPLETE` 时，工具会**判该轮作废并停止**，不会把它写进 CSV。

## 失败语义与退出码

| 退出码 | 含义 |
|---|---|
| 0 | 测量成功 |
| 1 | 测量/数据/连接失败（`rounds` 任一轮失败即停，已写入行是有效数据） |
| 2 | 用法错误（含未设 `ANDROID_SERIAL`、`rounds` 缺 `-n`、`-w/-t` 非正整数） |

`rounds` 的三类失败判定（均**不写入**该轮数据）：

| 情形 | 判据 | 含义 |
|---|---|---|
| boot_completed 超时 | `-t`（默认 240s）内未置位 | 本轮开机未完成（可能是 system_server 崩溃循环），需人工归因 |
| 无 boot_progress | 输出 NODATA | events 环形缓冲被冲掉 |
| T2 锚点缺失 | 输出 NOCOMPLETE | 本次启动未走到 sys.boot_completed=1，T2/T3 无意义 |

## 明确不做

- 不编译、不部署、不改设备状态（`report` 全程只读）；
- `rounds` 只做"清日志 + reboot + 测量"，不刷机、不清数据、不碰分区；
- 不在 `--demo` 数据上出验收结论——demo 只证明脚本能跑。
