#!/usr/bin/env bash
# uninstall.sh —— 从源码树移除 harness 框架文件。
#
# 明确**不删**：
#   - 各根的 codegraph.json（那是你确认过的排除策略）
#   - 各根的 .codegraph/（重建一次要几小时）
#   - features/harness.conf（你的配置）
#   - features/<feature>/（你的 feature 上下文与基线）
#
# 用法：
#   bash uninstall.sh --tree /y/RK3562Android --yes
set -uo pipefail

TREE=""; yes=0
while (($# > 0)); do
  case "$1" in
    --tree) TREE="${2:-}"; shift 2 ;;
    --yes) yes=1; shift ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: 未知参数 $1" >&2; exit 2 ;;
  esac
done
[[ -n "$TREE" && -d "$TREE" ]] || { echo "error: 需要 --tree <已安装的源码树根>" >&2; exit 2; }
TREE="$(cd "$TREE" && pwd -P)"
DST="$TREE/features/.harness"
[[ -d "$DST" ]] || { echo "无需卸载：$DST 不存在"; exit 0; }

if (( yes == 0 )); then
  echo "将删除：$DST"
  read -r -p "确认？(yes/N) " ans
  [[ "$ans" == "yes" ]] || { echo "已取消"; exit 1; }
fi
rm -rf "$DST"
echo "已删除 $DST"
echo "保留：features/harness.conf、features/<feature>/、各根 codegraph.json 与 .codegraph/"
