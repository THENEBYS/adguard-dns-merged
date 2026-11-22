#!/usr/bin/env bash
# AdGuard DNS 订阅合并：整行去重保 @@ 语义；统计写入头部；失败源跳过+告警；异常缩水不覆盖。
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/sources.txt"
OUT="$DIR/merged.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MIN_LINES=100        # 单源最少行数，低于此视为拉取异常（防 403/验证码页）
SHRINK_FLOOR=0.9     # 新结果不得低于旧结果的 90%，否则不覆盖

# 数字加千分位（纯 awk，不引依赖）
comma() { awk -v n="$1" 'BEGIN{s="";x=n+0;while(x>=1000){r=int(x)%1000;x=int(x/1000);s=sprintf(",%03d%s",r,s)}print x s}'; }

[ -f "$SRC" ] || { echo "FATAL: 找不到 $SRC" >&2; exit 1; }

ok=0; failed=0
raw_total=0; eff_total=0
: > "$TMP/all.txt"
: > "$TMP/detail.txt"      # 每源明细：状态|名称|原始行|有效行
: > "$TMP/warnings.txt"

while IFS= read -r url || [ -n "$url" ]; do
    case "$url" in ''|\#*) continue ;; esac   # 空行/注释跳过，加源只需加一行 URL
    name="${url##*/}"; name="${name%%\?*}"
    if curl --fail --silent --show-error --location --retry 3 --retry-delay 2 --max-time 90 "$url" -o "$TMP/src.txt" 2>/dev/null; then
        raw=$(wc -l < "$TMP/src.txt")
        if [ "$raw" -lt "$MIN_LINES" ]; then
            echo "- ⚠️ $name：仅 $raw 行（<$MIN_LINES），疑似异常，已跳过" >> "$TMP/warnings.txt"
            echo "skip|$name|$raw|0" >> "$TMP/detail.txt"
            failed=$((failed+1)); continue
        fi
        grep -vE '^[[:space:]]*(#|!|$)' "$TMP/src.txt" > "$TMP/eff.txt" || true
        eff=$(wc -l < "$TMP/eff.txt")
        cat "$TMP/eff.txt" >> "$TMP/all.txt"
        echo "ok|$name|$raw|$eff" >> "$TMP/detail.txt"
        raw_total=$((raw_total+raw)); eff_total=$((eff_total+eff))
        echo "OK: $name ($raw 行 → $eff 有效)"
        ok=$((ok+1))
    else
        echo "- ⚠️ $name：拉取失败，已跳过" >> "$TMP/warnings.txt"
        echo "fail|$name|0|0" >> "$TMP/detail.txt"
        failed=$((failed+1))
    fi
done < "$SRC"

[ "$ok" -ge 1 ] || { echo "FATAL: 所有源均失败，拒绝生成空列表（防止全屋 DNS 裸奔）" >&2; exit 1; }

# 整行去重 + 排序
sort -u "$TMP/all.txt" > "$TMP/merged"
final=$(wc -l < "$TMP/merged")

# 防缩水
if [ -f "$OUT" ]; then
    prev=$(wc -l < "$OUT")
    floor=$(awk -v p="$prev" -v f="$SHRINK_FLOOR" 'BEGIN{printf "%d",p*f}')
    if [ "$final" -lt "$floor" ]; then
        echo "FATAL: 新结果 $final 行 < 上次 $prev 行的 90% ($floor)，疑似源异常，拒绝覆盖" >&2
        cat "$TMP/warnings.txt" >&2
        exit 2
    fi
fi

removed_comment=$((raw_total-eff_total))
removed_dup=$((eff_total-final))
removed_total=$((raw_total-final))
pct=$(awk -v r="$removed_total" -v t="$raw_total" 'BEGIN{printf "%.1f",r*100/t}')

# 头部统计 + 明细（AGH 忽略所有 # 行）
{
    echo "# AdGuard DNS 合并规则 — 自动生成，请勿手改"
    echo "# 生成时间: $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "# ----------------------------------------"
    echo "# 合并统计"
    echo "#   源数量:        $ok 成功 / $failed 跳过"
    echo "#   原始规则总数:  $(comma "$raw_total") 行"
    echo "#   去注释/空行:   -$(comma "$removed_comment") 行"
    echo "#   整行去重删除:  -$(comma "$removed_dup") 行"
    echo "#   最终保留:      $(comma "$final") 行（压缩 $pct%）"
    echo "# ----------------------------------------"
    echo "# 各源明细（原始行 → 有效行）"
    while IFS='|' read -r st nm rw ef; do
        case "$st" in
            ok)   printf '#   %-22s %s → %s\n' "$nm" "$(comma "$rw")" "$(comma "$ef")" ;;
            *)    printf '#   %-22s 跳过（%s）\n' "$nm" "$st" ;;
        esac
    done < "$TMP/detail.txt"
    echo "# ----------------------------------------"
    echo '# 去重: 整行 sort -u，保留 @@ / $important 语义'
    [ -s "$TMP/warnings.txt" ] && { echo "# 告警:"; sed 's/^- ⚠️ /#   /' "$TMP/warnings.txt"; }
    echo ""
    cat "$TMP/merged"
} > "$OUT.new"
mv "$OUT.new" "$OUT"

echo "DONE: $final 行 → $OUT（原始 $raw_total，删除 $removed_total，$pct%）"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### AdGuard DNS 合并结果"
        echo "- 最终规则: **$(comma "$final")** 行"
        echo "- 原始总数: $(comma "$raw_total") 行，删除 $(comma "$removed_total") 行（$pct%）"
        echo "- 成功源: $ok / 跳过: $failed"
        [ -s "$TMP/warnings.txt" ] && { echo ""; cat "$TMP/warnings.txt"; }
    } >> "$GITHUB_STEP_SUMMARY"
fi
exit 0
