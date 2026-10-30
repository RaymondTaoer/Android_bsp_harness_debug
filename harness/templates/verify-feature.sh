#!/usr/bin/env bash
# features/<FEATURE>/verify-<FEATURE>.sh
#
# 四段验收：STATIC（codegraph，离线）→ BUILD（判定已有产物）→ DEVICE（adb）→ FEATURE（功能断言）。
#
# 诚实性：功能断言的**阈值**由人写在 assertions.tsv；文件缺失或无生效行时 FEATURE 段固定 SKIP，
#         正常结果应为 RESULT INCOMPLETE —— 不是通过。
#
# 本文件是模板：复制到 features/<FEATURE>/ 后，把 <FEATURE> 换成真实 feature 名即可。
# 平台专属断言（型号、分区、专有属性）直接加在 DEVICE 段后面，不要改判定协议。
#
# 用法：verify-<FEATURE>.sh [--demo] [--allow-skip] [--since EPOCH] [--log FILE]
#                           [--artifact PATH]... [--metrics CSV] [--assertions FILE]
set -uo pipefail

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HARNESS_ROOT_EXPORT="$(cd "$FEATURE_DIR/../.." && pwd -P)"
export HARNESS_ROOT="$HARNESS_ROOT_EXPORT"
# shellcheck source=../.harness/lib/common.sh
source "$FEATURE_DIR/../.harness/lib/common.sh"

FEATURE="$(basename "$FEATURE_DIR")"
BIN="$HARNESS_ROOT/features/.harness/bin"
STATE_DIR="$HARNESS_ROOT/features/.harness/.state"

usage() {
  cat <<'EOF'
usage: verify-<FEATURE>.sh [--demo] [--allow-skip] [--since EPOCH] [--log FILE]
                          [--artifact PATH]... [--metrics CSV] [--assertions FILE] [--help]

  --log FILE        构建日志（BUILD 段判定用；不给则 SKIP）
  --artifact PATH   必需产物（可多次）
  --since EPOCH     本次构建开始时间（产物 mtime 必须更新）
  --metrics CSV     FEATURE 段的数据（表头列名对应 assertions.tsv 的 metric）
  --assertions FILE 改用指定阈值文件（默认 features/<FEATURE>/assertions.tsv）
EOF
}

demo=0; allow_skip=0; since=""; build_log=""; metrics_csv=""; assertions_file=""; artifacts=()
while (($# > 0)); do
  case "$1" in
    --demo) demo=1; shift ;;
    --allow-skip) allow_skip=1; shift ;;
    --since) since="${2:-}"; shift 2 ;;
    --log) build_log="${2:-}"; shift 2 ;;
    --metrics) metrics_csv="${2:-}"; shift 2 ;;
    --assertions) assertions_file="${2:-}"; shift 2 ;;
    --artifact) artifacts+=("${2:-}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
if (( demo == 0 && allow_skip == 1 )); then
  echo 'error: --allow-skip 只能与 --demo 连用' >&2
  exit 2
fi

pass=0; fail=0; skip=0
p() { echo "PASS  $1"; pass=$((pass + 1)); }
f() { echo "FAIL  $1"; fail=$((fail + 1)); }
s() { echo "SKIP  $1"; skip=$((skip + 1)); }

mkdir -p "$STATE_DIR"

# ---------------- STATIC ----------------
echo "=== STATIC (codegraph, offline) ==="

repos_file="$FEATURE_DIR/repos.tsv"
if [[ -f "$repos_file" ]]; then
  p "repos.tsv 存在（$(grep -cvE '^[[:space:]]*(#|$)' "$repos_file") 个仓）"
else
  f "repos.tsv 缺失"
fi

missing_repos=0
while IFS=$'\t' read -r repo _feature _desc root || [[ -n "${repo:-}" ]]; do
  [[ -z "${repo:-}" || "$repo" == \#* ]] && continue
  if [[ -d "$HARNESS_ROOT/$repo" ]]; then
    :
  else
    f "仓不存在：$repo"
    missing_repos=$((missing_repos + 1))
  fi
done < "$repos_file"
(( missing_repos == 0 )) && p "全部涉及仓存在"

roots="$(awk -F'\t' '!/^#/ && NF>=4 {print $4}' "$repos_file" 2>/dev/null | sort -u)"
while IFS= read -r r; do
  [[ -z "$r" ]] && continue
  line="$(db_status "$r")"
  state="${line%%$'\t'*}"
  detail="${line#*$'\t'}"
  case "$state" in
    fresh|stale)
      # mtime 只能说明"索引时间"，不能说明"库能读"。再打一次真实查询。
      probe_out="$(bash "$BIN/cg-assert" langs "$r" 2>&1)"; probe_rc=$?
      if [[ "$probe_rc" -eq 0 ]]; then
        if [[ "$state" == fresh ]]; then
          p "codegraph 可查且新鲜：$r（$(printf '%s\n' "$probe_out" | tail -n 1)）"
        else
          s "codegraph 可查但已过期：$r（$detail）→ 环境未就绪"
        fi
      else
        s "codegraph 不可查：$r（$(printf '%s\n' "$probe_out" | head -n 1)）→ 需重建索引"
      fi
      ;;
    missing) s "codegraph 库缺失：$r" ;;
    *) s "codegraph 库状态未知：$r（$detail）" ;;
  esac
done <<<"$roots"

if [[ -f "$FEATURE_DIR/baseline.tsv" ]]; then
  p "baseline.tsv 存在"
else
  f "baseline.tsv 缺失（先跑 features/.harness/bin/feature-state capture $FEATURE）"
fi

drift_log="$STATE_DIR/drift-$FEATURE-$$.log"
drift_rc=0
bash "$BIN/check-drift" "$FEATURE" --quiet >"$drift_log" 2>&1 || drift_rc=$?
case "$drift_rc" in
  0) p "漂移守卫通过" ;;
  1) f "漂移守卫失败：$(tr '\n' ';' <"$drift_log")" ;;
  *) s "漂移守卫不可用（exit $drift_rc）" ;;
esac
rm -f "$drift_log"

# ---------------- BUILD ----------------
echo "=== BUILD (判定已有产物，不执行构建) ==="
if [[ -z "$build_log" ]]; then
  s "未提供 --log，跳过构建判定（环境未就绪）"
else
  args=(--log "$build_log")
  [[ -n "$since" ]] && args+=(--since "$since")
  for a in "${artifacts[@]:-}"; do [[ -n "${a:-}" ]] && args+=(--artifact "$a"); done
  out="$(bash "$BIN/verify-build" "${args[@]}" 2>&1)" || true
  printf '%s\n' "$out" | grep -E '^(PASS|FAIL|SKIP)' || true
  pass=$((pass + $(printf '%s\n' "$out" | grep -c '^PASS' || true)))
  fail=$((fail + $(printf '%s\n' "$out" | grep -c '^FAIL' || true)))
  skip=$((skip + $(printf '%s\n' "$out" | grep -c '^SKIP' || true)))
fi

# ---------------- DEVICE ----------------
echo "=== DEVICE (adb) ==="
serial="${ANDROID_SERIAL:-}"
if (( demo == 1 )); then
  boot_completed="${DEMO_BOOT_COMPLETED:-1}"
  system_server="${DEMO_SYSTEM_SERVER:-1234}"
  (( boot_completed == 1 )) && p "sys.boot_completed = 1 (demo)" || f "sys.boot_completed != 1 (demo)"
  [[ -n "$system_server" ]] && p "system_server pid = $system_server (demo)" || f "system_server pid 为空 (demo)"
elif [[ -z "$serial" ]]; then
  s "未设置 ANDROID_SERIAL，跳过设备段（环境未就绪）"
else
  adb=(adb -s "$serial")
  if "${adb[@]}" get-state >/dev/null 2>&1; then
    p "adb 连接正常：$serial"
    if bc="$("${adb[@]}" shell getprop sys.boot_completed 2>/dev/null)"; then
      [[ "$(printf '%s' "$bc" | tr -d '\r' | tr -d '[:space:]')" == 1 ]] && p "sys.boot_completed = 1" || f "sys.boot_completed != 1"
    else
      f "sys.boot_completed 查询失败"
    fi
    if ss="$("${adb[@]}" shell pidof system_server 2>/dev/null)"; then
      [[ -n "$(printf '%s' "$ss" | tr -d '\r\n[:space:]')" ]] && p "system_server pid = $ss" || f "system_server pid 为空"
    else
      f "system_server 查询失败"
    fi
    base_file="$FEATURE_DIR/.state/boot_id"
    if [[ -f "$base_file" ]]; then
      old_id="$(cat "$base_file")"
      if new_id="$("${adb[@]}" shell cat /proc/sys/kernel/random/boot_id 2>/dev/null)"; then
        [[ "$new_id" != "$old_id" ]] && p "boot_id 已变化（部署后已重启）" || f "boot_id 未变化（部署未生效）"
      else
        f "boot_id 查询失败"
      fi
    else
      s "无部署前 boot_id 基线，跳过重启校验"
    fi
  else
    f "adb 连接失败：$serial"
  fi
fi

# 平台专属断言加在这里（示例）：
# if (( demo == 0 )) && [[ -n "$serial" ]]; then
#   hw="$("${adb[@]}" shell getprop ro.hardware 2>/dev/null)"
#   [[ "$hw" == "<期望值>" ]] && p "ro.hardware = $hw" || f "ro.hardware = $hw（期望 <期望值>）"
# fi

# ---------------- FEATURE ----------------
# 功能断言 = assertions.tsv（阈值由人定） + 指标数据 CSV。
# 两条铁律：
#   1) assertions.tsv 缺失或没有生效行 → SKIP，绝不默认通过；
#   2) 指标列缺失或值为空（n/a）→ SKIP（数据不可判定），不当成满足阈值。
echo "=== FEATURE (功能断言) ==="
[[ -z "$assertions_file" ]] && assertions_file="$FEATURE_DIR/assertions.tsv"

active_rows=0
if [[ -f "$assertions_file" ]]; then
  active_rows="$(grep -cvE '^[[:space:]]*(#|$)' "$assertions_file" || true)"
fi

if (( active_rows == 0 )); then
  s "功能断言未定义：$assertions_file 缺失或无生效行（模板见 harness/templates/feature-assertions.tsv）"
elif [[ -z "$metrics_csv" ]]; then
  s "缺少指标数据：用 --metrics <csv> 传入（表头列名需与 assertions.tsv 的 metric 对应）"
elif [[ ! -f "$metrics_csv" ]]; then
  s "指标数据不存在：$metrics_csv"
else
  header="$(head -n 1 "$metrics_csv" | tr -d '\r')"
  # 取最后一条数据行：CSV 可能含多轮（rounds），默认取最新一轮
  data="$(awk 'NF>0 && !/^[[:space:]]*#/ {last=$0} END {print last}' "$metrics_csv" | tr -d '\r')"
  if [[ -z "$data" ]]; then
    s "指标 CSV 无数据行：$metrics_csv"
  else
    # tr -d '\r'：Windows 上编辑的 TSV 常是 CRLF，不去掉会让列名匹配失败
    while IFS=$'\t' read -r metric op threshold unit required note || [[ -n "${metric:-}" ]]; do
      [[ -z "${metric:-}" || "$metric" == \#* ]] && continue
      [[ "$required" == "no" ]] && continue
      # 定位列号（按表头名字匹配，不写死列序）。
      # 容忍单位后缀：foo / foo_s / foo_ms 都认。
      col="$(printf '%s\n' "$header" | awk -F',' -v m="$metric" '{
          base=m; sub(/_(s|ms)$/, "", base);
          for (i=1;i<=NF;i++) {
            c=$i; gsub(/^[ \t]+|[ \t]+$/, "", c);
            if (c==m || c==base || c==base"_s" || c==base"_ms") { print i; exit }
          }
        }')"
      if [[ -z "$col" ]]; then
        s "$metric：指标数据里没有该列（数据不可判定）"
        continue
      fi
      val="$(printf '%s' "$data" | awk -F',' -v c="$col" '{print $c}' | tr -d '\r ')"
      if [[ -z "$val" || "$val" == "n/a" || "$val" == "NA" ]]; then
        s "$metric：值为空/不可测（数据不可判定）"
        continue
      fi
      res="$(awk -v v="$val" -v t="$threshold" -v o="$op" 'BEGIN{
            if (v+0 != v) { print "NONNUM"; exit }
            if (o=="<=") print (v<=t)?"OK":"NG";
            else if (o=="<") print (v<t)?"OK":"NG";
            else if (o==">=") print (v>=t)?"OK":"NG";
            else if (o==">") print (v>t)?"OK":"NG";
            else if (o=="==") print (v==t)?"OK":"NG";
            else print "BADOP";
          }')"
      case "$res" in
        OK)     p "$metric = ${val}${unit}（要求 $op $threshold${unit}）" ;;
        NG)     f "$metric = ${val}${unit}（要求 $op $threshold${unit}）" ;;
        NONNUM) s "$metric：值 \"$val\" 不是数字（数据不可判定）" ;;
        BADOP)  f "$metric：不支持的操作符 \"$op\"（只认 <= < >= > ==）" ;;
        *)      s "$metric：判定失败（内部错误）" ;;
      esac
    done < <(tr -d '\r' < "$assertions_file")
  fi
fi

echo "SUMMARY PASS=$pass FAIL=$fail SKIP=$skip"
if (( fail > 0 )); then
  echo "RESULT FAIL"; exit 1
elif (( skip > 0 && allow_skip == 0 )); then
  echo "RESULT INCOMPLETE"; exit 1
elif (( skip > 0 )); then
  echo "RESULT INCOMPLETE"; exit 0
else
  echo "RESULT PASS"; exit 0
fi
