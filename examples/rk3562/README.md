# 实例：RK3562 / Android 13 BSP

这是一个真实跑通过的部署，用来演示"框架怎么落到一棵真树上"，**不是默认配置**。

## 树形

```
<tree>/                          ← 根仓（dis121c），features/ 与 .claude/ 被 .gitignore 排除
├── kernel-5.10/                 ← 独立库（49916 文件：c 49217 / cpp 666 / objc 21 / yaml 6 / python 5 / xml 1）
├── frameworks/                  ← 独立库
├── system/                      ← 独立库
├── hardware/                    ← 独立库
├── vendor/                      ← 独立库
├── device/rockchip/             ← 独立库
├── packages/                    ← 独立库（20638 java / 4777 cpp / 919 python / 679 kotlin / 231 rust）
└── features/
    ├── harness.conf             ← 见同目录 harness.conf
    ├── CURRENT_FEATURE          ← 内容 boot-opt
    ├── .harness/                ← install.sh 装进来的框架
    └── boot-opt/                ← feature 上下文
        ├── AGENTS.md
        ├── repos.tsv
        ├── assertions.tsv       ← 只有注释 → 生效行 0 → 结果必为 RESULT INCOMPLETE
        ├── baseline.tsv         ← feature-state capture 生成
        └── verify-boot-opt.sh
```

## 落地过程中踩到并固化的点

| 现象 | 结论 | 固化位置 |
|---|---|---|
| 子树里 524 个 `.git` 只有 `HEAD`+`index`，没有 `config`/`refs`/`objects` | git 不认它们是仓根，`rev-parse --show-toplevel` 返回树根 → 判"真仓"必须看 `.git/config` 是否存在 | `feature-state` / `check-drift` |
| Samba 共享对 `info` / `config` 这两个名字做大小写不敏感 veto，客户端建不出 `.git/info`、`.git/config` | 与 harness 无关，不要在脚本里依赖 `.git/info/exclude` | 文档 |
| `codegraph status` 在 3.2GB 库上 >120s | 禁止进 hook；新鲜度只看 db mtime 与 `git log -1 --format=%ct` | `common.sh:db_status` |
| 库 mtime 很新但查询报 `database disk image is malformed` | 只判 mtime 会假绿；必须真打一次查询 | `cg-assert env --probe` |
| 同一分支（dis121c）覆盖全树，per-feature 分支不存在 | 用"最后触及提交 + 脏集"做漂移守卫，不判分支名 | `check-drift` |
| 目录名相同但归属不同（顶层 `packages/` vs `frameworks/base/packages/`） | 按最长前缀路由，不按目录名字面猜 | `cg-route` |
| 语言不能靠扩展名白名单 | 以 `cg-assert langs <root>` 实测为准 | skill `codegraph-nav` |

## 复现步骤

```bash
bash install.sh --tree /y/RK3562Android
cp examples/rk3562/harness.conf /y/RK3562Android/features/harness.conf
bash /y/RK3562Android/features/.harness/bin/cg-ensure        # 1
bash /y/RK3562Android/features/.harness/bin/cg-roots sync --langs   # 2
bash /y/RK3562Android/features/.harness/bin/cg-exclude       # 3
bash /y/RK3562Android/features/.harness/bin/cg-build         # 4（数小时，放后台）
```

然后按 `harness/templates/` 建 feature 目录，`feature-state capture` 取基线。
