# 双主机租约协议（服务器 / Windows）

> 适用：`Y:\RK3562Android`（Windows）与 `/home/<user>/workspace/RK3562Android`（服务器）
> **是同一份物理文件**（Samba `[work]` 导出 `/home/<user>/workspace`）。
> 本文件是租约协议的唯一事实源；实现见 `features/.harness/bin/harness-lease`。

## 1. 核心原则

**单端工作不需要申请租约。**

- 只有一端有会话（另一端没开 Claude / 不碰这棵树）→ 直接工作，不要 claim。
- 两端都在线、且可能碰同一资源 → 争用操作前 claim 对应 scope。
- 判断方式：`bash features/.harness/bin/harness-lease status`
  - `mode: single-host` → 单端，无需租约；
  - `mode: multi-host` → 多端，按下方 scope 申请。

在线状态由 `enter` / `leave` 维护（心跳 TTL 默认 240 分钟）：

```bash
bash features/.harness/bin/harness-lease enter --note "修 boot-opt"
bash features/.harness/bin/harness-lease leave
```

> `status` 本身不写心跳；长会话请先 `enter`，否则另一端看不到你在线。

## 2. Scope 与持有方

| scope | 允许持有方 | 何时 claim | 强制方式 |
|---|---|---|---|
| `codegraph-build` | **只能服务器** | 不需要人工 claim；`cg-build-server` 自动申请/释放 | Windows 上 `codegraph init/sync/index` 被 guard 直接拦截；另一台主机持有时 `cg-build-server` 以 `rc=4` 退出 |
| `device` | **只能 Windows** | 开**整段**设备会话前 claim（信号作用） | 服务器上任何 `adb` 被 guard 拦截；另一端持有时 Windows 的 `adb` 也被拦 |
| `code` | 任一端 | 两端在线且都要改源码时 | 护栏不强制，靠协议；真正并行用 `git worktree` |
| `build` | 建议服务器 | 多端且同时编译/产出时 | 护栏不强制 |

## 3. 常用命令

```bash
L=features/.harness/bin/harness-lease

bash $L status                                   # 在线主机 + 各 scope 状态 + mode 判定
bash $L enter --note "当前任务"                  # 标记本机在线
bash $L leave                                    # 标记本机离线

bash $L claim code   --ttl 120 --note "改 frameworks/base"   # 串行化源码改动
bash $L claim device --ttl 120 --note "验证 boot-opt"        # 设备整段会话
bash $L release device
bash $L check device                             # 0=空闲/本机持有；1=另一端持有
bash $L beat device --ttl 120                    # 续租
```

- 租约按 **hostname** 生效，带 TTL；过期可被自动抢占。
- 同一台机器的多个会话共用租约；并行工作请用
  `git worktree add ../RK3562Android-<task> <branch>` 隔离。
- 确认对方已失效时可用 `--force` 抢占/释放；先用 `status` 看清持有者与 note。

## 4. 交接流程（服务器 → Windows）

1. **服务器**：改代码 / 编译 → `handoff new` 写卡（改动文件、产物路径、Windows 验证命令、期望结果）；
2. **Windows**：`harness-lease enter` → `claim device` → `flash-verify` 证明产物身份 →
   执行设备验证 → 结果回填同一张卡 → `release device` → `leave`；
3. **服务器**：读回填结果，更新 `debugdoc`。

产物与卡片一律用**树内相对路径**，不要写 `Y:\` 或 `/home/...`。

## 5. 禁止事项

- 一端 `git checkout/reset` 切分支时，另一端仍在改同一批文件；
- 两端同时跑 codegraph 写操作（`init/sync/index`）；
- 两端同时驱动设备；
- 在服务器上安装/使用 adb，或用网络 adb 绕过。

## 6. 自检

```bash
bash features/.harness/bin/harness-doctor   # 含在线主机与租约状态
```

## 7. 相关文件

- 实现：`features/.harness/bin/harness-lease`
- 强制：`features/.harness/bin/adb-device-guard`、`features/.harness/bin/cg-build-server`
- 规则：根 `CLAUDE.md` 的「🖥️ 双主机」章节、`AGENTS.md` 的两端协作段
