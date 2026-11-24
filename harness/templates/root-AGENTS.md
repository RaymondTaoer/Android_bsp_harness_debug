<!--
  features/.harness/templates/root-AGENTS.md
  树根 AGENTS.md 的精简骨架。由 agents-slim 填充 {{PLATFORM}} / {{PRODUCT}} / {{DTS}}。

  设计原则（见 docs/TOKEN-EFFICIENCY.md 2.5）：
    - 根规则每轮都进上下文，只放「写错就出事」的纪律 + 「去哪查」的指针；
    - 项目事实放 features/harness.conf（唯一人工配置），不在这里重复；
    - 库清单放 cg-route --list（生成物），写进根文件必然过期；
    - 命令细节放 docs/USAGE.md 与 skills（按需加载）。
  官方建议 CLAUDE.md <200 行；中文密度高，本框架目标 ≤60 行。
-->
# AGENTS.md — {{PLATFORM}} BSP 源码树

> 常驻规则只放纪律。项目事实查 `features/harness.conf`，库清单查 `cg-route --list`，
> 命令查 `docs/USAGE.md` 与 skills，调试资料查 `debugdoc/KB.md`。

| 项 | 值（详见 `features/harness.conf`） |
|---|---|
| 产品 / lunch | {{PRODUCT}} |
| 板级 dts | {{DTS}} |

## 1. 事实源：不要凭记忆

| 要什么 | 去哪 |
|---|---|
| 产品、dts、规模、构建环境、冷区 | `features/harness.conf` + `cg-exclude` 生成的 `codegraph.json` |
| 库清单 / 某个文件归哪个库 | `bash features/.harness/bin/cg-route --list` / `cg-route <路径>` |
| 库是否新鲜/损坏 | `cg-assert env --probe`（真打一次查询，别只看 mtime） |
| 命令用法 / 退出码 | `docs/USAGE.md`；建库、设备、知识库细节在 `.claude/skills/` |
| 评估、方案、调试记录、官方手册 | `debugdoc/KB.md`（L0）→ R0–R7 |
| 上一轮做到哪、接着做什么 | `handoff show <feature>` |

**禁止凭记忆列举库清单，禁止把一级目录当 `projectPath`**：命中库根是
`cg-route` 的**最长前缀**；传一级目录时 codegraph 会静默返回提示而不报错，
看起来就是"查不到"。

## 2. 四条红线

1. `projectPath` = `cg-route` 命中的最长前缀；跨库链路逐段切换，说明"只到本库边界"。
2. `INCOMPLETE` / `SKIP` / `TIMEOUT` / 「busy, retry」都**不是 PASS**，也不是"符号不存在"；
   判环境未就绪。库状态 `STALE/MISSING/UNKNOWN/CORRUPT` 不得当成代码事实。
3. 非索引文件（`.dts` `.dtsi` `.dtbo` `.bp` `.mk` `.xml` `.rc` `.cfg` `.aidl` `.hidl`
   `.sh` `.json`）与被排除的冷区 → **ripgrep**；codegraph 无结果不得断言"不存在"。
   语言以 `cg-assert langs <root>` 实测为准，不用扩展名白名单。
4. 不改 `out/` `build/` `prebuilts/` 生成物与别名目录；设备操作显式 `ANDROID_SERIAL`，
   重启类动作需显式授权。禁止 `taskkill /IM node.exe` 清理残留进程。

## 3. 四段证据

`STATIC → BUILD → DEVICE → FEATURE`，缺一段即 `INCOMPLETE`。
阈值必须**由人**写进 `features/<feature>/assertions.tsv`；
改源码前 `check-drift` + `cg-assert impact`，交付前 `verify-<feature>.sh`。
退出码：`0` PASS / `1` 断言失败 / `2` 参数或配置错 / `3` 数据不可用（记 SKIP）。

## 4. 会话接力与预算

- 新会话第一件事：`bash features/.harness/bin/handoff show <feature>`；
  收尾 `handoff new --note … --blocker … --next …` + `handoff check`。
  **handoff 不是验收报告**，结论只认 verify 的 `RESULT` 行。
- `bash features/.harness/bin/context-budget` 检查常驻体积与反模式。
- 新增内容前先问：它是"每轮都需要的纪律"，还是"查一次就够的细节"？
  后者一律进 skills / `docs/USAGE.md`，不要往本文件里加。
