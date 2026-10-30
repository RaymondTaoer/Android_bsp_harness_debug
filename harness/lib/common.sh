#!/usr/bin/env bash
# features/.harness/lib/common.sh
# 共用函数。纯 bash + git + coreutils：**不依赖 python3 / jq**，
# 以便在 Windows Git Bash 与 Linux 构建宿主上行为一致。
#
# 约定：
#   - HARNESS_ROOT 默认由本文件位置推导（features/.harness/lib -> 上三级）。
#   - 所有内部比较使用归一化路径（正斜杠、无尾斜杠）。
#   - 传给 codegraph 的路径必须经 to_native 转换（Windows 下 /y/x -> Y:/x）。
#
# 用法（在脚本中）：
#   source "$(dirname "$0")/../lib/common.sh"

set -u

HARNESS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"

norm_path() {
  local p="${1//\\//}"
  while [[ "$p" == */ && "$p" != "/" ]]; do p="${p%/}"; done
  printf '%s\n' "$p"
}

# Git Bash / Cygwin 下把 Windows 盘符路径 Y:/foo 转成 /y/foo。
# to_native 的逆运算：路由前缀匹配（route_for）用的是 HARNESS_ROOT（/y/... 形式），
# 若入参保持 Y:/... 形式则前缀永远对不上，绝对路径形式的调用会全部路由失败。
to_msys() {
  local p
  p="$(norm_path "$1")"
  case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*)
      if [[ "$p" =~ ^([A-Za-z]):/(.*)$ ]]; then
        printf '/%s/%s\n' "$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')" "${BASH_REMATCH[2]}"
      else
        printf '%s\n' "$p"
      fi
      ;;
    *)
      printf '%s\n' "$p"
      ;;
  esac
}

# 物理路径归一化（**两边都要过这一关**）。
#
# 【坑，实测踩过两次】Git Bash / MSYS 下同一目录有多种写法，且 `cd` 会"记住"你进门的写法：
#   /y/RK3562Android        ==  Y:/RK3562Android
#   /tmp/x                  ==  C:/Users/<u>/AppData/Local/Temp/x
# `cd C:\...\Temp/x && pwd -P`  ->  /tmp/x
# `cd /c/Users/.../Temp/x && pwd -P` -> /c/Users/.../Temp/x   （同一目录，两种输出）
# 只用 to_msys 或只用 cd+pwd -P 都会让「树根」和「入参」落到不同分支 → 前缀永不匹配 →
# 报「未登记的一级目录：<自己树里的路径>」。
#
# 解法：用 cygpath -w（POSIX→Windows）再 to_msys 回到 /c/... 形式，两个方向都收敛到同一写法。
# 没有 cygpath（Linux/macOS）时退化为 to_msys，行为不变。
canon_path() {
  local p w
  p="$(norm_path "$1")"
  case "$p" in
    /*|[A-Za-z]:/*) : ;;
    *) p="$(norm_path "$PWD")/$p" ;;
  esac
  p="$(norm_path "$p")"
  if command -v cygpath >/dev/null 2>&1; then
    w="$(cygpath -w "$p" 2>/dev/null || true)"
    [[ -n "$w" ]] && p="$(norm_path "$w")"
  fi
  to_msys "$p"
}

abs_path() {
  canon_path "$1"
}

# Git Bash / Cygwin 下把 /y/foo 转成 Y:/foo，供 Windows 原生程序（codegraph）使用。
to_native() {
  local p
  p="$(norm_path "$1")"
  case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*)
      if [[ "$p" =~ ^/([A-Za-z])/(.*)$ ]]; then
        printf '%s:/%s\n' "$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')" "${BASH_REMATCH[2]}"
      else
        printf '%s\n' "$p"
      fi
      ;;
    *)
      printf '%s\n' "$p"
      ;;
  esac
}

stat_mtime() {
  [[ -f "$1" ]] || return 1
  if stat -c %Y "$1" >/dev/null 2>&1; then stat -c %Y "$1"; else stat -f %m "$1"; fi
}

fmt_epoch() {
  local e="${1:-}"
  [[ "$e" =~ ^[0-9]+$ ]] || { printf -- '-\n'; return 0; }
  date -d "@$e" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$e" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '%s\n' "$e"
}

# git 包装：SMB 共享会触发 dubious ownership，这里统一放行（每次调用显式 -c）。
git_q() {
  git -c safe.directory='*' -c core.quotepath=false "$@" 2>/dev/null
}

git_head_commit() {
  git_q -C "$1" rev-parse --short=12 HEAD 2>/dev/null || true
}

git_head_epoch() {
  git_q -C "$1" log -1 --format=%ct 2>/dev/null || true
}

git_branch() {
  git_q -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || echo DETACHED
}

git_dirty() {
  local out
  out="$(git_q -C "$1" status --porcelain 2>/dev/null | head -n 1)"
  [[ -n "$out" ]] && echo 1 || echo 0
}

# 输出：dir<TAB>mcp<TAB>db_rel<TAB>langs<TAB>db_root
# 返回：0 命中；1 不属于任何已登记一级根；2 路由表缺失；3 目标是树根本身
route_for() {
  local target best="" best_len=-1
  local dir mcp db langs dbroot prefix len
  target="$(abs_path "$1")"
  [[ "$target" == "$HARNESS_ROOT" ]] && return 3
  [[ -f "$ROOTS_TSV" ]] || return 2
  while IFS=$'\t' read -r dir mcp db langs dbroot || [[ -n "${dir:-}" ]]; do
    [[ -z "${dir:-}" || "$dir" == \#* ]] && continue
    prefix="$(norm_path "$HARNESS_ROOT/$dir")"
    if [[ "$target" == "$prefix" || "$target" == "$prefix"/* ]]; then
      len=${#prefix}
      if (( len > best_len )); then
        best_len=$len
        best="$dir"$'\t'"$mcp"$'\t'"$db"$'\t'"$langs"$'\t'"$dbroot"
      fi
    fi
  done < "$ROOTS_TSV"
  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
}

# 库新鲜度：db mtime 与"该 db 根最近一次提交"比较。
# 输出：<state><TAB><detail>，state ∈ fresh|stale|missing|unknown
db_status() {
  local dbroot="$1" db mtime last detail
  db="$HARNESS_ROOT/$dbroot/.codegraph/codegraph.db"
  if [[ ! -f "$db" ]]; then
    printf 'missing\t%s\n' "$db"
    return 0
  fi
  mtime="$(stat_mtime "$db" || true)"
  last="$(git_head_epoch "$HARNESS_ROOT/$dbroot" || true)"
  if [[ -z "$mtime" || -z "$last" ]]; then
    printf 'unknown\tdb_mtime=%s last_commit=%s\n' "${mtime:--}" "${last:--}"
    return 0
  fi
  detail="db_mtime=$(fmt_epoch "$mtime") last_commit=$(fmt_epoch "$last")"
  if (( mtime >= last )); then
    printf 'fresh\t%s\n' "$detail"
  else
    printf 'stale\t%s\n' "$detail"
  fi
}

feature_from_env_or_file() {
  local f="${FEATURE_NAME:-}"
  if [[ -z "$f" && -f "$HARNESS_ROOT/features/CURRENT_FEATURE" ]]; then
    IFS= read -r f < "$HARNESS_ROOT/features/CURRENT_FEATURE" || true
  fi
  printf '%s\n' "${f//[[:space:]]/}"
}

valid_feature_name() {
  local LC_ALL=C
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

# ---- 变量初始化必须放在函数定义之后 ----
# 【坑】HARNESS_ROOT 必须与 abs_path() 的输出形态一致（Git Bash 下统一成 /y/...），
# 否则 `--tree Y:\RK3562Android`、`mktemp -d` 返回的 `C:\Users\...\Temp/x` 这类入参
# 会被 to_msys 变成 /y/...、/c/...，而 HARNESS_ROOT 仍是盘符形式 → 前缀永不匹配，
# 表现为「未登记的一级目录：<自己树里的路径>」。这一步不能省。
HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$HARNESS_LIB_DIR/../../.." >/dev/null 2>&1 && pwd -P)}"
HARNESS_ROOT="$(canon_path "$HARNESS_ROOT")"
ROOTS_TSV="${ROOTS_TSV:-$HARNESS_ROOT/features/.harness/codegraph-roots.tsv}"
