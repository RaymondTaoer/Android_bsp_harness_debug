---
name: deploy-and-accept
description: 把单文件产物部署到已确认的 Android 设备并完成验收（备份、原子替换、失败回滚、reboot 后 boot_id 与 sys.boot_completed 校验）。用于用户明确授权上机验证、且已经拿到本次构建产物时。
---

# 部署与验收

## 前置条件（缺一即停）

1. 用户**显式确认**目标设备序列号；`ANDROID_SERIAL` 必须由人设置，不猜、不取第一个设备；
2. 已通过 `verify-build` 判定本次构建有效（成功标记 + 产物 mtime）；
3. 已跑 `check-drift` 且无 DRIFT；
4. 明确本轮是否允许 reboot —— **部署与烧写不等同于授权刷机、清数据或改分区**。

```bash
: "${ANDROID_SERIAL:?设置 ANDROID_SERIAL 为已确认的目标序列号}"
adb -s "$ANDROID_SERIAL" get-state        # 必须返回 device
```

## 事务契约（不可省略的 5 步）

本框架**不提供**自动化部署脚本；以下契约要求在实现入口时逐条满足，手工执行时同样按序：

| 步 | 要求 | 失败处理 |
|---|---|---|
| 1 备份 | 原文件复制到 `/data/local/tmp/harness-backup/<feature>/<ts>/`，记录 `sha256sum` 与 `ls -lZ` 元数据 | 备份不完整 → 中止，不得继续 |
| 2 暂存 | 新文件 push 到**同分区**的 `*.new`，校验 sha256 与本地一致 | 校验不符 → 删除暂存，中止 |
| 3 替换 | `mv` 原子替换（同目录同分区），不用 `cp` 覆盖 | 失败 → 用备份回滚 |
| 4 权限 | 恢复原 `uid:gid:mode`；必要时 `restorecon` 并检查返回码 | `restorecon` 失败 → 视为失败并回滚 |
| 5 生效 | `adb reboot` 后在**新 boot_id** 下等待 `sys.boot_completed=1` | 超时/旧 boot_id → 标记 `RESULT FAIL`，不得报成功 |

> 直接 `adb push` 覆盖正在被 mmap 的 ELF（`lib*.so`、`app_process`、`system_server` 相关）会触发不可预测行为；这类目标一律走"整包烧写"而不是单文件替换。

## 典型目标

| 产物 | 目标路径 | 生效方式 |
|---|---|---|
| `services.jar` / `framework.jar` | `/system/framework/` | 替换后需评估 ART / dexpreopt 缓存；不确定时重新整包烧写 |
| HAL `.so` | `/vendor/lib64/` | 替换 + `reboot`；检查 `logcat -b crash` |
| sepolicy | 随 `boot.img` / `vendor_boot.img` | **不单文件替换**，整包烧写 |
| kernel `Image` | 随 `boot.img` | 整包烧写 |

> 目录布局因平台而异（`/system` vs `/system_ext` vs `/vendor_dlkm`）。落盘前先 `adb shell ls -lZ <目标目录>` 确认实际路径与 SELinux 标签。

## 验收断言（`verify-<feature>.sh` 的 DEVICE 段）

```bash
adb -s "$ANDROID_SERIAL" shell getprop sys.boot_completed        # = 1
adb -s "$ANDROID_SERIAL" shell cat /proc/sys/kernel/random/boot_id  # 与部署前不同
adb -s "$ANDROID_SERIAL" shell pidof system_server                # 非空
adb -s "$ANDROID_SERIAL" shell service list | grep -F '<svc>:'    # 字段边界精确匹配
adb -s "$ANDROID_SERIAL" logcat -b crash -d -v epoch,nsec -T <boot 基线>
```

- 查询命令失败 ≠ "不存在"：必须保留退出码，输出 `FAIL <查询失败>`；
- `logcat -b crash` 的时间基线用 `/proc/stat` 的 `btime` 或显式 `--since`；
- 平台专属检查写进 `verify-<feature>.sh`，不要塞进本 skill（示例见仓库 `examples/`）。

## 结果协议

| 输出 | 含义 | 退出码 |
|---|---|---|
| `RESULT PASS` | 全部必需断言通过，无 SKIP | 0 |
| `RESULT FAIL` | 任一断言失败或查询失败 | 非 0 |
| `RESULT INCOMPLETE` | 环境未就绪（无设备/未构建/未授权） | 非 0 |

`INCOMPLETE` 即使在 `--allow-skip` 下退出 0，也不是验收通过。

## 明确不做

- 不自动选择设备、不自动 `adb root/remount`；
- 不自动清 `/data/dalvik-cache/`、不自动 wipe；
- 不把"部署成功"报告为"功能验收通过"——两者分别报告。
