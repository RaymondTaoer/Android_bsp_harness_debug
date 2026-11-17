# 调试知识库的规则架构设计

> 本文说明**为什么这么设计、以及它如何成为 harness 的一部分**。
> 规则正文随骨架部署到 `<树>/debugdoc/KB_PLAN.md`；L0 常驻入口是 `<树>/debugdoc/KB.md`。
> 框架仓库只保存**通用模板与协议**，不保存任何项目内部资料。

## 1. 要解决的问题

BSP 调试会在源码树里沉淀大量异构材料：原理图 PDF、评估记录、方案评审、补丁、
复现脚本、上机日志、trace、截图、录音。它们有三个特点：

1. **总量远超上下文**：一次全量加载会瞬间打爆 token 预算；
2. **无引用链**：结论散落在文档里，无法追溯到证据；
3. **多工具不一致**：不同 AI 客户端各读各的，容易「凭印象」给出结论。

所以知识库不是「文件夹整理」，而是**一套约束 AI 取证行为的协议**。

## 2. 四层渐进式披露

| 层 | 载体 | 体积上限 | 读取时机 |
|---|---|---|---|
| L0 | `KB.md` | ≤800 tokens | 会话第一步，之后不重读 |
| L1 | `index/debugdoc-<类>.md` | 单文件 ≤5KB | 类别路由后，只读 1–2 个 |
| L2 | 每篇文档的 front matter 摘要 | ≤200 tokens/篇 | 命中候选后 |
| L3 | 正文 | 按级别分级 | 确认需要后 |

单任务预算 ≤50K（L0+L1 ≤3K、L2 ≤5K、L3 ≤42K）。超预算先输出摘要再询问，
不静默截断、也不硬塞。

**关键取舍**：索引是**派生物**（`kb-index` 可随时重建），人工只维护少量注解与文档头部。
这样「整理」的成本从「持续手工维护目录」降到「结构变化后跑一条命令」。

## 3. 类别路由与 R0–R7

10 条路由（9 个内容类 + 官方 PDF）把任务信号映射到 L1 索引，避免全库扫描：

```
schematics · manuals · eval · plan · debug · patch · scripts · evidence · raw · rkdocs
源码符号/调用链 → 走 codegraph MCP（不进知识库）
```

R0–R7 是检索纪律：R0 只读 L0、R1 类别路由、R2 索引内筛选、R3 先摘要后全文、
R4 读取方式分级、R5 预算、R6 引用留痕、R7 不编造。

其中 **R7 与 harness 的诚实性铁律同源**：索引无条目 = 无内容，宁可说「没有」
也不臆测；这和 `RESULT INCOMPLETE ≠ PASS` 是同一条原则在两类资产上的体现。

## 4. 与 harness 四段证据的关系

| harness | 知识库 |
|---|---|
| `STATIC` 符号/调用链结论 | eval / debug 类分析结论 |
| `BUILD` 构建判定（`verify-build` 不执行构建） | plan / scripts 类构建记录与脚本 |
| `DEVICE` 上机测量 | evidence / raw 类日志、trace、截图 |
| `FEATURE` 阈值由人写 `assertions.tsv` | plan 类方案与评审 |

**互不替代**：知识库里的「评估结论」不是验收证据；harness 的 `INCOMPLETE`
也不等于「没有结论」。二者各自如实标注，避免出现「文档里写了就算验证通过」。

## 5. 纳入框架的形式

| 位置 | 内容 | 是否入库 |
|---|---|---|
| `harness/kb/*.template` | L0 入口、规则正文、类别说明模板（含占位符） | 是（通用、脱敏） |
| `harness/bin/kb-init` | 幂等部署骨架到 `<树>/debugdoc/`，默认不覆盖；维护树根 `/debugdoc/` 忽略项 | 是 |
| `harness/bin/kb-index` | 纯 bash 重建 L1 分类索引与官方 PDF 主题树 | 是 |
| `harness/bin/pdf2md` | PDF → md：溯源头部、页码锚点、sha256 指纹去重、扫描件 OCR 回退 | 是 |
| `harness/skills/debugdoc-kb/SKILL.md` | AI 代理的 R0–R7 纪律 | 是（随 `sync-skills` 分发） |
| `harness/skills/pdf-to-md/SKILL.md` | AI 代理的 PDF 取用与转换纪律 | 是（随 `sync-skills` 分发） |
| `<树>/debugdoc/` | 规则 + 空目录 + 团队沉淀的内容；**自身是独立 git 仓库** | **否**（父树 `.gitignore` 排除） |
| `docs/kb/`（仓库工作区） | 任何真实项目的内部资料 | **否**（被 `.gitignore` 忽略） |

`install.sh` 复制整个 `harness/`，所以模板与两个命令随框架自动到位；
但 **`debugdoc/` 不自动创建** —— 是否建立知识库属于项目决策，显式执行 `kb-init` 才落盘。

模板用 `.template` 后缀与 `__PROJECT__` / `__CATEGORY__` 占位符，明确表达
「这是骨架模板，不是知识正文」，也避免把任何项目的资料混进发行分支。

## 6. 边界与风险

- **骨架不含内容**：客户评估、原理图、补丁、测量数据由本树团队自行沉淀，
  **不得从其它项目复制**；`kb-init` 只写规则与空目录。
- **不擅动用户文件**：官方 PDF 库、`features/`、源码树一律不动，只通过索引与引用协议接入。
- **索引漂移**：文件移动/改名后必须重跑 `kb-index`。
- **ID 非稳定标识**：`D-xxxx` 等编号随重建变化，权威引用是相对路径。
- **token 预估**为粗算，用于分级预警，不做精确计费依据。
- **PDF 纪律**：官方 PDF 先转 md 落 `docs/rkdocs-md/` 再引用，禁止整本加载；
  统一走 `pdf2md`（溯源头部 + 页码锚点），并按 sha256 指纹去重 —— 同一 PDF 只转一次，
  改名也不会重复转。扫描件/原理图用 `--ocr`，脚本在文本产出近空时会自动回退。
- **独立仓库**：`debugdoc/` 自带 `.git`，父树用 `/debugdoc/` 排除。好处是提交粒度按知识内容走、
  不受 BSP 树几十万文件影响；代价是两套历史，**内容只在知识库仓提交**，不要在源码树侧 `git add -f`。
- **PDF 原件不入库**：知识库仓库只收 md 与索引。原理图、扫描件动辄几十 MB，
  进仓库会让 clone 与 diff 变慢；原件留在 `RKDocs/` 或本地资料目录，用 `RKDocs:<相对路径>` 引用。

## 7. 命令速查

```bash
bash features/.harness/bin/kb-init --dry-run          # 只看计划
bash features/.harness/bin/kb-init --project "<代号>"  # 建骨架（幂等）+ 树根忽略 /debugdoc/
bash features/.harness/bin/kb-init --git-init          # 同时建独立仓库并首次提交
bash features/.harness/bin/kb-index                   # 重建 L1 索引
bash features/.harness/bin/pdf2md --check              # PDF 引擎体检（exit 3 = 缺依赖）
bash features/.harness/bin/pdf2md RKDocs/<主题>/<文件>.pdf
bash features/.harness/bin/pdf2md --ocr --dpi 300 <扫描件.pdf>
bash features/.harness/bin/sync-skills                # 分发 debugdoc-kb / pdf-to-md skill
```

验收口径：L0 ≤800 tokens；单 L1 ≤5KB；随机 5 个任务关键词按 R0–R7 走查能在
≤50K tokens 内找到文档并带引用；索引无条目时能如实说明。

## 8. 问题落盘策略：三层分级 + 闸门三问

**评估结论（2026-11-17）：不把源码树里「所有已解决的问题」自动落盘成知识库文档。**
全部自动落盘有三个代价：L1 索引超预算（单索引 ≤5KB 的验收口径被淹没）、
低复发问题成为检索噪声、以及把没有四段证据的「已解决」写成看似权威的记录
（违反诚实性铁律 —— 与「阈值由人写」同一逻辑）。改为三层分级：

| 层级 | 载体 | 成本 | 适用 |
|---|---|---|---|
| L-a 默认层 | git 提交信息 + `handoff` 接力卡 | 全自动、零落盘 | 一次性、低复发问题 |
| L-b 台账层 | `debugdoc/docs/debug/resolved-ledger.tsv`（一行一问题，TAB 分 5 列：date/症状/根因/修法/关联） | 追加一行 | 根因或修法值得记，但不需要全文 |
| L-c 文档层 | 完整排查文档（命名 + L2 头部） | 全文 | **闸门三问命中 ≥2 条** |

**闸门三问**（R6 落盘前逐条判断，纪律写在 `debugdoc-kb` skill 与 `KB_PLAN.md` 4.4）：

1. 根因非显而易见？（隔协议层 / 构建系统 / 时序，如 ZIP2ZIP 剥 APK 签名）
2. 平台级、会复发？（SELinux / PMS / 预装 / dts / RIL / boot 链路）
3. git 查不到？（知识是「为什么」，不是「改了什么」—— git log + `handoff` 已覆盖后者）

| 命中数 | 落盘层级 |
|---|---|
| ≥2 | L-c 完整文档 |
| 1 | L-b 台账加一行（先 `rg` 症状去重） |
| 0 | 不进知识库，git + `handoff` 兜底 |

与 `handoff` 同一条设计哲学：**AUTO 填事实，HUMAN 定结论** —— AI 只产出落盘草稿
（可由 handoff AUTO 段 + git diff 自动汇总候选），闸门判断与「已解决」的宣称留给复核；
台账与文档状态列不写「已验证」，无证据按 `INCOMPLETE` 标注。台账随 `kb-index`
进 debug 类索引，禁止把台账写成第二份全文（单一事实源）。

落地形式：`kb-init` 部署台账空表（`docs/debug/resolved-ledger.tsv`）；
`KB.md` 模板路由表加台账指针；`KB_PLAN.md` 模板 4.4 节为规则正文。
