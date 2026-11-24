#!/usr/bin/env bash
# cg-server-rebuild.sh —— 服务器本地盘续建 RK3562Android 的 36 个 codegraph 叶子库
#
# 背景（2026-11-17）：
#   跨 SMB 全量建库时 4 个库被 codegraph liveness watchdog 误杀
#   （日志："Main thread unresponsive for ~60s — killing the wedged process (#850)"），
#   残留空壳 db（172KB / 222MB 未完成）。本脚本先把残留 db 备份到 .state，
#   再在服务器本地盘以 NO_WATCHDOG=1 续建，并自动跑 cg-bench 验收。
#
# 用法（在源码树根执行；脚本按自身位置推导树根，无需 cd）：
#   bash features/.harness/bin/cg-server-rebuild.sh --dry-run       # 只看计划，不写盘
#   bash features/.harness/bin/cg-server-rebuild.sh --failed-only   # 只重建 4 个失败库（最快）
#   bash features/.harness/bin/cg-server-rebuild.sh                 # 全量续建（已建库走 sync）
#   bash features/.harness/bin/cg-server-rebuild.sh --no-clean      # 跳过残留清理（已手动处理过时用）
#
# 其余参数原样透传给 cg-build-server，例如：
#   bash features/.harness/bin/cg-server-rebuild.sh --only kernel-5.10/drivers/net
#   bash features/.harness/bin/cg-server-rebuild.sh --check
#
# 退出码：沿用 cg-build-server（0 全部达标 / 1 有失败 / 2 配置错 / 3 环境不可用）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TREE="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
STATE="$TREE/features/.harness/.state"
BUILD="$SCRIPT_DIR/cg-build-server"
BENCH="$SCRIPT_DIR/cg-bench"

# 本次跨 SMB 建库被 watchdog 误杀、需要重新 init 的库
FAILED_ROOTS=(
  "frameworks/base/packages"
  "packages/apps/Settings"
  "packages/apps/Dialer"
  "hardware/rockchip"
)

# ---- 参数解析（本脚本消费的开关；其余透传）----
dry=0; clean=1; failed_only=0
passthru=()
while (($# > 0)); do
  case "$1" in
    --no-clean)    clean=0; shift ;;
    --failed-only) failed_only=1; shift ;;
    --dry-run)     dry=1; passthru+=("--dry-run"); shift ;;
    *)             passthru+=("$1"); shift ;;
  esac
done
if (( failed_only )); then
  for r in "${FAILED_ROOTS[@]}"; do passthru+=("--only" "$r"); done
fi

# ---- 前置检查 ----
echo "============================================================"
echo " cg-server-rebuild"
echo " 树根      : $TREE"
echo " 主机      : $(uname -s 2>/dev/null || echo unknown)"
echo " 模式      : $([[ $dry == 1 ]] && echo dry-run || echo apply)"
echo "============================================================"
[[ -f "$BUILD" ]] || { echo "error: 缺 cg-build-server：$BUILD" >&2; exit 2; }
[[ -f "$TREE/features/harness.conf" ]] || { echo "error: 缺 features/harness.conf" >&2; exit 2; }
command -v codegraph >/dev/null 2>&1 || {
  echo "error: 服务器未安装 codegraph CLI（需 Node >= 18 + codegraph 1.6.2）" >&2
  echo "       npm i -g @colbymchenry/codegraph" >&2
  exit 3
}
echo "codegraph : $(codegraph --version 2>&1 | tr -d 'v\r\n')"

mkdir -p "$STATE"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$STATE/cg-server-rebuild-$TS.log"
exec > >(tee -a "$LOG") 2>&1
echo "本脚本日志: ${LOG#"$TREE"/}"

# ---- 清理 watchdog 误杀残留（mv 备份，绝不直接 rm）----
if (( clean == 1 && dry == 0 )); then
  BK="$STATE/failed-db-backup-$TS"
  echo
  echo "---- 备份失败库残留 .codegraph（保留证据，可事后删除）----"
  for r in "${FAILED_ROOTS[@]}"; do
    cgdir="$TREE/$r/.codegraph"
    if [[ -d "$cgdir" ]]; then
      mkdir -p "$BK/$(dirname "$r")"
      mv "$cgdir" "$BK/$r.codegraph"
      echo "  BACKUP $r/.codegraph -> ${BK#"$TREE"/}/$r.codegraph"
    else
      echo "  SKIP   $r（无残留）"
    fi
  done
  echo "  备份目录: ${BK#"$TREE"/}"
elif (( clean == 1 )); then
  echo
  echo "---- [dry-run] 将备份以下残留（未执行）----"
  for r in "${FAILED_ROOTS[@]}"; do
    [[ -d "$TREE/$r/.codegraph" ]] && echo "  PLAN $r/.codegraph"
  done
fi

# ---- 服务器本地盘调优（均为 codegraph 官方支持的环境变量）----
# watchdog 是本次 4 库失败的直接原因：本地盘仍可能因大库 scan 触发 60s liveness 误杀。
export CODEGRAPH_NO_WATCHDOG="${CODEGRAPH_NO_WATCHDOG:-1}"
export CODEGRAPH_QUERY_POOL_SIZE="${CODEGRAPH_QUERY_POOL_SIZE:-4}"
export CODEGRAPH_NO_DAEMON="${CODEGRAPH_NO_DAEMON:-1}"
export CODEGRAPH_WAL_VALVE_MB="${CODEGRAPH_WAL_VALVE_MB:-1024}"
export CODEGRAPH_WAL_HEAL_MB="${CODEGRAPH_WAL_HEAL_MB:-64}"
echo
echo "调优      : NO_WATCHDOG=$CODEGRAPH_NO_WATCHDOG QUERY_POOL_SIZE=$CODEGRAPH_QUERY_POOL_SIZE NO_DAEMON=$CODEGRAPH_NO_DAEMON"
echo "            WAL_VALVE_MB=$CODEGRAPH_WAL_VALVE_MB WAL_HEAL_MB=$CODEGRAPH_WAL_HEAL_MB"
if (( ${#passthru[@]} )); then
  echo "透传参数  : ${passthru[*]}"
fi

# ---- 建库 + 内置 cg-bench 验收 ----
echo
echo "---- 调用 cg-build-server（幂等：已建库走 sync，未建/清理过的走 init）----"
bash "$BUILD" "${passthru[@]}"
rc=$?

if (( dry == 1 )); then
  echo
  echo "DRY-RUN 完成（未备份残留、未写库、未验收）。"
  exit "$rc"
fi

echo
if (( rc == 0 )); then
  echo "RESULT OK —— 所有库建库与验收通过；旧 7 个一级库可暂留作兜底，确认稳定后再 uninit。"
else
  echo "RESULT INCOMPLETE (rc=$rc) —— 详见上面 SUMMARY / FAIL 行；"
  echo "  单库日志在 ${STATE#"$TREE"/}/cg-build-server-*.log，本脚本日志 ${LOG#"$TREE"/}"
  echo "  修复后重跑：bash features/.harness/bin/cg-server-rebuild.sh --no-clean"
fi
exit "$rc"
