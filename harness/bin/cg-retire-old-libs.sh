#!/usr/bin/env bash
# cg-retire-old-libs.sh —— 分层迁移验收通过后，清除旧一级大库的 codegraph 数据
#
# 背景：Y 树已从 7 个一级大库拆为 36 个 L2/L3 叶子库。旧一级库中：
#   kernel-5.10(4.6GB) / frameworks(3.2GB) / packages(2.9GB) / hardware(0.8GB)
#   已无路由价值，可清除，回收约 11.5GB；
#   而 system / vendor / device/rockchip 这 3 个一级库被新方案直接复用为叶子库，
#   其一级根的 .codegraph 就是新库本身 —— 脚本永不列入删除清单。
#
# 安全设计：
#   1. 默认 dry-run，只列计划，不写盘、不删数据。
#   2. --apply 默认把旧库 move 到树根 .retired-codegraph-<ts>/（同盘瞬时、可回滚），不直接删。
#   3. --purge 才真正删除（释放磁盘，不可逆）。
#   4. 执行前校验 36 个新库是否齐全；缺库默认拒绝（--force 可越过，危险）。
#   5. 删除清单与 ROOTS 求差集：若某个"旧库"现在也是新库，自动剔除并告警（防配置漂移误删）。
#   6. 只按精确路径处理一级根的 .codegraph 与 codegraph.json，绝不递归子目录的新库。
#
# 用法（服务器本地路径或 Y: 均可，树根按脚本自身位置推导）：
#   bash features/.harness/bin/cg-retire-old-libs.sh                  # 默认 dry-run，看计划
#   bash features/.harness/bin/cg-retire-old-libs.sh --apply          # move 到备份目录（可回滚）
#   bash features/.harness/bin/cg-retire-old-libs.sh --apply --purge  # 直接删除（释放磁盘，不可逆）
#   bash features/.harness/bin/cg-retire-old-libs.sh --force --apply  # 新库没建全也强删（危险）
#
# 回滚（move 模式）：把 .retired-codegraph-<ts>/<root>.codegraph 移回 <tree>/<root>/.codegraph；
#                    codegraph.json 同样移回 <tree>/<root>/codegraph.json。
# 退出码：0 完成 / 1 前置校验失败或执行出错 / 2 参数错
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TREE="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
CONF="$TREE/features/harness.conf"
STATE="$TREE/features/.harness/.state"

# 仅这 4 个旧一级库可清除；system/vendor/device/rockchip 是新库本身，永不列入
RETIRE=( kernel-5.10 frameworks packages hardware )

apply=0; purge=0; force=0; tree_override=""
while (($# > 0)); do
  case "$1" in
    --apply)   apply=1; shift ;;
    --purge)   purge=1; shift ;;
    --force)   force=1; shift ;;
    --tree)    tree_override="${2:-}"; shift 2 ;;
    --dry-run) apply=0; shift ;;
    -h|--help) sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: 未知参数 $1" >&2; exit 2 ;;
  esac
done
[[ -n "$tree_override" ]] && TREE="$tree_override"
(( purge == 1 )) && apply=1

echo "============================================================"
echo " cg-retire-old-libs"
echo " 树根      : $TREE"
echo " 主机      : $(uname -s 2>/dev/null || echo unknown)"
echo " 模式      : $([[ $apply == 0 ]] && echo 'dry-run（不写盘）' || ([[ $purge == 1 ]] && echo 'APPLY + PURGE（真删，不可逆）' || echo 'APPLY + MOVE（可回滚）'))"
echo "============================================================"

[[ -f "$CONF" ]] || { echo "error: 缺配置 $CONF" >&2; exit 1; }
mkdir -p "$STATE"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$STATE/cg-retire-old-libs-$TS.log"
exec > >(tee -a "$LOG") 2>&1
echo "日志: ${LOG#"$TREE"/}"

# shellcheck disable=SC1090
source "$CONF"
roots=("${ROOTS[@]:-}")
(( ${#roots[@]} )) || { echo "error: ROOTS 为空" >&2; exit 1; }

# ---- 校验 1：删除清单与 ROOTS 求差集，防止配置漂移后误删新库 ----
echo
echo "---- 校验 1：删除清单安全性（与 36 个新库求差集）----"
safe=()
for r in "${RETIRE[@]}"; do
  hit=0
  for nr in "${roots[@]}"; do [[ "$nr" == "$r" ]] && hit=1; done
  if (( hit == 1 )); then
    echo "  剔除  $r —— 该库现在是新 ROOTS 成员，拒绝删除"
  else
    echo "  可删  $r —— 不是新 ROOTS 成员"
    safe+=("$r")
  fi
done
(( ${#safe[@]} )) || { echo "error: 无安全的删除目标" >&2; exit 1; }

# ---- 校验 2：新库是否齐全（缺库则默认拒绝，避免删旧库后无回退）----
echo
echo "---- 校验 2：36 个新库完整性 ----"
ok_n=0; miss=0
for r in "${roots[@]}"; do
  db="$TREE/$r/.codegraph/codegraph.db"
  if [[ -f "$db" ]]; then
    sz=$(stat -c %s "$db" 2>/dev/null || echo 0)
    if (( sz > 1048576 )); then ok_n=$((ok_n+1)); else echo "  偏小  $r ($((sz/1048576))MB)"; miss=$((miss+1)); fi
  else
    echo "  缺失  $r"; miss=$((miss+1))
  fi
done
echo "  已建=$ok_n 异常=$miss 总数=${#roots[@]}"
if (( miss > 0 && force == 0 )); then
  echo "  拒绝执行：新库未建全。请先完成建库 + cg-bench 验收；确需强删加 --force。" >&2
  exit 1
elif (( miss > 0 )); then
  echo "  ⚠ --force 已生效：新库不齐全仍继续，删旧库后无法回退，风险自负。"
fi

# ---- 校验 3：目标旧库存在且有数据 ----
echo
echo "---- 校验 3：待清除旧库体量 ----"
total_mb=0
for r in "${safe[@]}"; do
  cg="$TREE/$r/.codegraph"
  db="$cg/codegraph.db"
  if [[ ! -d "$cg" || ! -f "$db" ]]; then
    echo "  跳过  $r（无旧库目录或 db，可能已清除）"
    continue
  fi
  mb=$(du -sm "$cg" 2>/dev/null | cut -f1)
  total_mb=$((total_mb + mb))
  echo "  待清  $r/.codegraph  ${mb}MB"
done
echo "  合计约 ${total_mb}MB"
if (( total_mb == 0 )); then echo "  无数据可清除，退出。"; exit 0; fi

# ---- 干跑：只打印计划 ----
if (( apply == 0 )); then
  echo
  echo "---- [dry-run] 计划（未执行）----"
  for r in "${safe[@]}"; do
    [[ -d "$TREE/$r/.codegraph" ]] || continue
    if (( purge == 1 )); then
      echo "  PLAN PURGE  $TREE/$r/.codegraph"
    else
      echo "  PLAN MOVE   $TREE/$r/.codegraph -> $TREE/.retired-codegraph-$TS/$r.codegraph"
    fi
    [[ -f "$TREE/$r/codegraph.json" ]] && echo "  PLAN        $TREE/$r/codegraph.json（旧排除配置，一并处理）"
  done
  echo
  echo "这是 dry-run。实际执行加 --apply（默认 move 可回滚）或 --apply --purge（真删）。"
  exit 0
fi

# ---- 执行 ----
echo
echo "---- 执行清除 ----"
if (( purge == 0 )); then
  BK="$TREE/.retired-codegraph-$TS"
  mkdir -p "$BK" || { echo "error: 无法创建备份目录 $BK" >&2; exit 1; }
  echo "备份目录: ${BK#"$TREE"/}"
fi

freed=0
for r in "${safe[@]}"; do
  cg="$TREE/$r/.codegraph"
  conf="$TREE/$r/codegraph.json"
  [[ -d "$cg" ]] || continue
  mb=$(du -sm "$cg" 2>/dev/null | cut -f1)
  if (( purge == 1 )); then
    # 精确路径删除，绝不递归到子目录的新库
    rm -rf -- "$cg" && echo "  清除  $r/.codegraph (${mb}MB)" || { echo "  FAIL  $r/.codegraph" >&2; continue; }
    [[ -f "$conf" ]] && rm -f -- "$conf" && echo "  清除  $r/codegraph.json（旧配置）"
  else
    mv -- "$cg" "$BK/$r.codegraph" && echo "  移出  $r/.codegraph (${mb}MB) -> .retired-codegraph-$TS/$r.codegraph" || { echo "  FAIL  $r/.codegraph" >&2; continue; }
    [[ -f "$conf" ]] && mv -- "$conf" "$BK/$r.codegraph.json" && echo "  移出  $r/codegraph.json（旧配置）"
  fi
  freed=$((freed + mb))
done

# move 模式把退役目录排除在 git 状态之外（幂等）
if (( purge == 0 )); then
  gi="$TREE/.gitignore"
  if [[ -f "$gi" ]] && ! grep -q '^\.retired-codegraph-\*/$' "$gi"; then
    printf '\n# 退役的旧 codegraph 数据（可回滚备份，确认后手动删除）\n.retired-codegraph-*/\n' >> "$gi"
    echo "  已在 .gitignore 追加 .retired-codegraph-*/"
  fi
fi

echo
echo "RESULT DONE  freed≈${freed}MB"
if (( purge == 0 )); then
  echo "回滚示例：mv \"$TREE/.retired-codegraph-$TS/kernel-5.10.codegraph\" \"$TREE/kernel-5.10/.codegraph\""
  echo "确认无问题后，可手动删除 $BK 释放磁盘。"
else
  echo "已真删，不可回滚。建议跑一次 cg-bench 确认 36 个新库仍正常。"
fi
exit 0
