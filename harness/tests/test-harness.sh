#!/usr/bin/env bash
# tests/test-harness.sh —— 在临时假树里端到端验证 harness。
#
# 原则：
#   - **不碰**任何真实源码树；全部在 mktemp -d 里跑，结束即删；
#   - 不依赖 python3 / jq，只依赖 bash + git + coreutils + find/awk/sed；
#   - codegraph 相关的"真建库"用例在 codegraph 缺失时记为 SKIP（不是 PASS）；
#   - 断言全部是"命令退出码 + 输出内容"，不做模糊匹配。
#
# 用法：
#   bash tests/test-harness.sh              # 全量
#   bash tests/test-harness.sh --keep       # 保留临时目录便于排查
#   bash tests/test-harness.sh --no-index   # 跳过真建库（磁盘/时间敏感时）
#
# 退出码：0 全部 PASS 且无 FAIL；1 有 FAIL
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
KEEP=0; NO_INDEX=0
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP=1 ;;
    --no-index) NO_INDEX=1 ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: 未知参数 $arg" >&2; exit 2 ;;
  esac
done

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '      %s\n' "$2"; }
skip() { SKIP=$((SKIP + 1)); printf 'SKIP  %s\n' "$1"; }

out=""; rc=0
run() { out="$("$@" 2>&1)"; rc=$?; }
has() { printf '%s' "$out" | grep -qF -- "$1"; }
hasre() { printf '%s' "$out" | grep -qE -- "$1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/harness-test.XXXXXX")" || { echo "无法创建临时目录" >&2; exit 2; }
TREE="$WORK/tree"
cleanup() {
  if (( KEEP == 1 )); then
    echo
    echo "临时目录保留：$WORK"
  else
    rm -rf "$WORK" 2>/dev/null || true
  fi
}
trap cleanup EXIT

gitc() { git -C "$1" -c user.name=harness-test -c user.email=t@example.invalid -c safe.directory='*' "${@:2}"; }

# =============================================================================
echo "=============================================================="
echo " 0. 前置：仓库结构 / 语法"
echo "=============================================================="

for f in install.sh uninstall.sh harness/bootstrap.sh \
         harness/lib/common.sh harness/bin/cg-ensure harness/bin/cg-roots \
         harness/bin/cg-exclude harness/bin/cg-build harness/bin/cg-route \
         harness/bin/cg-assert harness/bin/check-drift harness/bin/feature-state \
         harness/bin/prepare-feature harness/bin/sync-skills harness/bin/verify-build \
         harness/templates/verify-feature.sh; do
  if [[ -f "$REPO_DIR/$f" ]]; then ok "存在 $f"; else bad "缺失 $f"; fi
done

syntax_bad=0
while IFS= read -r f; do
  if ! bash -n "$f" 2>"$WORK/syntax.err"; then
    bad "bash -n 失败：${f#"$REPO_DIR"/}" "$(head -n 2 "$WORK/syntax.err")"
    syntax_bad=1
  fi
done < <(find "$REPO_DIR" -type f \( -name '*.sh' -o -path '*/bin/*' \) -not -path '*/.git/*' -not -path '*/tests/*' | sort)
(( syntax_bad == 0 )) && ok "所有脚本 bash -n 通过"

# shellcheck（有则跑，没有则跳过）
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning -x "$REPO_DIR"/harness/bin/* "$REPO_DIR"/install.sh >"$WORK/shellcheck.log" 2>&1; then
    ok "shellcheck 无 warning"
  else
    bad "shellcheck 有问题" "$(head -n 5 "$WORK/shellcheck.log")"
  fi
else
  skip "shellcheck 未安装"
fi

# =============================================================================
echo
echo "=============================================================="
echo " 1. 假树 + install.sh"
echo "=============================================================="

mkdir -p "$TREE/alpha/src/sub" "$TREE/beta/src" "$TREE/alpha/out" "$TREE/alpha/tests" "$TREE/alpha/prebuilts"
printf 'int main(void){return 0;}\n' > "$TREE/alpha/src/a.c"
printf 'int sub(void){return 2;}\n'  > "$TREE/alpha/src/sub/s.c"
printf 'int b(void){return 1;}\n'    > "$TREE/beta/src/b.c"
printf 'x\n' > "$TREE/alpha/out/generated.o"
printf 'x\n' > "$TREE/alpha/tests/t.c"
printf '.gitignore\n' > "$TREE/.gitignore"
git init -q "$TREE" >/dev/null 2>&1
gitc "$TREE" add -A >/dev/null 2>&1
gitc "$TREE" commit -qm init >/dev/null 2>&1
[[ -d "$TREE/.git" ]] && ok "假树已 git init + 首次提交" || bad "假树 git 初始化失败"

run bash "$REPO_DIR/install.sh" --dry-run --tree "$TREE"
[[ $rc -eq 0 ]] && has 'dry-run' && ok "install.sh --dry-run" || bad "install.sh --dry-run" "$out"

run bash "$REPO_DIR/install.sh" --tree "$TREE"
[[ $rc -eq 0 ]] && ok "install.sh 安装成功" || bad "install.sh 安装失败" "$out"
[[ -x "$TREE/features/.harness/bin/cg-route" ]] && ok "cg-route 已安装且可执行" || bad "cg-route 未安装或不可执行"
[[ -f "$TREE/features/.harness/lib/common.sh" ]] && ok "common.sh 已安装" || bad "common.sh 未安装"
[[ -f "$TREE/features/.harness/templates/verify-feature.sh" ]] && ok "templates 已安装" || bad "templates 未安装"
[[ -f "$TREE/features/harness.conf" ]] && ok "harness.conf 已生成" || bad "harness.conf 未生成"

# 幂等：再装一次不得覆盖已改过的文件
printf '# local edit\n' >> "$TREE/features/.harness/lib/common.sh"
run bash "$REPO_DIR/install.sh" --tree "$TREE"
if grep -q '# local edit' "$TREE/features/.harness/lib/common.sh"; then
  ok "install.sh 幂等：不覆盖已有文件"
else
  bad "install.sh 覆盖了已有文件"
fi

# 改成可控配置（3 个根，含嵌套根用于测最长前缀）
cat > "$TREE/features/harness.conf" <<'CONF'
ROOTS=("alpha" "alpha/src" "beta")
ALIASES=("a=alpha")
EXCLUDE_DIR_CANDIDATES=("out" "tests" "prebuilts" "build" "nonexistentdir")
EXCLUDE_FILE_PATTERNS=("**/*.o" "**/*.so" "**/*.xyz")
EXTRA_EXCLUDE=()
EXCLUDE_SCAN_DEPTH_DIR=3
EXCLUDE_SCAN_DEPTH_FILE=4
CODEGRAPH_MIN_VERSION="1.6.0"
CODEGRAPH_MCP_TARGETS=""
BUILD_SERIAL=1
CONF
ok "写入测试用 harness.conf（3 根 + 1 别名）"

BIN="$TREE/features/.harness/bin"

# =============================================================================
echo
echo "=============================================================="
echo " 2. cg-roots（配置 → 路由表）"
echo "=============================================================="

run bash "$BIN/cg-roots" list
[[ $rc -eq 0 ]] && has 'alpha' && has 'beta' && ok "cg-roots list" || bad "cg-roots list" "$out"

run bash "$BIN/cg-roots" sync
[[ $rc -eq 0 ]] && ok "cg-roots sync" || bad "cg-roots sync" "$out"
TSV="$TREE/features/.harness/codegraph-roots.tsv"
[[ -f "$TSV" ]] && ok "路由表已生成" || bad "路由表未生成"
nroots="$(awk -F'\t' '!/^#/ && $1!="dir" && NF>=5' "$TSV" | wc -l | tr -d ' ')"
[[ "$nroots" == 4 ]] && ok "路由表行数 = 4（3 根 + 1 别名）" || bad "路由表行数 = $nroots（期望 4）"
awk -F'\t' '$1=="a" && $5=="alpha"' "$TSV" | grep -q . && ok "别名行 a → db_root alpha" || bad "别名行不正确"

run bash "$BIN/cg-roots" add gamma
[[ $rc -eq 0 ]] && grep -q '"gamma"' "$TREE/features/harness.conf" && ok "cg-roots add 写回配置" || bad "cg-roots add 失败" "$out"
run bash "$BIN/cg-roots" rm gamma
! grep -q '"gamma"' "$TREE/features/harness.conf" && ok "cg-roots rm 从配置删除" || bad "cg-roots rm 失败"

# =============================================================================
echo
echo "=============================================================="
echo " 3. cg-route（最长前缀 / 别名 / 树根拒绝）"
echo "=============================================================="

run bash "$BIN/cg-route" --quiet "$TREE/alpha/src/sub/s.c"
[[ $rc -eq 0 ]] && [[ "$(printf '%s' "$out" | cut -f1)" == "alpha/src" ]] \
  && ok "嵌套根按最长前缀命中 alpha/src" || bad "最长前缀失败" "$out"

run bash "$BIN/cg-route" --quiet "$TREE/alpha/out/generated.o"
[[ $rc -eq 0 ]] && [[ "$(printf '%s' "$out" | cut -f1)" == "alpha" ]] \
  && ok "非嵌套路径命中 alpha" || bad "alpha 路由失败" "$out"

run bash "$BIN/cg-route" "$TREE/alpha/src/a.c"
[[ $rc -eq 0 ]] && has 'projectPath' && ok "人读输出含 projectPath" || bad "人读输出缺 projectPath" "$out"

run bash "$BIN/cg-route" "$TREE"
[[ $rc -eq 1 ]] && has '源码树根' && ok "树根被拒绝（exit 1）" || bad "树根未被拒绝（rc=$rc）" "$out"

run bash "$BIN/cg-route" --list
[[ $rc -eq 0 ]] && has 'alpha' && ok "cg-route --list" || bad "cg-route --list" "$out"

# =============================================================================
echo
echo "=============================================================="
echo " 4. cg-exclude（按实况生成排除）"
echo "=============================================================="

run bash "$BIN/cg-exclude" --dry-run alpha
[[ $rc -eq 0 ]] && has 'out/**' && has 'tests/**' && ok "干跑：探测到 out/ 与 tests/" || bad "干跑探测失败" "$out"
has 'prebuilts/**' && ok "干跑：探测到 prebuilts/" || bad "prebuilts 未探测到" "$out"
if has 'nonexistentdir' || has 'build/**'; then
  bad "写入/预览了不存在的目录（应为空规则）" "$out"
else
  ok "不存在的目录未写入（build/ nonexistentdir）"
fi
has '**/*.o' && ok "探测到 *.o 文件模式" || bad "*.o 未探测到" "$out"
if has '**/*.xyz'; then bad "不存在的扩展名被写入"; else ok "不存在的扩展名未写入（*.xyz）"; fi

run bash "$BIN/cg-exclude" alpha
[[ $rc -eq 0 ]] && [[ -f "$TREE/alpha/codegraph.json" ]] && ok "生成 alpha/codegraph.json" || bad "未生成 codegraph.json" "$out"
grep -q '"out/\*\*"' "$TREE/alpha/codegraph.json" && ok "json 含 out/**" || bad "json 缺 out/**"
grep -q '"extensions"' "$TREE/alpha/codegraph.json" && bad "json 混入了非 exclude 键" || ok "json 只含 exclude 键"

# 已有其它键 → 拒绝覆盖
python_free_patch() { printf '{ "extensions": [".c"], "exclude": ["foo/**"] }\n' > "$TREE/alpha/codegraph.json"; }
python_free_patch
run bash "$BIN/cg-exclude" alpha
[[ $rc -eq 1 ]] && has '拒绝覆盖' && ok "含其它键时拒绝覆盖（exit 1）" || bad "未拒绝覆盖（rc=$rc）" "$out"

run bash "$BIN/cg-exclude" --force alpha
[[ $rc -eq 0 ]] && grep -q '"out/\*\*"' "$TREE/alpha/codegraph.json" && ok "--force 覆盖并重写" || bad "--force 覆盖失败" "$out"
ls "$TREE"/alpha/codegraph.json.bak.* >/dev/null 2>&1 && ok "--force 前已备份" || bad "未生成备份"

# =============================================================================
echo
echo "=============================================================="
echo " 5. cg-build（计划 / 跳过 / 真建库）"
echo "=============================================================="

if command -v codegraph >/dev/null 2>&1; then
  run bash "$BIN/cg-build" --dry-run
  [[ $rc -eq 0 ]] && ok "cg-build --dry-run" || bad "cg-build --dry-run" "$out"
  [[ "$(printf '%s\n' "$out" | grep -c '^PLAN')" == 3 ]] && ok "计划 3 个根" \
    || bad "计划行数异常" "$out"

  run bash "$BIN/cg-build" --dry-run --only gamma
  [[ $rc -eq 0 ]] && has 'SKIP  gamma' && ok "不存在的根被 SKIP" || bad "不存在的根未 SKIP" "$out"

  if (( NO_INDEX == 0 )); then
    run bash "$BIN/cg-build" --only alpha --only beta
    [[ $rc -eq 0 ]] && ok "真建库 alpha/beta（cg-build）" || bad "真建库失败" "$(printf '%s' "$out" | tail -n 8)"
    [[ -f "$TREE/alpha/.codegraph/codegraph.db" ]] && ok "alpha 库文件存在" || bad "alpha 库文件缺失"
    [[ -f "$TREE/beta/.codegraph/codegraph.db" ]] && ok "beta 库文件存在" || bad "beta 库文件缺失"
  else
    skip "真建库（--no-index）"
  fi
else
  run bash "$BIN/cg-build" --dry-run
  [[ $rc -eq 3 ]] && has 'codegraph 未安装' && ok "codegraph 缺失时 cg-build exit 3" || bad "codegraph 缺失时行为不对（rc=$rc）" "$out"
  skip "真建库（codegraph 未安装）"
fi

# =============================================================================
echo
echo "=============================================================="
echo " 6. cg-assert（新鲜度 / 语言 / 诚实性）"
echo "=============================================================="

run bash "$BIN/cg-assert" env
[[ $rc -eq 1 ]] && ok "cg-assert env：缺库时 exit 1（不假绿）" || bad "cg-assert env 未报缺库（rc=$rc）" "$out"

if command -v codegraph >/dev/null 2>&1 && (( NO_INDEX == 0 )); then
  run bash "$BIN/cg-assert" fresh alpha
  [[ $rc -eq 0 ]] && has 'fresh' && ok "alpha 库新鲜（FRESH）" || bad "alpha 新鲜度判定失败（rc=$rc）" "$out"

  run bash "$BIN/cg-assert" langs alpha
  [[ $rc -eq 0 ]] && has 'SUMMARY files=' && ok "cg-assert langs 实测语言" || bad "langs 失败" "$out"

  run bash "$BIN/cg-assert" env --probe
  ok "cg-assert env --probe 可执行（输出：$(printf '%s\n' "$out" | head -n 1)）"
else
  skip "cg-assert fresh/langs（无 codegraph 或 --no-index）"
fi

run bash "$BIN/cg-assert" fresh gamma
[[ $rc -eq 1 ]] && has 'missing' && ok "未建库的根报 missing（exit 1）" || bad "未建库的根判定不对（rc=$rc）" "$out"

# =============================================================================
echo
echo "=============================================================="
echo " 7. feature 生命周期（repos → capture → drift）"
echo "=============================================================="

FDIR="$TREE/features/demo"
mkdir -p "$FDIR"
printf '# repo\tfeature\tdesc\troot\nalpha\tdemo\t测试树\talpha\n' > "$FDIR/repos.tsv"
printf '# 只有注释\n' > "$FDIR/assertions.tsv"
cp "$TREE/features/.harness/templates/feature-drift-ignore" "$FDIR/.drift-ignore"
cp "$TREE/features/.harness/templates/feature-AGENTS.md" "$FDIR/AGENTS.md"
sed 's/<FEATURE>/demo/g' "$TREE/features/.harness/templates/verify-feature.sh" > "$FDIR/verify-demo.sh"
chmod +x "$FDIR/verify-demo.sh"
ok "feature 目录与模板已创建"

run bash "$BIN/feature-state" capture demo
[[ $rc -eq 0 ]] && [[ -f "$FDIR/baseline.tsv" ]] && ok "feature-state capture" || bad "feature-state capture 失败" "$out"
[[ "$(grep -cvE '^#' "$FDIR/baseline.tsv")" == 1 ]] && ok "baseline.tsv 1 行基线" || bad "baseline.tsv 行数异常"

run bash "$BIN/check-drift" demo
[[ $rc -eq 0 ]] && has 'drift=no' && ok "check-drift：无漂移" || bad "check-drift 误报漂移（rc=$rc）" "$out"

printf 'int main(void){return 9;}\n' > "$TREE/alpha/src/a.c"
gitc "$TREE" add -A >/dev/null 2>&1
gitc "$TREE" commit -qm 'change alpha' >/dev/null 2>&1
run bash "$BIN/check-drift" demo
[[ $rc -eq 1 ]] && has 'DRIFT' && ok "check-drift：检测到漂移（exit 1）" || bad "漂移未被检测（rc=$rc）" "$out"

run bash "$BIN/feature-state" capture demo
[[ $rc -eq 0 ]] && ok "重新 capture 后基线更新" || bad "重新 capture 失败" "$out"
run bash "$BIN/check-drift" demo
[[ $rc -eq 0 ]] && ok "重新 capture 后无漂移" || bad "重新 capture 后仍报漂移" "$out"

# --strict：范围外脏文件
printf 'stray\n' > "$TREE/stray.txt"
run bash "$BIN/check-drift" demo --strict
[[ $rc -eq 1 ]] && has '范围外脏文件' && ok "--strict 抓到范围外脏文件" || bad "--strict 未抓到（rc=$rc）" "$out"

printf 'stray.txt\n.drift-ignore\nfeatures/*\n' > "$FDIR/.drift-ignore"
run bash "$BIN/check-drift" demo --strict
[[ $rc -eq 0 ]] && ok ".drift-ignore 生效（--strict 通过）" || bad ".drift-ignore 未生效（rc=$rc）" "$out"
rm -f "$TREE/stray.txt"

# prepare-feature
run bash "$BIN/prepare-feature" demo
[[ $rc -eq 0 ]] && has 'feature=demo' && ok "prepare-feature" || bad "prepare-feature 失败（rc=$rc）" "$out"

# =============================================================================
echo
echo "=============================================================="
echo " 8. verify-build（不构建，只判定产物）"
echo "=============================================================="

printf '#### build completed successfully\n' > "$WORK/build.log"
printf 'artifact\n' > "$WORK/Image"
sleep 1
run bash "$BIN/verify-build" --log "$WORK/build.log" --since 0 --artifact "$WORK/Image"
[[ $rc -eq 0 ]] && has 'PASS' && ok "verify-build：成功标记 + 产物存在 → PASS" || bad "verify-build 误判失败（rc=$rc）" "$out"

run bash "$BIN/verify-build" --log "$WORK/build.log" --since 0 --artifact "$WORK/nope.img"
[[ $rc -eq 1 ]] && has 'FAIL' && ok "verify-build：产物缺失 → FAIL" || bad "verify-build 未报缺失（rc=$rc）" "$out"

printf 'no marker here\n' > "$WORK/bad.log"
run bash "$BIN/verify-build" --log "$WORK/bad.log"
[[ $rc -eq 1 ]] && ok "verify-build：无成功标记 → FAIL" || bad "无标记未判失败（rc=$rc）" "$out"

run bash "$BIN/verify-build" --log "$WORK/nonexistent.log"
[[ $rc -eq 3 ]] && ok "verify-build：日志缺失 → INCOMPLETE(3)" || bad "日志缺失未判 3（rc=$rc）" "$out"

# =============================================================================
echo
echo "=============================================================="
echo " 9. verify-<feature>.sh（四段验收 / 诚实性）"
echo "=============================================================="

# 9.1 assertions 为空 → 必须 INCOMPLETE
run bash "$FDIR/verify-demo.sh" --demo
[[ $rc -eq 1 ]] && has 'RESULT INCOMPLETE' && has '功能断言未定义' \
  && ok "空 assertions → RESULT INCOMPLETE（不是通过）" || bad "空 assertions 未判 INCOMPLETE（rc=$rc）" "$out"

# 9.2 有阈值、有数据 → PASS（需要 BUILD/DEVICE/STATIC 都过）
cat > "$FDIR/assertions.tsv" <<'TSV'
# metric	op	threshold	unit	required	note
boot_total	<=	12	s	yes	冷启动总时长
first_frame	<=	3.5	s	yes	首帧
cpu_idle	>=	60	%	no	仅观察
TSV
printf 'round,boot_total_s,first_frame_s,cpu_idle_pct\n1,10.2,2.8,71\n' > "$WORK/metrics.csv"

if command -v codegraph >/dev/null 2>&1 && (( NO_INDEX == 0 )); then
  # 9.2a 诚实性：索引落后于最新提交时必须 INCOMPLETE（前一步刚提交过 alpha 改动）
  run bash "$FDIR/verify-demo.sh" --demo --log "$WORK/build.log" --since 0 \
        --artifact "$WORK/Image" --metrics "$WORK/metrics.csv"
  if [[ $rc -eq 1 ]] && has 'RESULT INCOMPLETE'; then
    ok "库落后于最新提交 → RESULT INCOMPLETE（不假绿）"
  else
    bad "stale 库未判 INCOMPLETE（rc=$rc）" "$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL|SKIP|RESULT)' | head -n 6)"
  fi

  # 9.2b 同步后应 PASS
  run bash "$BIN/cg-build" --only alpha
  [[ $rc -eq 0 ]] && ok "cg-build 增量同步 alpha" || bad "增量同步失败" "$out"
  # 基线必须与当前 HEAD 一致（前一步已重新 capture）
  run bash "$FDIR/verify-demo.sh" --demo --log "$WORK/build.log" --since 0 \
        --artifact "$WORK/Image" --metrics "$WORK/metrics.csv"
  [[ $rc -eq 0 ]] && has 'RESULT PASS' \
    && ok "四段全通 → RESULT PASS" || bad "全通未判 PASS（rc=$rc）" "$(printf '%s\n' "$out" | grep -E '^(FAIL|SKIP|RESULT)' | head -n 6)"
else
  run bash "$FDIR/verify-demo.sh" --demo --log "$WORK/build.log" --since 0 \
        --artifact "$WORK/Image" --metrics "$WORK/metrics.csv"
  has 'SKIP' && ok "无 codegraph 时静态段 SKIP 而非假绿（$(printf '%s\n' "$out" | tail -n 1)）" \
    || bad "无 codegraph 时未 SKIP" "$out"
fi

# 9.3 阈值不满足 → FAIL
printf 'round,boot_total_s,first_frame_s,cpu_idle_pct\n1,99.9,2.8,71\n' > "$WORK/metrics-bad.csv"
run bash "$FDIR/verify-demo.sh" --demo --log "$WORK/build.log" --since 0 \
      --artifact "$WORK/Image" --metrics "$WORK/metrics-bad.csv"
[[ $rc -eq 1 ]] && has 'RESULT FAIL' && has 'boot_total = 99.9' \
  && ok "阈值不满足 → RESULT FAIL" || bad "阈值不满足未判 FAIL（rc=$rc）" "$out"

# 9.4 指标列缺失 → SKIP（数据不可判定），不当作满足
printf 'round,other_s\n1,5\n' > "$WORK/metrics-miss.csv"
run bash "$FDIR/verify-demo.sh" --demo --log "$WORK/build.log" --since 0 \
      --artifact "$WORK/Image" --metrics "$WORK/metrics-miss.csv"
has '没有该列' && ! has 'RESULT PASS' && ok "指标列缺失 → SKIP，不假绿" || bad "指标列缺失处理错误" "$out"

# 9.5 值 NA → SKIP
printf 'round,boot_total_s,first_frame_s,cpu_idle_pct\n1,NA,2.8,71\n' > "$WORK/metrics-na.csv"
run bash "$FDIR/verify-demo.sh" --demo --log "$WORK/build.log" --since 0 \
      --artifact "$WORK/Image" --metrics "$WORK/metrics-na.csv"
has '不可测' && ! has 'RESULT PASS' && ok "值为 NA → SKIP，不假绿" || bad "NA 处理错误" "$out"

# 9.6 --allow-skip 只能与 --demo 连用
run bash "$FDIR/verify-demo.sh" --allow-skip
[[ $rc -eq 2 ]] && ok "--allow-skip 单独使用被拒绝（exit 2）" || bad "--allow-skip 未被拒绝（rc=$rc）" "$out"

# =============================================================================
echo
echo "=============================================================="
echo " 10. sync-skills / bootstrap --help / uninstall"
echo "=============================================================="

run bash "$BIN/sync-skills" --dry-run
[[ $rc -eq 0 ]] && ok "sync-skills --dry-run" || bad "sync-skills 失败" "$out"

run bash "$TREE/features/.harness/bootstrap.sh" --help
[[ $rc -eq 0 ]] && has 'bootstrap' && ok "bootstrap --help" || bad "bootstrap --help 失败" "$out"

# 全流程 smoke（只读检查 + 跳过建库）：必须四段都跑到，且以明确结论收尾
run bash "$TREE/features/.harness/bootstrap.sh" --check --skip-build
if has '1/4' && has '2/4' && has '3/4' && has '4/4' && hasre '^BOOTSTRAP (OK|INCOMPLETE)'; then
  ok "bootstrap --check --skip-build 四段齐全（$(printf '%s\n' "$out" | tail -n 1)）"
else
  bad "bootstrap 流程不完整（rc=$rc）" "$(printf '%s\n' "$out" | tail -n 12)"
fi

run bash "$REPO_DIR/uninstall.sh" --tree "$TREE" --yes
[[ $rc -eq 0 ]] && [[ ! -d "$TREE/features/.harness" ]] && ok "uninstall 删除框架目录" || bad "uninstall 失败" "$out"
[[ -f "$TREE/features/harness.conf" ]] && ok "uninstall 保留 harness.conf" || bad "uninstall 误删配置"
[[ -f "$TREE/alpha/codegraph.json" ]] && ok "uninstall 保留 codegraph.json" || bad "uninstall 误删 codegraph.json"
if (( NO_INDEX == 0 )) && command -v codegraph >/dev/null 2>&1; then
  [[ -d "$TREE/alpha/.codegraph" ]] && ok "uninstall 保留 .codegraph" || bad "uninstall 误删索引"
else
  # --no-index 下 alpha/.codegraph 从未被创建，此断言不成立，记 SKIP 而不是伪造 PASS
  skip "uninstall 保留 .codegraph（--no-index 未建库）"
fi

# =============================================================================
echo
echo "=============================================================="
printf 'SUMMARY PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
echo "=============================================================="
(( FAIL == 0 )) || exit 1
exit 0
