---
name: perf-probe
description: RK3562 性能/温度/中断/PLC 占用采样与分析（probe 一体化、snap 快照、rank 进程排名、threads PLC 线程、irq 中断、trend 趋势 CSV）。用于"看 CPU 占用""温度多少""谁在吃 CPU""中断多少""PLC 负载""降频没"这类采样场景；判定验收结论不使用本 skill（那是 verify 的事）。
---

# perf-probe —— 性能/温度/中断采样分析（RK3562）

单一事实源：`features/.harness/bin/perf-probe`（合并自 `debugdoc/tools` 7 个采样脚本，2026-10-30：
`cpu_thermal_probe.sh` `_sys_snapshot.sh` `_proc_rank.sh` `_thread_rank.sh` `_irq_top.sh`
`_temp_trend.sh` `_cpu_sample.sh`）。
debugdoc 下旧实现**已冻结归档**，勿再改、勿再引用。

## 适用范围

- 采样整机/分核 CPU 占用、PLC（codesyscontrol）进程与线程负载、arch_timer 定时器速率、
  WFI/深睡次数、SoC 温度、当前频率、cooling_state（**全程只读，零设备写入**）；
- 温度/负载趋势 CSV（观察降频、热积累）；
- 为 `verify-boot-opt.sh` 的 FEATURE 段提供性能断言数据（断言判定在 verify，不在本工具）。

## 前置条件（缺一即停）

1. `ANDROID_SERIAL` 必须由人显式设置——不猜、不取第一个设备；
2. 本工具**不重启、不部署、不改设备状态**，无需额外授权；
3. 无需 root（读 /proc/stat、/proc/interrupts、/sys 即可）；userdebug + root 可读性更稳。

```bash
: "${ANDROID_SERIAL:?设置 ANDROID_SERIAL 为已确认的目标序列号}"
```

## 命令

| 场景 | 命令 |
|---|---|
| 一体化性能报告 + SUMMARY | `bash features/.harness/bin/perf-probe probe`（默认采样 8s） |
| 轻量快照 | `bash features/.harness/bin/perf-probe snap` |
| 谁在吃 CPU（全进程 top15） | `bash features/.harness/bin/perf-probe rank`（默认 5s） |
| PLC 线程 top10 | `bash features/.harness/bin/perf-probe threads` |
| 中断源 top8 + 总速率 | `bash features/.harness/bin/perf-probe irq` |
| 温度/负载趋势 CSV | `bash features/.harness/bin/perf-probe trend 18 5`（18 点 × 5s ≈ 90s） |
| 采样窗口调长 | 位置参数：`probe 15` / `rank 10`（1..3600 秒） |
| 离线自测 | 追加 `--demo`（模拟数据、**零 adb 调用**，不是测量证据） |

## 采样口径（全部为实测读数，不靠估算）

- **双采样差分**：窗口起点/终点各读一次计数器，差值 ÷ 窗口 ÷ `CLK_TCK`；
- **busy%** = (user+nice+system+irq+softirq+steal+guest) / 总 tick 差（idle+iowait 计入 idle）；
  单核满载 = 100%，整机 4 核上限 = 400%；
- **PLC%** = codesyscontrol 的 (utime+stime) 差，折算"单核百分比"（50% = 半个核）；
  pid 每次自动探测，**不写死**；采样窗口内进程退出/重启 → 诚实输出 NA，不给假数；
- **timer** = `/proc/interrupts` 中 arch_timer 各 CPU 列之和的差分速率（4 核合计）；
- **WFI / 深睡(cpu-sleep)** = `cpu0/cpuidle/state0|state1/usage` 差分速率；
- **温度/频率/cooling_state** = `thermal_zone0/temp`、`policy0/scaling_cur_freq`、
  `cooling_device0/cur_state`（RK3562 路径；换板子只改设备侧采集器里的路径）；
- **rank/threads**：窗口内**新出现的 pid/tid 无基线，直接跳过**（旧实现会误报 100% 占用）；
- comm 含空格/括号按最后一个 `") "` 切分解析，实测 `codesys io` 类 comm 可正确解析。

## SUMMARY 键值行（probe 末行，供 verify 断言 grep）

```
SUMMARY busy=41.7 usr=23.1 sys=13.9 irq=2.3 softirq=2.3 idle=58.3 plc_pct=50.0 plc_pid=994 \
timer_hz=12500 wfi_per_s=200 dsleep_per_s=2.0 temp_mc=55500 freq_khz=1800000 cool=0 cores=4
```

- `temp_mc` 为毫摄氏度（sysfs 原生值），`freq_khz` 为 kHz；
- 任一读数失败该键为 `NA`（不是 0）；`plc_pct=NA` 表示 PLC 未运行或中途退出。

## trend CSV schema（7 列，与旧 `_temp_trend.sh` 完全兼容）

```
uptime_s,temp_C,plc_pct,busy_pct,freq_GHz,cooling,deep_sleep
```

- `deep_sleep` 为 `state1/usage` **累计计数**（不是速率，沿旧口径）；
- `plc_pct=NA` 同上；CSV 走 stdout，进度信息走 stderr，可直接 `> out.csv` 重定向。

## 与验收闭环的关系

- 本工具只产出**采样数据**，不产出 `RESULT PASS/FAIL`；
- 性能断言的判定入口是 `bash features/boot-opt/verify-boot-opt.sh`（FEATURE 段断言仍待补）；
- 温度/降频证据落 `debugdoc/docs/evidence/`（KB 的 evidence 类别），不写入 `debugdoc/tools/`；
- 归因到代码：采样结果指向可疑路径后，走 skill `codegraph-nav` 静态定位（不混在本工具里）。

## 失败语义与退出码

| 退出码 | 含义 |
|---|---|
| 0 | 采样成功（含"PLC 未运行""窗口内无中断增量"这类合法空结果） |
| 1 | 采集/数据/连接失败（adb 断、输出缺 SNAP/POINT 标记、/proc/stat 不可读） |
| 2 | 用法错误（含未设 `ANDROID_SERIAL`、参数非整数/超范围） |

- 查询失败 ≠ 无数据：采集非零退出或输出异常一律 FAIL 退出，不输出假结果；
- 读数失败 ≠ 0：单个读数失败显示 `NA`/`n/a`，不冒充 0.0。

## 明确不做

- 不编译、不部署、不重启、不改任何设备状态（采集器纯读 + sleep）；
- 不做断言判定（PASS/FAIL 是 verify 的事）、不做代码归因（那是 codegraph-nav 的事）；
- 不在 `--demo` 数据上出验收结论——demo 只证明脚本能跑。
