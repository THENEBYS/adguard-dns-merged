#!/usr/bin/env bash
# AdGuard DNS 订阅合并：整行去重保 @@ 语义，失败源跳过+告警，异常缩水不覆盖。
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/sources.txt"
OUT="$DIR/merged.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MIN_LINES=100        # 单源最少行数，低于此视为拉取异常（防 403/验证码页）
SHRINK_FLOOR=0.9     # 新结果不得低于旧结果的 90%，否则不覆盖

[ -f "$SRC" ] || { echo "FATAL: 找不到 $SRC" >&2; exit 1; }

ok=0; failed=0
: > "$TMP/all.txt"
: > "$TMP/warnings.txt"

while IFS= read -r url || [ -n "$url" ]; do
    case "$url" in ''|\#*) continue ;; esac
    name="${url##*/}"; name="${name%%\?*}"
    if curl --fail --silent --show-error --location --retry 3 --retry-delay 2 --max-time 90 "$url" -o "$TMP/src.txt" 2>"$TMP/curl_err.txt"; then
        lines=$(wc -l < "$TMP/src.txt")
        if [ "$lines" -lt "$MIN_LINES" ]; then
            echo "WARN: $name 仅 $lines 行（< $MIN_LINES），疑似异常，跳过" >&2
            echo "- ⚠️ $name：仅 $lines 行，已跳过" >> "$TMP/warnings.txt"
            failed=$((failed+1))
        else
            # 去注释(!/#)与空行，整行保留，语义零丢失
            grep -vE '^[[:space:]]*(#|!|$)' "$TMP/src.txt" >> "$TMP/all.txt" || true
            echo "OK: $name ($lines 行)"
            ok=$((ok+1))
        fi
    else
        echo "WARN: $name 拉取失败，跳过（保留其他源）" >&2
        echo "- ⚠️ $name：拉取失败，已跳过" >> "$TMP/warnings.txt"
        failed=$((failed+1))
    fi
done < "$SRC"

[ "$ok" -ge 1 ] || { echo "FATAL: 所有源均失败，拒绝生成空列表（防止全屋 DNS 裸奔）" >&2; exit 1; }

# 整行去重 + 排序
sort -u "$TMP/all.txt" > "$TMP/merged"
final=$(wc -l < "$TMP/merged")

# 防缩水：与旧结果比较
if [ -f "$OUT" ]; then
    prev=$(wc -l < "$OUT")
    floor=$(awk -v p="$prev" -v f="$SHRINK_FLOOR" 'BEGIN{printf "%d", p*f}')
    if [ "$final" -lt "$floor" ]; then
        echo "FATAL: 新结果 $final 行 < 上次 $prev 行的 90% ($floor)，疑似源异常，拒绝覆盖" >&2
        cat "$TMP/warnings.txt" >&2
        exit 2
    fi
fi

# 头部注释（AGH 忽略 # 行），标注来源与时间
{
    echo "# AdGuard DNS merged rules — 自动生成，请勿手改"
    echo "# 生成时间: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "# 来源: $ok 个订阅成功, $failed 个跳过; 整行去重(sort -u)，保 @@/\$important 语义"
    [ -s "$TMP/warnings.txt" ] && { echo "# 告警:"; sed 's/^- ⚠️ /#   /' "$TMP/warnings.txt"; }
    echo ""
    cat "$TMP/merged"
} > "$OUT.new"
mv "$OUT.new" "$OUT"

echo "DONE: $final 行 → $OUT"
# GitHub Step Summary（若在 Actions 中）
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### AdGuard DNS 合并结果"
        echo "- 最终规则：**$final** 行"
        echo "- 成功源：$ok / 跳过：$failed"
        [ -s "$TMP/warnings.txt" ] && { echo ""; cat "$TMP/warnings.txt"; }
    } >> "$GITHUB_STEP_SUMMARY"
fi
