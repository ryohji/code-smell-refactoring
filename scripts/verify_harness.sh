#!/usr/bin/env bash
# フェーズ 0 の補助：テスト実行手段を検出し、現状のグリーン／レッドを報告する。
#
# 使い方:
#   verify_harness.sh [対象ディレクトリ]        # 検出してコマンド候補を表示
#   verify_harness.sh [対象ディレクトリ] --run  # 検出したコマンドを実行する
#
# 出力は「候補コマンドの一覧」と「検出したテストファイル数」。
# 実際にどのコマンドを使うかは呼び出し側が決める。ここでは候補を並べるだけ。

set -uo pipefail

DIR="${1:-.}"
RUN=0
[[ "${2:-}" == "--run" ]] && RUN=1
cd "$DIR" || { echo "ディレクトリがありません: $DIR" >&2; exit 1; }

echo "== 対象: $(pwd) =="
echo

# --- ビルド／テスト設定の検出 ---
echo "-- 検出した設定ファイル --"
found_any=0
for f in pytest.ini pyproject.toml setup.cfg tox.ini pom.xml build.gradle build.gradle.kts \
         CMakeLists.txt Makefile package.json Cargo.toml go.mod *.csproj *.sln composer.json; do
  for m in $f; do
    [[ -e "$m" ]] && { echo "  $m"; found_any=1; }
  done
done
[[ $found_any -eq 0 ]] && echo "  （なし）"
echo

# --- テストファイルの検出 ---
echo "-- テストファイルらしきもの（件数） --"
count_pattern() {
  local label="$1"; shift
  local n
  n=$(find . -type f \( "$@" \) \
        -not -path './.git/*' -not -path './node_modules/*' \
        -not -path './target/*' -not -path './build/*' \
        -not -path './.venv/*' -not -path './venv/*' 2>/dev/null | wc -l | tr -d ' ')
  [[ "$n" -gt 0 ]] && echo "  $label: $n"
}
count_pattern "Python (test_*.py / *_test.py)" -name 'test_*.py' -o -name '*_test.py'
count_pattern "Java (*Test.java / Test*.java)" -name '*Test.java' -o -name 'Test*.java'
count_pattern "C/C++ (*_test.cc|cpp|c / test_*.c*)" -name '*_test.cc' -o -name '*_test.cpp' -o -name '*_test.c' -o -name 'test_*.cpp' -o -name 'test_*.cc'
count_pattern "JS/TS (*.test.* / *.spec.*)" -name '*.test.js' -o -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.spec.js' -o -name '*.spec.ts'
count_pattern "Go (*_test.go)" -name '*_test.go'
count_pattern "Rust (tests/*.rs)" -path './tests/*.rs'
count_pattern "C# (*Tests.cs / *Test.cs)" -name '*Tests.cs' -o -name '*Test.cs'
echo

# --- コマンド候補 ---
echo "-- テスト実行コマンドの候補（上から順に確度が高い） --"
CANDIDATES=()
add() { CANDIDATES+=("$1"); }

if [[ -f package.json ]]; then
  if grep -qE '"test"[[:space:]]*:' package.json 2>/dev/null; then
    add "npm test"
  fi
  grep -qE '"(vitest|jest)"' package.json 2>/dev/null && add "npx vitest run  /  npx jest"
fi
[[ -f pytest.ini || -f pyproject.toml || -f setup.cfg || -f tox.ini ]] && add "python -m pytest -q"
find . -maxdepth 3 -name 'test_*.py' -not -path './.venv/*' 2>/dev/null | grep -q . && \
  { add "python -m pytest -q"; add "python -m unittest discover"; }
[[ -f pom.xml ]] && add "mvn -q test"
[[ -f build.gradle || -f build.gradle.kts ]] && add "./gradlew test"
[[ -f Cargo.toml ]] && add "cargo test"
[[ -f go.mod ]] && add "go test ./..."
[[ -f CMakeLists.txt ]] && add "ctest --output-on-failure   (要: cmake でのビルド後)"
[[ -f Makefile ]] && grep -qE '^(test|check):' Makefile 2>/dev/null && add "make test  /  make check"
ls ./*.sln ./*.csproj >/dev/null 2>&1 && add "dotnet test"

# 重複を除いて表示
if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  echo "  （検出できませんでした。CI 設定 .github/workflows/ や README を確認してください）"
else
  printf '%s\n' "${CANDIDATES[@]}" | awk '!seen[$0]++ { print "  " $0 }'
fi
echo

# --- CI 設定からの裏取り ---
if [[ -d .github/workflows ]]; then
  echo "-- CI 設定に現れるテストコマンド（最も信頼できる情報源） --"
  grep -rhoE '(npm|yarn|pnpm) (run )?test[a-z:-]*|python -m (pytest|unittest)[^"]*|pytest[^"]*|mvn[^"]*test|gradlew[^"]*test|cargo test[^"]*|go test[^"]*|ctest[^"]*|dotnet test[^"]*|make (test|check)' \
    .github/workflows/ 2>/dev/null | sed 's/^[[:space:]]*//' | sort -u | head -10 | sed 's/^/  /'
  echo
fi

# --- 実行 ---
if [[ $RUN -eq 1 && ${#CANDIDATES[@]} -gt 0 ]]; then
  CMD="${CANDIDATES[0]%%  /*}"
  CMD="${CMD%%   (*}"
  echo "-- 実行: $CMD --"
  eval "$CMD"
  status=$?
  echo
  if [[ $status -eq 0 ]]; then
    echo "結果: 終了コード 0（グリーン）"
    echo "注意: テストが 1 件も収集されていないのに 0 が返る場合があります。"
    echo "      上の出力で実行件数を必ず確認してください。0 件なら保護は存在しません。"
  else
    echo "結果: 終了コード $status（レッド）"
    echo "注意: 着手前からレッドの状態ではリファクタリングを始められません。"
    echo "      自分の変更が原因かを判定できなくなるため、まず既存の失敗をユーザーに報告してください。"
  fi
  exit $status
fi

cat <<'EOF'
-- 次にやること --
1. 上の候補から実行コマンドを決め、そのまま実行して現状を確認する。
   すでにレッドなら着手せず、ユーザーに報告する（自分の変更が原因かを判別できなくなる）。
2. テストが 0 件だった場合、フレームワークの疎通を確認する。
   a. 空のテストを 1 つ作って実行し、OK を得る
   b. 必ず失敗する assertion を入れて、レッドが正しく報告されることを確認する
   c. 確認できたら失敗テストを削除する
   b を省くと「テストが 1 件も収集されていないのにグリーン」を見誤ります。
3. 決めたコマンドと現状の件数を REFACTORING_PLAN.md の「前提」に記録する。
EOF
