---
name: pdf-to-md
description: 把 RKDocs 官方文档、原理图、芯片数据手册等 PDF 转成可检索复用的 Markdown，并落进 debugdoc 知识库。用于"要引用某个 PDF 的寄存器表/时序/引脚定义"、"要批量把资料库转成文本"、"扫描件或图片型 PDF 读不出文字"这类场景。禁止整本加载 PDF 原文。
---

# PDF → Markdown（知识库入库前置步骤）

## 为什么必须转

PDF 不能按需切片读取：整本加载一本 TRM 就是几十万 tokens，且无法用关键词定位。
知识库规则（`debugdoc/KB_PLAN.md` 第 6 节）要求**先转 md、再定向检索**，一份 PDF 只转一次、长期复用。

## 0. 先体检，别猜

```bash
bash features/.harness/bin/pdf2md --check
```

输出会告诉你：哪个引擎可用、OCR 依赖是否齐、`RKDocs` 有多少 PDF、已转换多少。
**退出码 3 = 一个引擎都没有**，此时不要伪造结果，直接把安装命令交给用户（需要服务器侧执行）：

```bash
pip install pymupdf4llm                                     # 首选：结构化最好、最快
apt install poppler-utils                                   # 兜底：pdftotext
apt install poppler-utils tesseract-ocr tesseract-ocr-chi-sim   # 扫描件 / 图片型原理图
```

## 1. 转换

```bash
# 单文件（RKDocs 内路径会自动映射到 debugdoc/docs/rkdocs-md/<主题>/）
bash features/.harness/bin/pdf2md RKDocs/<主题>/<文件>.pdf

# 整个主题目录（递归，保留子目录层级）
bash features/.harness/bin/pdf2md RKDocs/<主题目录>

# 大手册只要关键章节
bash features/.harness/bin/pdf2md --pages 120-180 RKDocs/<主题>/<大手册>.pdf

# 扫描件 / 图片型 PDF（只能取文字，没有拓扑）
bash features/.harness/bin/pdf2md --ocr --lang chi_sim+eng --dpi 300 docs/sch/<板名>.pdf

# 矢量原理图：文字清单 + 候选网络表 + 图形统计
bash features/.harness/bin/pdf2md --schematic docs/sch/<板名>_sch.pdf

# 原理图转出来放错类别时，用 --out 指定输出根
bash features/.harness/bin/pdf2md --out debugdoc/docs/schematics docs/sch/<板名>.pdf

# 只看计划、不写盘
bash features/.harness/bin/pdf2md --dry-run RKDocs/<主题目录>
```

产物路径：`debugdoc/docs/rkdocs-md/<RKDocs 内相对路径>.md`；非 `RKDocs` 来源落到输出根下同名文件。

## 2. 产物长这样（自带溯源与诚实提示）

```markdown
# <原文件名>
> 来源: `RKDocs:<主题>/<文件>.pdf`
> 转换: pdf2md / pymupdf4llm · 2026-11-13 17:05
> 指纹: sha256:b292b2dc0ab81871 · 页: 全部
> 说明: 本文由 PDF 自动转换，版式、表格与图片可能失真；关键参数、引脚与寄存器值以原 PDF 为准。

<!-- page: 1 -->
...
```

`<!-- page: N -->` 是页码锚点：引用参数时带上「原 PDF 第 N 页」，方便回查。

## 3. 去重与重转

- 指纹清单 `debugdoc/docs/rkdocs-md/.pdf2md-index.tsv` 按 **sha256** 记录，同一 PDF 改名也不会重复转换 → 输出 `SKIP`。
- 已有同名 md 但没有指纹记录时也 `SKIP`（可能是人工整理过的，不要盲覆盖）。
- 确实需要重转：`--force`（会覆盖产物，不删原 PDF）。
- 引擎升级或 `--pages` 换段后想重来，同样要 `--force`。

## 4. 转完必须重建索引

```bash
bash features/.harness/bin/kb-index
```

新 md 会按 `manuals` 类别进 `debugdoc/index/debugdoc-manuals.md`（原理图类走 `schematics`）。
之后检索按知识库 R0–R7：先读 L0，再选 1–2 个类别索引，最后定向读 md 的相关章节。

```bash
rg -n 'partition|分区表' debugdoc/docs/rkdocs-md/common/NVM/
```

## 5. 引擎选择与已知失真

| 引擎 | 强项 | 已知问题 |
|---|---|---|
| `pymupdf4llm` | 标题层级、列表、大部分表格；速度快 | 跨页表格可能断裂；图片仅占位 |
| `marker_single` | 版式还原最好，公式与复杂表格 | 慢、依赖重，适合少量关键文档 |
| `pdftotext` | 零依赖、稳定 | 丢结构；中文排版可能顺序错乱 |
| `ocr`（pdftoppm+tesseract） | 图片型/扫描件唯一可行 | 慢；表格与引脚网标识别率低；需 `chi_sim` 语言包 |

**如实说明的三条**：

1. **图片不会自动进 md**（默认不导出图片）。需要看图就回原 PDF 对应页。
2. **原理图要单独走 `--schematic`**：它解析矢量线段、结点标记与文字坐标，做连通分量重建，
   输出「图形统计 + 候选网络表 + 文字清单」。它回答的是"哪些线在几何上连在一起"，
   **不等于设计者意图**，已知失真见第 6 节。位图/扫描件会被判为「无矢量线段」并拒绝产出空壳 md（exit 1）。
3. **寄存器默认值、时序参数、引脚复用表这类精确数据**：md 只作定位，最终以原 PDF 为准，并在结论里标注页码。

## 6. 原理图重建的核验清单（必做）

`--schematic` 的候选网表**不能直接用于改板、算电流、查短路**。出结论前按这张表核对：

| 风险 | 现象 | 核验动作 |
|---|---|---|
| 元件符号轮廓被当成导线 | 不同网络被并成一个 | 抽 2–3 个网络回原图，看是否跨过了器件符号 |
| 跨页连接器断开 | 同一网络被拆成多个分量 | 查页边 `PORT` / 连接器文字，人工补齐 |
| 电源符号不画线 | VCC / GND 变成"未命名网络" | 按符号旁文字判断，不要依赖自动命名 |
| 不同地图上同一符号 | AGND / PGND 被并成一个 | 逐段核对地符号标注 |
| 总线（粗线 / 四边形） | 只算近似连接 | 总线一律按原图人工梳理 |
| 网络名贴在符号内部 | 标签挂错分量 | 用产物第 3 节「文字清单」按 y 坐标对照 |

**有源文件时不要走这条路**：`.SchDoc`（Altium）/ `.dsn`（OrCAD）/ `.kicad_sch`（KiCad）
能直接导出权威网表，精度远高于任何几何重建。几何重建的定位是：**没有源文件时，
把"图上有哪些网络名、大概连到哪些脚"变成可检索文本**，缩小回查范围，而不是替代读图。

## 7. 失败处理（不要假装成功）

| 现象 | 处理 |
|---|---|
| `RESULT INCOMPLETE` / `FAIL ...（产出为空）` | 该 PDF 未入库。文本型→查引擎；图片型→`--ocr`；加密→先解密 |
| 转换成功但字符数极少 | 脚本已自动回退 OCR；若仍少，多半是纯图片页，按上一条人工确认 |
| 中文乱码 | 换 `pymupdf4llm`；`pdftotext` 老版本对 CJK 支持差 |
| 表格错行 | 关键表格改用 `marker` 单篇重转，或直接引用 PDF 页码 |
| `exit 3` | 无引擎，按第 0 节装依赖；**不得跳过转换直接整本读 PDF** |
| `--schematic` 报「无矢量线段」 | 位图/扫描件，无法重建拓扑：改 `--ocr` 取文字，或要原理图源文件 |

## 8. 边界

- 只处理**已在本树内的资料**；不要把客户资料、外部付费文档整本转存进仓库。
- 转换产物属于知识库内容，随 `debugdoc` 独立仓库版本管理；不要复制回源码树其它目录。
- `pdf2md` 属于框架命令（`features/.harness/bin/`），不在 `debugdoc` 仓库内；仓库只存内容与规则。
