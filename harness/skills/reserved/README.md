# 预留：构建执行 skill（默认不实现）

本目录是**占位**，不含可执行流程。`sync-skills` 会跳过本目录。

## 为什么预留而不实现

1. 构建的**决策**不可自动化：`-A/-K/-U/-p/-o/-u/-d`、清不清 `out/`、`user` vs `userdebug`、出整包还是单镜像、烧写还是 `adb push`，取决于现场与人；
2. 构建的**环境**不可靠：容器 + 共享 `out/` + 90 分钟时长 + 超大日志，会话内跑构建边际价值低；
3. 真正吃时间的是**判定**与**归因**，不是敲命令 —— 这部分已由 `features/.harness/bin/verify-build` 覆盖（不执行构建，只判定）。

当前替代物是 feature 上下文里的**构建决策表**（见 `features/<feature>/AGENTS.md` 的"构建决策"段）。

## 若将来确需自动化

- 正确路径：让 harness **消费** `/opt/build-server`（`run-stack.sh --project`）的产物与日志，而不是在会话里跑长构建；
- 重启前必须补齐：唯一日志、子进程退出码、成功标记、产物 mtime、失败保留非零、共享 `out/` 串行锁；
- 落地前先读 `features/.harness/skills/deploy-and-accept/SKILL.md` 的事务契约，确认构建产物与部署入口对应。
