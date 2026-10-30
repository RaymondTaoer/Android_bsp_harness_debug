---
name: ab-experiment
description: 在 RK3562Android 设备上做可逆的 A/B 试验 —— 按包清单批量禁用/恢复应用，量开机时序对比，验证裁剪效果与故障假设。用于"禁用哪些包能缩短开机""这个崩溃是不是某包引起的""裁剪后 T3 改善了多少"这类问题。当需要修改设备状态（pm disable-user / pm enable / setprop / 停启容器）并需要留证据时使用。
---

# ab-experiment：设备侧可逆 A/B 试验

## 适用范围

- 在**真机**上批量禁用/恢复应用包，测量开机时序变化
- 验证某个包是否为故障源（如 system_server 崩溃循环）
- CODESYS 容器停/启的 A/B（RK3562 项目扩展）

**不适用**：编译、刷机、root 提权、永久删除 APK、`pm uninstall`、修改 `/system` 分区。

## 前置条件

| 条件 | 要求 | 失败表现 |
|---|---|---|
| 设备状态 | `adb get-state` = `device` | rc=1，拒绝继续 |
| 目标唯一 | 必须显式 `ANDROID_SERIAL` | rc=2，拒绝猜测目标 |
| 清单存在 | `features/boot-opt/ab-groups.tsv`（或 `-l` 指定） | rc=1，"清单不存在" |
| 权限 | `adb shell` 可执行 `pm`（非 root 也能 disable-user） | 逐包报异常，rc=1 |

> **序列号纪律**：本工具**不做**设备自动选择。多设备在线时必须显式指定，否则拒绝执行。

## 真实命令

```bash
# 前置：显式指定序列号（禁止留空）
export ANDROID_SERIAL=45bfd85c89194875

# 1) 看清单有哪些组、多少包（只读，零 adb 写操作）
bash features/.harness/bin/ab-experiment list
bash features/.harness/bin/ab-experiment list -g core

# 2) 看设备当前状态：清单覆盖的包 + 已禁用清单 + 关键 prop + 进程/温度
bash features/.harness/bin/ab-experiment status

# 3) 施加一档（可逆；只改包启用状态，不动 APK）
bash features/.harness/bin/ab-experiment apply -g core

# 4) 重启后量时序（用 boot-timing 取权威数字）
adb -s "$ANDROID_SERIAL" reboot
#   等设备回来后：
bash features/.harness/bin/boot-timing report -o debugdoc/docs/evidence/ab-core.csv
bash features/.harness/bin/ab-experiment verify

# 5) 回滚（完全可逆）
bash features/.harness/bin/ab-experiment revert -g core

# CODESYS 容器 A/B（RK3562 扩展）
bash features/.harness/bin/ab-experiment codesys-off   # 停容器 → 重启 → 量时序
bash features/.harness/bin/ab-experiment codesys-on    # 恢复
```

### 子命令

| 子命令 | 副作用 | 说明 |
|---|---|---|
| `list` | 无 | 列出清单条目（`-g` 按组过滤，可重复；`ALL` = 全部） |
| `status` | 无 | 清单全量 + 设备已禁用包 + 关键 prop + 进程数/温度/PLC CPU% |
| `apply` | **改包状态** | `pm disable-user --user 0 <pkg>`，逐包 |
| `revert` | **改包状态** | `pm enable --user 0 <pkg>`，逐包 |
| `verify` | 无 | 开机里程碑（T1/T2/T3/**T4**）+ BOOT_COMPLETED 广播耗时 + 慢接收者归因 + status |
| `codesys-off/on` | **停/启容器** | `setprop` + `ctl.stop/start` + 容器内进程 TERM→KILL |

### 选项

- `-g GROUP` 按组过滤，可重复；不带 = 全部组；`ALL` = 全部
- `-l FILE` 指定清单 TSV（默认 `features/boot-opt/ab-groups.tsv`）
- `--demo` 模拟数据，**零 adb 调用**，仅离线自测，**不是真机证据**

## ★ 判读 A/B 结果时必须看 T4，不能只看 T3

`verify` 输出的 `T4 真实空闲` = BC 广播**全部接收者完成**的时刻，比 T3（末个进程拉起）晚得多。

真机实测（45bfd85c89194875，2026-10-30）：

```
T1=45.38s  T2=46.79s  T3=52.74s   ← 只看 T3 会以为 53s 就空了
T4=114.09s                            ← 真实空闲点，晚 61.35s
complete=66477ms  receiversSize=25
```

拖尾元凶（`verify` 会自动抓出来）：

```
BroadcastQueue: Timeout of broadcast BroadcastRecord{... BOOT_COMPLETED}
                 - receiver=android.os.BinderProxy@bf110a5, started 60003ms ago
BroadcastQueue: Receiver during timeout ...: ResolveInfo{... com.android.phone/.vvm.VvmSimStateTracker}
```

**含义**：裁剪包若不触及这条广播链，T3 会变好而 T4 不变——**A/B 结论必须以 T4 为准**，
否则会得出"裁剪有效"的错误结论。

## 清单格式（唯一事实源）

`features/boot-opt/ab-groups.tsv`，**真 TAB 分隔、无 BOM、UTF-8**：

```
group<TAB>package<TAB>reason
```

| 组 | 包数 | 定位 | 风险 |
|---|---|---|---|
| `core` | 13 | 广播型包 + 无业务后台服务（广播风暴尾部） | 最保守的一档 |
| `extra` | 26 | 无硬件支撑的媒体/工具/壁纸/屏保 | 低 |
| `kioskA` | 4 | 确定无用（动态分区/相机/书签/备份确认） | 低 |
| `kioskB` | 16 | 高度可能无用（电话附加件/文档/MTP/代理/厂商应用） | 中——见下 |

> **`kioskB` 含 `com.android.providers.blockednumber`**：禁用它会消除"system_server 被 provider 权限异常打死"的故障源（2026-10-30 归因），但**紧急呼叫通知功能随之失效**——这是有意取舍，不是纯性能裁剪。

**修改清单**：直接编辑 TSV，不要在脚本里加硬编码数组（那是本工具要消除的反模式）。

## 建议的 A/B 阶梯

```
基线（不裁剪） → core → core+extra → +kioskA → 全量
每档：apply → reboot → boot-timing report -o <csv> → 对比 T1/T2/T3
```

一次只动一档；每档之间不要叠加未回滚的变更。

## 日志与证据位置

| 内容 | 位置 |
|---|---|
| 时序 CSV | `debugdoc/docs/evidence/ab-<组>.csv`（用 `boot-timing report -o` 生成） |
| 基线 CSV | `debugdoc/docs/evidence/boot-baseline-2026-10-30.csv` |
| 报告正文 | 本 skill 的 SKILL.md 不存报告；报告落 `debugdoc/docs/` 对应主题目录 |

**证据边界**：`--demo` 输出是模拟数据，**不得**作为设备行为结论的依据。真实结论必须有真机 `report` 输出 + 对应 boot_id。

## 失败语义

| 情况 | 行为 |
|---|---|
| 缺 `ANDROID_SERIAL` | rc=2，拒绝执行 |
| 设备非 `device` 状态 | rc=1，拒绝执行 |
| 清单不存在 | rc=1，不做任何修改 |
| 过滤后清单为空 | rc=1，**未做任何修改** |
| 单包 `pm` 失败 | 计入"异常"，全部处理完后 rc=1（**不回滚已成功的包**，靠 `revert` 显式回滚） |
| 查询失败 ≠ 不存在 | `pkg_installed` 用 `pm list packages -u` 精确匹配 `package:<name>`，不靠 grep 子串 |

**三态计数**：apply 输出"禁用 N 个，异常 M 个，未安装 K 个"——三者分开报，不合并成一个数字。

## 恢复条件

- `apply` 的逆操作是 `revert -g <组>`（只改包启用状态，APK 仍在）
- `codesys-off` 的逆操作是 `codesys-on`
- 两者都**不涉及分区写入**，无需重新刷机
- 若中途状态不明：`status` 查"设备上实际已禁用的包"列表，与 `list` 对照

## 明确不做

- 不 `pm uninstall`、不删 APK、不动 `/system`
- 不自动重启设备（重启由人决定，`boot-timing rounds` 才做批量重启）
- 不自动编译、不部署到 `/system`（那是 `deploy-and-accept` 的职责）
- 不在 `--demo` 模式下调用 adb（保证离线自测零副作用）

## 相关 skill

- `boot-timing` — 开机时序测量（本工具 `verify` 的权威数据来源在其）
- `perf-probe` — CPU/温度采样（`status` 的性能字段）
- `deploy-and-accept` — 部署事务（分区级改动走那条路）
