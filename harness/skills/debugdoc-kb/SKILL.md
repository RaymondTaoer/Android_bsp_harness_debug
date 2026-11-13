---
name: debugdoc-kb
description: 在装有 harness 的 BSP/Android 源码树里按渐进式披露协议检索调试知识库（debugdoc）。用于查找评估、方案、调试记录、补丁、证据与官方 PDF 资料，以及判断该读哪一层索引、何时如实说明「索引无条目」。
---

# 调试知识库检索（debugdoc）

## 适用范围

- 树里已用 `bash features/.harness/bin/kb-init` 建立 `debugdoc/` 骨架；
- 任务是「找某次调试记录 / 评估结论 / 方案评审 / 补丁 / 上机证据 / 官方手册」；
- **不适用于**源码符号与调用链 —— 那走 codegraph MCP（`projectPath` = `cg-route`
  命中的最长前缀目录，见 `codegraph-nav`）；非源码的文本、配置、宏走 ripgrep。

## 第一步：R0 只读 L0

```bash
cat debugdoc/KB.md        # ≤800 tokens，唯一常驻入口；此后不重读
```

**禁止**启动即扫描整个 `debugdoc/` 或官方 PDF 库。完整规则在
`debugdoc/KB_PLAN.md`（只在需要查规范细节时读）。

## R0–R7（强制）

| 步 | 动作 | 硬约束 |
|---|---|---|
| R0 | 只读 `KB.md` | ≤800 tokens |
| R1 | 任务→类别→读命中类别 1–2 个 L1 索引 | 单文件 ≤5KB；不得一次读全部索引 |
| R2 | 索引内关键词过滤；大索引只 rg | `_index.json` / `rkdocs-full.json` 禁止整读 |
| R3 | 先读候选文档 L2 头部摘要 | 不跳过摘要直接读全文 |
| R4 | md 按节读；PDF 先转 md 再定向抽取 | 禁止 PDF 整本加载；单次 ≤5K tokens |
| R5 | 单任务 ≤50K tokens（L0+L1 ≤3K，L2 ≤5K） | 超预算先出摘要再问 |
| R6 | 结论引用来源；新结论按命名规范落盘 | 引用 = 相对路径 / `[D-xxxx]` / `RKDocs:<路径>` |
| R7 | 索引无条目即如实说明 | 禁止臆测文档内容 |

类别路由（L1 文件）：`schematics` / `manuals` / `eval` / `plan` / `debug` /
`patch` / `scripts` / `evidence` / `raw` / `rkdocs`，对应
`debugdoc/index/debugdoc-<类>.md`（官方 PDF 为 `index/rkdocs.md`）。

## 索引与内容维护

```bash
bash features/.harness/bin/kb-init --dry-run    # 看骨架计划（幂等、默认不覆盖）
bash features/.harness/bin/kb-init              # 首次建骨架
bash features/.harness/bin/kb-index            # 新增/移动/改名/删除文档后重建 L1 索引
```

- `index/` 是**派生物**，勿手改；结构变化后必须重跑 `kb-index`，否则索引漂移。
- 新文档命名 `<项目代号>_<主题>_<类型>_<YYYYMMDD>.md`，首部写 L2 front matter
  （类型/子系统/日期/状态/摘要），规范见 `KB_PLAN.md` 第 4 节。
- 引用格式：`[D-xxxx]` 文档 / `[P-xxxx]` 补丁 / `[S-xxxx]` 原理图 /
  `RKDocs:<相对路径>`。**相对路径是权威引用**，ID 随索引重建可变。

## 官方 PDF 资料

- 目录名即主题，不重排、不复制。
- 引用前必须先用本环境的 `pdf` / `pdf-to-markdown` 类能力转成 Markdown，
  落盘 `debugdoc/docs/rkdocs-md/<主题>/<文件名>.md`，头部标注来源与转换日期。
- 同一 PDF 只转一次；转换前先查 `index/debugdoc-manuals.md` 或 `rg docs/rkdocs-md`。
- 转换后重跑 `kb-index`，此后按 R0–R7 引用该 md。

## 与 harness 验收的边界

| harness | 知识库 |
|---|---|
| `STATIC` 段 | eval / debug 类分析结论 |
| `BUILD` 段 | plan / scripts 类构建记录 |
| `DEVICE` 段 | evidence / raw 类上机测量与日志 |
| `FEATURE` 段 | 阈值由人写进 `features/<feature>/assertions.tsv` |
| `RESULT INCOMPLETE` | 索引无条目同样如实说明（R7） |

**知识库里的「结论」不能替代四段证据**；`INCOMPLETE` 也不等于「没有结论」。
两者都按各自口径如实标注，禁止把没验证说成验证通过。

## 输出规范

1. 结论必须带来源引用（相对路径优先）；
2. 找不到写「索引无条目」，不编造文档或结论；
3. 跨类别检索逐层切换，不一次加载全部 L1；
4. 明确区分「知识库检索」与「codegraph / ripgrep」三种手段，切换时说明原因。
