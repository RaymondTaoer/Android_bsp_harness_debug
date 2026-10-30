#!/usr/bin/env bash
# install.sh —— 把 harness 安装进一个 Android/BSP 源码树。
#
# 只做复制，不改你的源码：
#   <tree>/features/.harness/**      框架本体（bin / lib / skills / tests / templates）
#   <tree>/features/harness.conf     配置（已存在则不动）
#   <tree>/features/roots.list       根清单的可读副本（可选，见 README）
#
# 装完后跑：
#   bash <tree>/features/.harness/bin/cg-ensure      # 1. 确认 codegraph/MCP
#   bash <tree>/features/.harness/bin/cg-roots sync  # 2. 生成路由表
#   bash <tree>/features/.harness/bin/cg-exclude     # 3. 生成排除配置
#   bash <tree>/features/.harness/bin/cg-build       # 4. 建库
# 或者一步到位：bash <tree>/features/.harness/bootstrap.sh
#
# 用法：
#   bash install.sh --tree /path/to/android
#   bash install.sh --tree /path/to/android --force     # 覆盖已存在的 harness 文件
#   bash install.sh --tree /path/to/android --dry-run
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TREE=""; force=0; dry=0
while (($# > 0)); do
  case "$1" in
    --tree) TREE="${2:-}"; shift 2 ;;
    --force) force=1; shift ;;
    --dry-run) dry=1; shift ;;
    -h|--help)
      sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "error: 未知参数 $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TREE" ]]; then
  echo "error: 必须指定 --tree <源码树根>" >&2
  echo "       例：bash install.sh --tree /y/RK3562Android" >&2
  exit 2
fi
[[ -d "$TREE" ]] || { echo "error: 目录不存在：$TREE" >&2; exit 2; }
TREE="$(cd "$TREE" && pwd -P)"

SRC="$REPO_DIR/harness"
DST="$TREE/features/.harness"
[[ -d "$SRC" ]] || { echo "error: 仓库不完整（缺 $SRC）" >&2; exit 2; }

echo "[install] 源：$SRC"
echo "[install] 目标：$DST"

if (( dry == 1 )); then
  echo "[install][dry-run] 将复制："
  (cd "$SRC" && find . -type f | sed 's/^/  /')
  exit 0
fi

mkdir -p "$DST"
# -a 保留权限（可执行位）；--force 决定是否覆盖已存在文件
if (( force == 1 )); then
  cp -a "$SRC/." "$DST/"
else
  # 不覆盖已有文件：逐个判断，便于用户在树内做本地改动
  while IFS= read -r rel; do
    mkdir -p "$DST/$(dirname "$rel")"
    [[ -e "$DST/$rel" ]] && continue
    cp -a "$SRC/$rel" "$DST/$rel"
  done < <(cd "$SRC" && find . -type f -printf '%P\n')
fi

mkdir -p "$TREE/features"
if [[ ! -f "$TREE/features/harness.conf" ]]; then
  cp "$REPO_DIR/harness.conf.example" "$TREE/features/harness.conf"
  echo "[install] 已生成配置：features/harness.conf（请按实际目录修改 ROOTS）"
else
  echo "[install] 保留已有配置：features/harness.conf"
fi

chmod +x "$DST"/bin/* 2>/dev/null || true
printf '%s\n' "$(cd "$REPO_DIR" && git rev-parse --short HEAD 2>/dev/null || echo unknown)" > "$DST/.harness-version"

# 让生成物不污染 git status（幂等追加）
GI="$TREE/.gitignore"
if [[ -f "$GI" ]]; then
  for line in 'features/.harness/.state/' 'features/.harness/.harness-version'; do
    grep -qxF "$line" "$GI" 2>/dev/null || printf '%s\n' "$line" >> "$GI"
  done
fi

echo "[install] 完成（$(find "$DST" -type f | wc -l | tr -d ' ') 个文件）"
echo
echo "下一步："
echo "  1) 编辑 $TREE/features/harness.conf 的 ROOTS"
echo "  2) bash $DST/bootstrap.sh"
