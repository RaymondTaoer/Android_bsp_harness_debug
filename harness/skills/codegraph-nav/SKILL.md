---
name: codegraph-nav
description: 在一棵树被切成多个隔离 codegraph 库的 BSP/Android 源码里定位与检索代码。用于"这个符号在哪、谁调用它、改动影响面多大"这类结构性问题，以及需要判断该用哪个一级根、该不该回退 ripgrep 的场景。
---

# codegraph 检索与路由

## 适用范围

- 目标文件位于**已安装 harness 的源码树**之下的**代码检索、调用链、引用、影响面**分析；
- 树的根清单不写死，**永远以路由表为准**：

  ```bash
  bash features/.harness/bin/cg-route --list    # 已登记的根 + 库路径
  ```

- **语言不限于 C/Java**：codegraph 支持 kotlin（`.kt`/`.kts`）、rust（`.rs`）、python、go、csharp、swift、dart、scala、php、ruby 等，但**是否可查取决于该根索引里是否真有这门语言**。判定方法：

  ```bash
  bash features/.harness/bin/cg-assert langs <root>   # 实测语言分布（同时是完整性探针）
  ```

  文件语言在该根输出里 → 可用 codegraph；不在 → ripgrep。

- 不适用于：`.aidl` / `.hidl` / `.dts` / `.dtsi` / `.bp` / `.mk` / `.xml` / `.json` / `.sh` 的查询，也不适用于被 `codegraph.json` 排除的目录（`out/` `build/` `tests/` `gen/` 等）—— 这些一律 ripgrep。

## 第一步：确定归属根（不要凭记忆）

```bash
bash features/.harness/bin/cg-route <任意文件或目录>
```

输出含：归属一级目录、`mcp_server`、`mcp_arg`、`mcp_tools`、`cli`、`db_status`。

- 根清单由 `features/harness.conf` 的 `ROOTS` 决定，由 `cg-roots sync` 生成路由表；
- 别名行（`ALIASES`，如 `kernel=kernel-5.10`）只做路由，不额外建库；
- 树根本身不归属任何一级根，`cg-route` 会拒绝；
- **同名子目录按最长前缀匹配，勿凭目录名猜**：例如顶层 `packages/` 与 `frameworks/base/packages/` 可能分属两个根，判据永远是 `cg-route` 的输出，不是路径里的 `packages` 字样。

> **已核实**：客户端只注册了一个 MCP server `codegraph`（`codegraph serve --mcp`），
> 工具名固定为 `codegraph_explore` / `_search` / `_node` / `_callers` / `_callees` / `_impact` / `_files` / `_status`。
> 选根靠**参数 `projectPath`**，不存在 `mcp__codegraph_<根>` 这类按根拆分的 server，也不存在 `--root` 参数。

## 第二步：查询

| 目的 | 命令 |
|---|---|
| 一次拿到符号源码 + 调用路径 | `codegraph explore -p <根> "<符号或自然语言>"` |
| 精确符号查找 | `codegraph query -p <根> -l 20 "<符号>"` |
| 单符号源码 + 上下游 | `codegraph node -p <根> "<符号>"` |
| 谁调用它 | `codegraph callers -p <根> "<符号>"` |
| 改动影响面 | `codegraph impact -p <根> "<符号>"` |

参数纪律（三端不一样，**不要混**）：

- CLI：`codegraph explore -p <一级根> "<query>"`
- MCP：`codegraph_explore({ query: "<query>", projectPath: "<一级根绝对路径>" })`
- SSE / HTTP 客户端：`projectPath=<一级根绝对路径>`

`--root` **不是** codegraph MCP 的参数；MCP 侧一律用 `projectPath`。

## 第三步：先验库的新鲜度

```bash
bash features/.harness/bin/cg-assert env --probe   # 全部根（含可查询性探测）
bash features/.harness/bin/cg-assert fresh <root>  # 单个根
```

- `STALE` / `MISSING` / `UNKNOWN` / `CORRUPT` / `ERROR` → 静态结论**一律标为"环境未就绪"**，不得当作事实；
- `codegraph status` 在 GB 级库上可能 >2 分钟，**禁止**在会话或 hook 里调用；
- 库只反映"上次索引时的状态"：最近改动过的文件必须用 `read` 复核；
- 大应用目录（Settings / Dialer / IMS 之类）符号集很大，**先 `query` 精确定位再 `explore`**，避免噪声淹没结论。

## 回退条件（满足任一即改用 ripgrep）

1. 文件语言不在该根 `cg-assert langs <root>` 的输出里（**不要**用固定扩展名白名单代替实测）；
2. 路径命中被 `codegraph.json` 排除的目录（`out/ build/ gen/ tests/ vts/ samples/` 等）；
3. 输出 `parse produced no symbols` 或工具报错；
4. `codegraph query` 无结果，但你知道符号刚新增（索引未同步）；
5. 库状态 `stale` / `missing`，或 `cg-assert langs` 返回 3（库缺失或 `database disk image is malformed`）。

回退时明确说一句：「codegraph 解析失败/未同步，切换 ripgrep 检索」。

## 输出规范

1. 每次结论前声明：`归属一级目录：<root>，使用 codegraph MCP（projectPath=<root>）`；
2. 跨一级目录时逐段切换，**禁止**用一个库查另一个库的符号；
3. `impact` 只在**同一个库内**跨文件；跨根影响面由 `cg-assert impact` 配合 `repos.tsv` 判定；
4. 无结果如实说明，禁止编造调用关系。

## 与守卫的配合

改源码前：

```bash
bash features/.harness/bin/check-drift <feature>
bash features/.harness/bin/cg-assert impact <root> "<符号>" features/<feature>/repos.tsv
```

第二行返回 `out-of-scope` 表示改动影响到了 `repos.tsv` 之外的根 —— 先停下来确认范围，再动手。
