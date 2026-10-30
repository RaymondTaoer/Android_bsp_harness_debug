#!/usr/bin/env bash
# bootstrap.sh —— 四步到位：确认 MCP → 生成路由表 → 生成排除配置 → 建库。
#
# 用法：
#   bash features/.harness/bootstrap.sh                 # 全流程
#   bash features/.harness/bootstrap.sh --check         # 只检查，不装不建
#   bash features/.harness/bootstrap.sh --dry-run       # 打印计划，不落盘
#   bash features/.harness/bootstrap.sh --skip-build    # 只做 1-3 步
#   bash features/.harness/bootstrap.sh --only kernel-5.10
#   bash features/.harness/bootstrap.sh --tree /y/RK3562Android
#
# 各步对应：
#   1. cg-ensure   检查 codegraph CLI / MCP 注册 / 已有库可查询性，缺则安装
#   2. cg-roots    由 features/harness.conf 生成路由表 codegraph-roots.tsv
#   3. cg-exclude  按各根**实际内容**生成 codegraph.json 排除配置
#   4. cg-build    批量 index / sync
#
# 退出码：0 全部成功；1 有步骤失败；2 用法/配置错误；3 codegraph 不可用
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
check=0; dry=0; skip_build=0; only=""; tree=""
while (($# > 0)); do
  case "$1" in
    --check) check=1; shift ;;
    --dry-run) dry=1; shift ;;
    --skip-build) skip_build=1; shift ;;
    --only) only="${2:-}"; shift 2 ;;
    --tree) tree="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "error: 未知参数 $1" >&2; exit 2 ;;
  esac
done

# 解析 harness 根（= 源码树根）：优先 --tree，其次由本脚本位置推导
if [[ -n "$tree" ]]; then
  HARNESS_ROOT="$(cd "$tree" && pwd -P)"
  export HARNESS_ROOT
else
  HARNESS_ROOT="$(cd "$SELF_DIR/../.." && pwd -P)"
  export HARNESS_ROOT
fi
BIN="$HARNESS_ROOT/features/.harness/bin"
CONF="$HARNESS_ROOT/features/harness.conf"

echo "============================================================"
echo " android-bsp-harness bootstrap"
echo " 树根：$HARNESS_ROOT"
echo " 模式：$([[ $check -eq 1 ]] && echo check-only || echo apply)$([[ $dry -eq 1 ]] && echo " + dry-run")"
echo "============================================================"

[[ -d "$BIN" ]] || { echo "error: 未安装 harness（缺 $BIN）；先跑 bash install.sh --tree $HARNESS_ROOT" >&2; exit 2; }
if [[ ! -f "$CONF" ]]; then
  echo "error: 缺配置 $CONF；先 cp harness.conf.example features/harness.conf" >&2
  exit 2
fi

step_fail=0
run_step() {
  local name="$1"; shift
  echo
  echo "---- $name ----"
  if "$@"; then
    return 0
  else
    local rc=$?
    echo "[bootstrap] $name 失败（rc=$rc）"
    step_fail=$((step_fail + 1))
    return "$rc"
  fi
}

# ---- 1. codegraph / MCP ----
if (( check == 1 )); then
  run_step "1/4 检查 codegraph 与 MCP" bash "$BIN/cg-ensure" --check
else
  run_step "1/4 检查并补齐 codegraph 与 MCP" bash "$BIN/cg-ensure"
fi
ensure_rc=$?

if (( ensure_rc == 3 )); then
  echo
  echo "[bootstrap] codegraph 不可用，后续建库步骤无法执行。"
  echo "            可手工安装后重跑：npm install -g @colbymchenry/codegraph"
  exit 3
fi

# ---- 2. 路由表 ----
if (( dry == 1 )); then
  echo
  echo "---- 2/4 生成路由表（dry-run）----"
  echo "PLAN  bash $BIN/cg-roots sync"
else
  run_step "2/4 生成路由表" bash "$BIN/cg-roots" sync
fi

# ---- 3. 排除配置 ----
args=()
(( dry == 1 )) && args+=(--dry-run)
if (( ${#args[@]} )); then
  echo
  echo "---- 3/4 生成排除配置（dry-run）----"
  bash "$BIN/cg-exclude" "${args[@]}"
else
  run_step "3/4 生成排除配置" bash "$BIN/cg-exclude"
fi

# ---- 4. 建库 ----
build_args=()
[[ -n "$only" ]] && build_args+=(--only "$only")
if (( skip_build == 1 )); then
  echo
  echo "---- 4/4 建库（已跳过 --skip-build）----"
elif (( check == 1 )); then
  echo
  echo "---- 4/4 建库（check-only 不执行）----"
  bash "$BIN/cg-build" --dry-run "${build_args[@]}"
elif (( dry == 1 )); then
  echo
  echo "---- 4/4 建库（dry-run）----"
  bash "$BIN/cg-build" --dry-run "${build_args[@]}"
else
  echo
  echo "注意：全量索引可能持续数小时（kernel 级目录尤其慢），建议在后台跑并保留日志。"
  run_step "4/4 建库" bash "$BIN/cg-build" "${build_args[@]}"
fi

echo
if (( step_fail > 0 )); then
  echo "BOOTSTRAP INCOMPLETE（$step_fail 个步骤失败）"
  exit 1
fi
echo "BOOTSTRAP OK"
echo "常用命令："
echo "  bash $BIN/cg-route <path>           # 这个文件该用哪个库"
echo "  bash $BIN/cg-assert env --probe     # 各库新鲜度 + 可查询性"
echo "  bash $BIN/cg-build                  # 增量同步所有库"
