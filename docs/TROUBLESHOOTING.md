# 排障手册（每条都来自实际踩坑）

## 0. 先看退出码，不要先看日志

| 码 | 你该做的事 |
|---|---|
| `1` | 是**代码/状态**问题：库过期、符号找不到、影响面越界、有漂移、有根建库失败 |
| `2` | 是**用法**问题：参数拼错、配置缺 `ROOTS`、feature 名非法 |
| `3` | 是**环境**问题：codegraph 缺失、库损坏、`adb` 不通、日志解析不出东西 |

把 `3` 当 `1` 处理，会花几小时改一段没问题的代码。

---

## 1. 假绿：文件在，库已烂

**症状**：`cg-assert env` 全绿，但 `codegraph explore` 报 `database disk image is malformed`。

**原因**：只判 `.codegraph/codegraph.db` 是否存在 / mtime 是否新。索引进程被 kill、
磁盘写满、`out of memory` 之后，db 文件仍在但内容坏了。

**做法**：`cg-assert env --probe` / `cg-ensure` 的第 4 步会对每个库**真打一次查询**。
见到 malformed 就重建该根：

```bash
codegraph index -f -p "Y:/RK3562Android/kernel-5.10"
```

**不要**为了让检查变绿去改判断逻辑。

---

## 2. `error: 未登记的一级目录：<自己树里的路径>`

**这是 Windows / Git Bash 专属坑，也是最容易误判成"路由表坏了"的一个。**

同一目录在 MSYS 下有多写法，且 `cd` 会记住进门写法：

```
cd "C:\Users\nt_DL\AppData\Local\Temp/x" && pwd -P   ->  /tmp/x
cd  "/c/Users/nt_DL/AppData/Local/Temp/x" && pwd -P  ->  /c/Users/nt_DL/AppData/Local/Temp/x
```

如果树根被规范化成 `/tmp/x`、传入路径被规范化成 `/c/Users/.../x`，前缀比较必然失败。

**修法**：`lib/common.sh` 的 `canon_path()` 用 `cygpath -w` 再 `to_msys`，两个方向都收敛到
`/c/...`。自己写新脚本时，**路径比较前两边都要过 `canon_path`**。

**自查**：

```bash
bash -c 'source harness/lib/common.sh; echo "[$HARNESS_ROOT]"; echo "[$(abs_path "Y:/some/path")]"'
```

两行应该同源（同为 `/c/...` 或同为 `/y/...`）。

---

## 3. `cg-ensure` 卡住不动

**原因**：第 4 步探活对 kernel 级库（3.2GB）执行 `codegraph query`，单次可能 >90s。

**做法**：已用 `timeout` 包住，默认 60s，超时输出 `SKIP ... INCOMPLETE`。要更长：

```bash
CG_PROBE_TIMEOUT=180 bash features/.harness/bin/cg-ensure --check
```

**不要**因为超时就判"库坏了"——那是没有结论，不是失败。

---

## 4. 路由表缺失 `.../features/.harness/codegraph-roots.tsv`

按顺序查：

1. 配置在不在：`features/harness.conf` 的 `ROOTS` 是否为空；
2. 生成没生成：`bash features/.harness/bin/cg-roots sync`；
3. harness 装在树里吗：`HARNESS_ROOT` 是否指向**源码树根**（不是仓库目录）。

> 开发模式下（仓库没装进树）必须显式给树根：
> `HARNESS_ROOT=Y:/RK3562Android bash harness/bin/cg-route ...`
> 否则它按"仓库位置向上三级"推导，会指到错误目录。

---

## 5. 首次建库报 `CodeGraph not initialized in <dir>`

`codegraph index` 不能在没有 `.codegraph/` 的目录上跑。首次必须：

```bash
codegraph init -y "Y:/RK3562Android/kernel-5.10"
```

`cg-build` 已按"有 `.codegraph/` → `sync`（或 `--force` 时 `index`）；没有 → `init -y`"分支处理。
`-y` 不能省，否则会交互等待。

---

## 6. 索引被中断，之后一直报 lock

```bash
codegraph unlock "Y:/RK3562Android/kernel-5.10"
codegraph daemon          # 看有没有残留 daemon，交互式停掉
```

---

## 7. SMB / 网络盘

| 症状 | 原因 | 处理 |
|---|---|---|
| `detected dubious ownership in repository` | SMB 上 owner 与本地账号不一致 | 所有 git 调用带 `-c safe.directory='*'`（`common.sh` 已内置）；不要手工 `chown` |
| `ln -s` 之后内容不同步 | SMB 上软链静默退化为复制 | 用 `sync-skills` 的复制 + 比对，不要软链 |
| 建库极慢 / CPU 打满 | 文件监听不停触发 | `codegraph serve --no-watch`（慢盘上） |
| 多根并行建库后日志串味 | IO 争抢 | 保持 `BUILD_SERIAL=1` |

---

## 8. `parse produced no symbols`

codegraph 解析该文件失败（常见于生成代码、非标准方言、超大文件）。

**立刻放弃 codegraph，切 ripgrep**，并在结论里注明"该处用 ripgrep 检索"。
不要对着一个空结果继续编调用关系。

---

## 9. 排除规则写了但没生效

`codegraph.json` 的 `exclude` 是 gitignore 风格，**相对项目根**，且**不支持 `!` 否定**。

- 写了 `out/` 但库在 `<根>/sub/out/` 下 → 不匹配，要写 `**/out/`；
- 写了但 **目录根本不存在** → 看起来生效了，实际什么也没挡住（`cg-exclude` 只写探测到的条目）；
- 改完 `codegraph.json` **必须重建**：`codegraph index -f -p <根>`，增量 `sync` 不会把已入库的文件踢出去。

---

## 10. 测试挂了，但看起来是"框架的锅"

先区分两类：

- **`PASS 空 assertions → RESULT INCOMPLETE` 之类失败** → 框架开始"帮你说好话"了，**优先级最高**，先修框架；
- **`uninstall 保留 .codegraph` 失败 且 用了 `--no-index`** → 该断言在没建库时本来就不成立，应当是 `SKIP`。
  这类断言缺失属于测试自身缺陷，要修测试而不是改产品行为。

`shellcheck 未安装` 记为 `SKIP`（不是 PASS）——想要这条检查就 `apt install shellcheck` / `choco install shellcheck`。

---

## 11. 设备侧工具（boot-timing / ab-experiment / perf-probe）

| 症状 | 处理 |
|---|---|
| `rc=2`，提示必须指定 `ANDROID_SERIAL` | 多设备在线时**不猜目标**，显式 `export ANDROID_SERIAL=<sn>` |
| 测得 T3 比真实空闲早很多 | 已知口径问题：BC 广播可能比 `boot_completed` 晚 60s+ 才完成，看 T4/`bc_done` |
| 开机时间算出负数或荒谬值 | 设备**无 RTC 电池**，早期日志带假时钟（epoch≈2017）。base 必须按 `/proc/stat` 的 `btime` 锚定 |
| 多轮测量后前一轮证据没了 | `logcat` 环形缓冲会被覆盖；归因证据要靠 `dropbox` / `pstore` 持久化来源 |
| `dmesg` 首行时间不可信 | 环形轮转后首行不是开机时刻；首行时间 > zygote 时间即不可据以计算 |
