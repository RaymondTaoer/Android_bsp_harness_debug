---
name: adb-device-debug
description: 通过 adb 对已连接的 RK3562 设备做只读取证/调试时的统一要求（序列号纪律、三条会把整机搞挂的红线、Git Bash 路径改写与 CRLF 陷阱、批量合并与脚本化、常用取证命令模板）。用于任何 adb 探测、日志取证、上机验证、现象复现的场合。
---

# adb 设备调试要求（RK3562）

## 何时用

任何通过 adb 接触已连接设备的时候：取证、复现、验证、抓日志、读寄存器/GPIO。
**目的**：把历史上真实搞挂过整机、以及大量返工的命令写法固化成硬规则。

## 一、前置纪律

1. **序列号显式指定**，不自动取 `adb devices` 第一台（多台时选错设备等于毁掉一次实验）：
   ```bash
   : "${S:?设置 S 为已确认的设备序列号}"
   adb -s "$S" get-state      # 必须返回 device
   ```
2. **只读优先**：不 `adb root` / `adb remount` / `adb shell su`，不写 `/data`、不清数据、不改分区（除用户明确授权且走 deploy-and-accept）。
3. 拿设备现象下结论**之前**先跑 `flash-verify`，否则测的可能是旧产物。

## 二、三条红线（真实事故，违反会整机重启/掉线）

| # | 禁止 | 后果 |
|---|---|---|
| 1 | 读 `/proc/iep` | RK3562 上必然 panic 并重启整机 |
| 2 | 对 `/proc`、`/sys`、`/dev` 递归 `grep -r` / `cat -r` / `find -exec cat` | chroot 的 `/proc` 挂在 `/data` 下，一次递归就会命中上一条 |
| 3 | 无超时的长命令 / cpuset 类迁移 | `adb shell` 挂死，只能断电重启 |

补充：`/proc/iep` 的 `simple_read_from_buffer` 修复**尚未确认已上机**，在 `flash-verify` 证明新 kernel 生效前一律按"会 panic"对待。

## 三、命令写法（每条都踩过）

1. **Git Bash 路径改写**：裸 `/sys/...` 参数会被改写成 `C:/Program Files/Git/sys/...`，adb 报 `No such file`。
   远端命令**整条作为一个引号参数**传，并关掉转换：
   ```bash
   adb -s "$S" shell 'cat /proc/version'                              # 对
   MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' adb -s "$S" shell '...' # 更稳
   adb -s "$S" exec-out cat /sys/firmware/fdt                         # 错
   ```
2. **输出是 CRLF**：`1   3  \r  \n`。解析前必须去掉，否则字符串比较永远失败：
   ```bash
   v="$(adb -s "$S" shell 'getprop ro.build.version.release')"; v="${v//$'\r'/}"
   ```
3. **二进制用 `exec-out`**，不要用 `shell`（shell 会过终端层做换行处理）：
   ```bash
   adb -s "$S" exec-out 'head -c 16 /dev/urandom' | wc -c     # 16
   ```
4. **批量合并**：每次 adb 调用约 1 秒（实测 3 次独立 2.1s vs 合并一次 1.2s）。一次 `shell` 里用 `;` 串起来，别拆成十次调用。
5. **复杂逻辑 push 脚本跑**，不要内联嵌套引号（历史多次因引号错误搞坏命令）：
   ```bash
   adb -s "$S" push ./probe.sh /data/local/tmp/probe.sh
   MSYS_NO_PATHCONV=1 adb -s "$S" shell 'sh /data/local/tmp/probe.sh' 2>&1 | tee probe.log
   ```
   脚本用 ASCII + LF，避免 PowerShell 5.1 按 UTF-8 解析失败（构建/打包脚本同样走 bash，不走 PowerShell）。
6. **`logcat` 必须限界**：`-d -t N`（只取最近 N 行）+ 指定 buffer（`-b crash`/`-b main`）+ 必要时 `--pid`。不要无界 `logcat -v threadtime`。
7. **`dmesg` 通常需要 root**，读不到不是"没有日志"，如实记 `SKIP/查询失败`。

## 四、常用只读取证模板

```bash
S=<serial>
MSYS_NO_PATHCONV=1 adb -s "$S" shell '
  echo "== boot =="; getprop sys.boot_completed; getprop ro.build.date.utc
  echo "== boot_id =="; cat /proc/sys/kernel/random/boot_id
  echo "== kernel =="; cat /proc/version
  echo "== uptime =="; cat /proc/uptime
  echo "== svc =="; pidof system_server
  echo "== irq =="; cat /proc/interrupts
' 2>&1 | tr -d '\r'
```

| 目标 | 命令 |
|---|---|
| 崩溃日志 | `adb -s $S logcat -b crash -d -t 200` |
| 平台识别 | `cat /sys/firmware/devicetree/base/compatible`（**不要**用 `ro.hardware`，本板是 `rk30board`） |
| 设备树回读 | `cat /sys/firmware/devicetree/base/<node>/<prop>` |
| DTB 路径定位 | `find /sys/firmware/devicetree/base -maxdepth 1 -name 'serial@fe670000'` |
| GPIO（需 root） | `cat /sys/kernel/debug/gpio` |

## 五、结果判定

- `PASS` / `FAIL` / `INCOMPLETE` 三态，`INCOMPLETE` 不等于失败、不等于通过；
- **查询失败 ≠ 不存在**：命令非 0 退出或空输出时，输出 `查询失败(<cmd>)`，不得写成"该服务不存在"；
- 结论必须贴设备原始输出，不贴推论。

## 六、机械护栏（PreToolUse 自动拦截，2026-10-31 落地）

上面的红线是"约定遵守"——agent 仍可能因内联裸敲命令而绕过。因此本 harness 提供**机械拦截器** `features/.harness/bin/adb-device-guard`，在任何 Bash 工具执行前自动扫描命令，命中即 block 并回原因（让 agent 自我纠正），干净则放行。

**拦截的四类命令**：
1. 访问 `/proc/iep`（红线#1，panic）；
2. 对 `/proc`、`/sys`、`/dev` 递归 `grep -r` / `find`（红线#2，挂死/命中 iep）；
3. 连续 `adb logcat` 无 `-d` 且无 `timeout`、`adb wait-for-*` 无 `timeout`（红线#3，卡死 agent）；
4. 直接 `pm disable/uninstall` 系统硬依赖包（`com.android.sdksandbox` / `systemui` / `launcher3` / `settings` / `android`）—— 防 brick（2026-10-31 实测 brick 教训）。

**接入方式**（Claude Code / OpenCode，已在仓库根 `.claude/settings.json`、`.opencode/settings.json` 注册）：
```json
{ "hooks": { "PreToolUse": [ { "matcher": "Bash",
    "hooks": [ { "type": "command",
      "command": "python3 Y:/RK3562Android/features/.harness/bin/adb-device-guard" } ] } ] } }
```
- **仅对 Bash 类工具生效**，其它工具（Write/Read/Edit）一律放行；
- **失败开放**：stdin 为空 / JSON 解析失败时放行，绝不因脚本故障阻断正常开发；
- **零误报**：普通编辑/git/编译命令、harness 自带工具（已全程 `timeout`+不碰 `/proc/iep`）一律放行。

**自检**（改完必须跑）：
```bash
python3 Y:/RK3562Android/features/.harness/bin/adb-device-guard --selftest
# 期望 22/22 passed
```

> 注：护栏是"最后一道机械防线"，与 `ab-experiment` 内置的系统硬依赖黑名单（清单级）构成双重防护——即使 agent 绕过 skill 红线裸敲 `pm disable-user com.android.sdksandbox`，也会被本护栏拦下。

## 上下文卫生（Token 纪律，2026-10-31 据 token 降本策略落地）

- **大日志不进对话**：`logcat -d -t N` 已限界（见命令写法第 6 条）。取证后只在工具/脚本内提炼结论，原始数十 MB 日志不要整段贴进对话，否则会撑爆上下文、拉高每轮 token。
- **能用离线/演示模式就用**：验证流程本身用 `--demo`/`--skip-static`（如 `verify-boot-opt.sh --demo --skip-static`），不拉设备态进上下文。
- **harness 自进化要批量、要先验证**：改 `CLAUDE.md`/`SKILL.md`/`*.tsv` 会触发缓存前缀失效（下一会话一次 cache-miss），所以**同一次会话内把多个改动攒齐再 `sync-skills` 分发**，且改动前先本地跑 `features/.harness/tests/test-harness.sh`（约 6m27s / 63 项）确认无误，避免"改了又改"反复失效前缀。
- 完整策略见 `features/.harness/docs/token-reduction-strategy.md`。

## 明确不做

- 不自动选设备、不 `adb root/remount`、不清数据、不刷机；
- 不递归遍历 `/proc` `/sys` `/dev`；
- 不把"命令跑通"当成"功能验收通过"。
