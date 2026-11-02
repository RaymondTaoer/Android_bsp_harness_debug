---
name: flash-verify
description: 在拿设备功能现象下结论之前，证明"设备上跑的确实是本次构建的产物"（本地 Image ↔ boot.img ↔ 设备 /proc/version ↔ 设备 DTB 属性回读）。用于改动 kernel/DTS/init.rc/sepolicy 后上机验证、或现象与预期不符时先排除"没刷/刷了旧的/没重打包"。
---

# 刷机产物身份判定（RK3562）

## 为什么必须做

最贵的返工不是改错代码，而是**拿旧产物判断新补丁**。实测（2026-10-30）：

```
本地 kernel-5.10/arch/arm64/boot/Image : #2 SMP PREEMPT Fri Oct 30 11:16:14 CST 2026
设备 /proc/version                     : #1 SMP PREEMPT Thu Oct 29 14:38:52 CST 2026
```

只看功能现象会得出"补丁无效"，实际一次都没刷上去。同类事故还包括：改了 DTS 但设备跑旧 DTB、编了 Image 但没重打包 boot.img。

**判定器不刷机**，只回答一个问题：设备上的产物 == 本地刚构建的产物吗？

## 一页命令

```bash
bash features/.harness/bin/flash-verify --serial <已确认序列号> \
  [--expect '<node>:<prop>=<value>']... \
  [--kernel-image <path>] [--boot-img <path>]
```

判定 4 项：

| 项 | 抓什么事故 |
|---|---|
| 本地产物存在 | 根本没建出来 |
| 本地 boot.img 内 kernel == 本地 Image | 编了但没重打包 |
| 设备 `/proc/version` 构建戳 == 本地 Image 构建戳 | 没刷 |
| `--expect` 回读设备 DTB 属性 | 旧 DTB / DTS 没编进去 |

耗时约 20 秒（Y: 是 SMB 网络盘，本机每次外部命令 spawn 约 1 秒；banner 抽取结果按 path+mtime 缓存在 `features/.harness/.state/flash-verify/`）。

## 改过 DTS 时：从 diff 推导 `--expect`

```bash
git -C kernel-5.10 diff -- 'arch/arm64/boot/dts/rockchip/*.dts*'
```

挑出**改动过的属性**，转成 `--expect`。设备树节点路径拿不准时，先问设备：

```bash
S=<serial>
# 有 alias 的 label 可直接映射（不保证都存在）
adb -s $S shell 'cat /sys/firmware/devicetree/base/aliases/i2c3'
# 否则按节点名（含地址）找
adb -s $S shell "find /sys/firmware/devicetree/base -maxdepth 1 -name 'serial@fe670000'"
```

典型用法：

```bash
# &i2c3 下某从设备改成 okay
--expect '/i2c@ffa20000/rtc@51:status=okay'
# 根节点 compatible 变更
--expect ':compatible=rockchip,rk3562-evb2-ddr4-v10 rockchip,rk3562'
```

**限制**：本工具只比对**字符串属性**（`status`/`compatible`/`model`/`label` 等）。
`rockchip,pins = <...>`、`reg = <...>` 这类数值属性回读出来是二进制，无法这样比对——改用功能断言（`/sys/kernel/debug/pinctrl`、驱动 probe 日志等）。

## 结果怎么用

| 输出 | 含义 | 下一步 |
|---|---|---|
| `RESULT PASS` (0) | 设备跑的是本次产物 | 才能开始看功能现象；PASS ≠ 功能验收通过 |
| `RESULT FAIL` (1) | 产物不一致 / DTB 回读不符 | **先刷机**，不要改代码，不要下"补丁无效"结论 |
| `RESULT INCOMPLETE` (3) | 环境未就绪（无设备/无产物/未给序列号） | 不算失败，补齐前置条件后重跑 |

`INCOMPLETE` 永远不能当作"验证通过"或"验证失败"。

## 环境陷阱（已实证，必看）

1. **MSYS 路径改写**：Git Bash 会把裸 `/sys/...` 参数改写成 `C:/Program Files/Git/sys/...`，adb 收到后报 `No such file or directory`。
   规则：远端命令**整条作为一个引号参数**传给 adb，并加 `MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'`。
   ```bash
   adb -s $S shell 'cat /proc/version'          # 对
   adb -s $S exec-out cat /sys/firmware/fdt     # 错：/sys 被改写
   ```
2. 序列号必须由人确认，**不自动取 `adb devices` 第一台**。
3. `ro.hardware` 在本板是 `rk30board`（不是 `rk3562`），别用它判断平台；用 `cat /sys/firmware/devicetree/base/compatible`。

## 明确不做

- 不自动刷机、不清数据、不改分区；
- 不自动选设备、不自动 `adb root/remount`；
- 不把"产物一致"报告成"功能验收通过"——两者分别报告；
- 不递归 grep/read `/proc`、`/sys`、`/dev`（读 `/proc/iep` 会 panic 并重启整机）。
