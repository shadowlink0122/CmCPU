#!/bin/bash
# ============================================================
# 全回路のシミュレーションテスト（自動発見）
# ============================================================
# 以下を自動的に発見し、`cm test` で実行する:
#   - テストラッパー: src/**/*_test.cm（対象モジュールと同じ階層に配置）
#   - #[test] 関数を含む回路: src/**/*.cm
#
# `cm test` は //! platform: sv を検出してSV+テストベンチを生成し、
# iverilog + vvp でシミュレーションを実行する（TEST が自動定義される）。
# 生成物・ログは .tmp/test/ に出力される。
# ============================================================
set -u
cd "$(dirname "$0")/.."

CM=Cm/cm
OUT=.tmp/test
mkdir -p "$OUT"

# テキスト系はフォントROM（$readmemh）を実行ディレクトリに要する
cp src/hdmi/text/font_rom.hex "$OUT/" 2>/dev/null || true

# テスト対象の自動発見（*_test.cm + #[test] を含むファイル）
TARGETS=$( { find src -name "*_test.cm"; grep -rl '#\[test\]' src --include="*.cm"; } | sort -u )

PASSED=0
FAILED=0

for src in $TARGETS; do
    name=$(echo "$src" | sed 's|^src/||; s|/|_|g; s|\.cm$||')
    log="$OUT/$name.log"

    if "$CM" test "$src" > "$log" 2>&1; then
        pass_count=$(grep -c "^PASS:" "$log" || true)
        echo "[PASS] $name (${pass_count} assertions)"
        PASSED=$((PASSED + 1))
    else
        echo "[FAIL] $name:"
        grep -E "^(PASS|FAIL|エラー|assertion)" "$log" | tail -5 | sed 's/^/    /'
        echo "    （詳細: $log）"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "結果: PASS=$PASSED FAIL=$FAILED"
[ "$FAILED" -eq 0 ]
