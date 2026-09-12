#!/usr/bin/env bash
# フェーズ 1 の補助：git 履歴から「よく触られるファイル」を集計する。
#
# 臭いの影響度を判定する材料。触られないコードの臭いは実害が小さいので、
# 変更頻度の高いファイルにある臭いを優先する根拠になる。
#
# 使い方:
#   hotspots.sh [対象パス] [期間]
#     対象パス: 既定 .（例: src/parser）
#     期間:     既定 1.year（git log --since に渡す。例: 6.months, 2.years）

set -uo pipefail

TARGET="${1:-.}"
SINCE="${2:-1.year}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "git リポジトリではありません。変更頻度による影響度判定は使えません。" >&2
  echo "代わりに参照の広さ（grep での被参照数）を影響度の根拠にしてください。" >&2
  exit 1
}

echo "== 変更頻度（$SINCE 以内, 対象: $TARGET） =="
echo

echo "-- 変更回数の多いファイル（上位 20） --"
echo "   回数  ファイル"
git log --since="$SINCE" --name-only --pretty=format: -- "$TARGET" 2>/dev/null \
  | grep -vE '^$' \
  | grep -vE '(^|/)(node_modules|vendor|dist|build|target|\.venv|venv)/' \
  | grep -vE '\.(lock|min\.js|min\.css|svg|png|jpg|jpeg|gif|ico|pdf|zip)$' \
  | grep -vE '(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|poetry\.lock|Cargo\.lock|go\.sum)$' \
  | sort | uniq -c | sort -rn | head -20 \
  | awk '{ printf "  %5s  %s\n", $1, $2 }'
echo

echo "-- 変更した人数の多いファイル（上位 10） --"
echo "   人数  ファイル"
git log --since="$SINCE" --name-only --pretty=format:'@@%an' -- "$TARGET" 2>/dev/null \
  | awk '
      /^@@/ { author = substr($0, 3); next }
      /^$/  { next }
      /(^|\/)(node_modules|vendor|dist|build|target|\.venv|venv)\// { next }
      /\.(lock|min\.js|min\.css|svg|png|jpg|jpeg|gif|ico|pdf|zip)$/ { next }
      { key = $0 "\t" author; if (!(key in seen)) { seen[key] = 1; n[$0]++ } }
      END { for (f in n) printf "  %5d  %s\n", n[f], f }
    ' \
  | sort -rn | head -10
echo

echo "-- 直近で触られていない大きめのファイル（$SINCE 以内に変更なし, 上位 10） --"
echo "   行数  ファイル"
recent=$(git log --since="$SINCE" --name-only --pretty=format: -- "$TARGET" 2>/dev/null | grep -vE '^$' | sort -u)
git ls-files -- "$TARGET" 2>/dev/null \
  | grep -vE '(^|/)(node_modules|vendor|dist|build|target|\.venv|venv)/' \
  | grep -vE '\.(lock|min\.js|min\.css|svg|png|jpg|jpeg|gif|ico|pdf|zip|md|txt|json|yaml|yml)$' \
  | while IFS= read -r f; do
      grep -Fxq "$f" <<< "$recent" && continue
      [[ -f "$f" ]] || continue
      printf '%s\t%s\n' "$(wc -l < "$f" | tr -d ' ')" "$f"
    done \
  | sort -rn | head -10 | awk -F'\t' '{ printf "  %5s  %s\n", $1, $2 }'
echo

cat <<'EOF'
-- 読み方 --
・変更回数が多いファイルの臭いは、繰り返しコストを生んでいる。影響度 High の根拠になる。
・変更した人数が多いファイルは、複数人が触るため名前の不明瞭さや責務の混在が特に高くつく。
・触られていない大きなファイルは、臭いが濃くても実害が小さい。影響度は Low 寄りに見積もる。
  ただし「これから機能追加する予定の場所」なら話は別。ユーザーの予定を確認する。

影響度のもうひとつの軸は「参照の広さ」。対象の関数・クラス名を grep して被参照数を数える。
広く参照されているものは、変更頻度が低くても影響度が高い。
EOF
