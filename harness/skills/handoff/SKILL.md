---
name: handoff
description: 跨会话接力卡。用于新会话开始要接续上一次调查、长 bug hunt 收尾、上下文即将耗尽、给子代理写 brief，以及需要把「做了什么/怎么验证/改了哪些文件/当前阻塞/下一步」固定成可复核文件的场合。不适用于判定验收结果（那是 verify-<feature>.sh 的职责）。
---

# handoff：跨会话接力

## 何时用

- **新会话第一件事**：项目里有 `features/<feature>/` 上下文时，先 `handoff show <feature>`；
- 一轮调查结束、上下文快满、或要换模型/换人继续 → `handoff new`；
- 要给子代理派活 → 把 `handoff show` 的输出直接当 brief 的一部分；
- 需要回溯"当时为什么走了这条错路" → `handoff show <feature> --all` 看归档。

## 为什么必须有

AOSP 规模的长调查会积累失败假设、半读的文件、成堆调试日志，直到上下文被噪声淹没。
固定形状的接力卡只把**还成立的事实**带过去，新会话不用重新探索，
而且新会话对旧假设没有执念，往往正是它发现之前走错了方向。

**不要用 `/compact` 代替落文件**：compaction 要先读全量上下文才产出摘要，
且专丢失败假设与命令输出——恰恰是调试里最贵的部分。落文件是单向成本。

## 命令

```bash
# 新会话开始
bash features/.harness/bin/handoff show <feature>

# 一轮收尾（三段 HUMAN 必须显式给）
bash features/.harness/bin/handoff new <feature> \
  --note '定位到 4G_PWRON 与 4G_RST 被接插件符号误并，已改 cg-slice 锚点校验' \
  --blocker '无' \
  --next '跑 features/<feature>/verify-<feature>.sh 看 STATIC 段；若 SKIP 先 sync 库'

# 中途只刷新自动段（不动人工段）
bash features/.harness/bin/handoff capture <feature>

# 收尾自检
bash features/.harness/bin/handoff check <feature>
```

首次使用先 `handoff init <feature>`；`handoff list` 看哪些 feature 有接力卡。

## 五段形状

| 段 | 谁填 | 含义 |
|---|---|---|
| 1. 做了什么 | **HUMAN** | 一轮的目的与结果，一句话 |
| 2. 怎么验证的 | AUTO | 只列证据产物路径 + mtime + `RESULT` 行，**不重述结论** |
| 3. 改了哪些文件 | AUTO | 按 `repos.tsv` 的根分别列 git 状态 |
| 4. 当前阻塞 | **HUMAN** | 现象 + 复现命令 + 已排除的假设；没有就写「无」 |
| 5. 下一步 | **HUMAN** | 具体动作 + 文件路径 + 判定标准 |

`handoff capture` 只替换 AUTO 段，HUMAN 段逐字保留；`handoff new` 把上一份
归档成 `handoff-NNN.md` 再建新的，编号不复用。

## 纪律（必须遵守）

1. **HUMAN 三段必须显式给**。脚本不会替你写结论；留 `TODO` 时 `handoff check`
   返回 `RESULT INCOMPLETE`。写不出下一步就如实写「未定」，不要用「继续排查」这种空话。
2. **AUTO 段只是指针**：`clean` 只代表该根本次 `git status` 无输出，
   **不代表验证通过**；`采集超时`/`采集失败` 一律显示「状态未知」，不能当成干净。
   工具刻意不做全树扫描（Samba 上 `git status` 实测 >200s 会挂死）。
3. **handoff 不是验收报告**。结论以四段证据 STATIC→BUILD→DEVICE→FEATURE 和
   `verify-<feature>.sh` 的 `RESULT` 行为准；`--demo` 产物、未跑的脚本、
   只存在于对话里的输出都不算证据。
4. **收尾前跑 `check`**，`INCOMPLETE` 就补齐，别把空壳留给下一个会话。
5. **位置默认 `features/<feature>/handoff/`，常被 `.gitignore` 忽略**——`init` 会
   如实报告。需要跨人/跨机器接力时设 `HANDOFF_DIR` 指向一个**未被忽略**的
   独立仓内路径（例如 `debugdoc/handoff`）。别假装它会被版本控制带走。
6. 一份 handoff 只描述一轮；不要在同一份里追加流水账，用 `new` 开新的。

## 与四段证据的关系

| | handoff | verify-<feature>.sh |
|---|---|---|
| 回答 | "上次做到哪、接着做什么" | "这次改动能不能验收" |
| 结论 | 不下结论，只给指针 | `PASS` / `FAIL` / `INCOMPLETE` |
| 谁写阈值 | 不涉及 | **必须由人写** `assertions.tsv` |

两者不互相替代：handoff 里写「验证通过」是无效的，必须指向 verify 的输出。
