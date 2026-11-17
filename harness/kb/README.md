# harness/kb —— 调试知识库骨架模板

本目录随框架分发，提供**规则架构**，不含任何项目内部资料（客户评估、原理图、
补丁、测量数据一律不进仓库）。安装 harness 后位于 `<树>/features/.harness/kb/`。

## 文件

| 模板 | 部署后 | 作用 |
|---|---|---|
| `KB.md.template` | `debugdoc/KB.md` | L0 常驻入口：布局、类别路由表、R0–R7 摘要 |
| `KB_PLAN.md.template` | `debugdoc/KB_PLAN.md` | 规则正文：四层披露、索引、命名、引用、边界 |
| `CATEGORY.md.template` | `debugdoc/docs/<类>/README.md` | 每类内容仓的放入/不放规范 |

## 占位符

`kb-init` 部署时替换：

- `__PROJECT__` —— 项目代号（默认取树根目录名，可用 `--project` 指定）
- `__CATEGORY__` —— 类别名
- `__PURPOSE__` —— 该类别的用途说明（在 `kb-init` 中定义）

## 部署

```bash
bash features/.harness/bin/kb-init --dry-run                 # 只看计划
bash features/.harness/bin/kb-init --project "<项目代号>"     # 建骨架
bash features/.harness/bin/kb-index                         # 结构变化后重建 L1 索引
```

**幂等、不覆盖已有文件**（`--force` 才覆盖）。`debugdoc/` 是树的权威位置，
是否纳入版本控制由项目自己决定；框架不自动改 `.gitignore`。

## 边界

- 骨架只写规则与空目录；内容由使用团队按 `KB_PLAN.md` 自行沉淀。
- 知识库承载**过程证据**，harness 承载**验收纪律**，见 `docs/KNOWLEDGE-BASE.md`。
- 官方 PDF 库、`features/`、源码树一律不动，只通过索引与引用协议接入。
