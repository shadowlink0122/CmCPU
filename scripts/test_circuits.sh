#!/bin/bash
# ============================================================
# 全回路のシミュレーションテスト（自動発見）
# ============================================================
# 以下を自動的に発見して -D SIM でSV化し、#[sv::testbench] から
# 生成されたテストベンチを iverilog + vvp で実行する:
#   - テストラッパー: src/**/*_test.cm（対象モジュールと同じ階層に配置）
#   - テストベンチ内蔵の回路: #[sv::testbench] を含む src/**/*.cm
# ============================================================
set -u
cd "$(dirname "$0")/.."

CM=Cm/cm
BUILD=build/test
mkdir -p "$BUILD"

# テキスト系はフォントROM（$readmemh）を実行ディレクトリに要する
cp src/hdmi/text/font_rom.hex "$BUILD/" 2>/dev/null || true

# テスト対象の自動発見（*_test.cm + #[sv::testbench] 内蔵ファイル）
TARGETS=$( { find src -name "*_test.cm"; grep -rl '#\[sv::testbench\]' src --include="*.cm"; } | sort -u )

PASSED=0
FAILED=0

for src in $TARGETS; do
    name=$(echo "$src" | sed 's|^src/||; s|/|_|g; s|\.cm$||')

    if ! "$CM" compile --target=sv -D SIM "$src" -o "$BUILD/$name.sv" -q \
            > "$BUILD/$name.compile.log" 2>&1; then
        echo "[FAIL] $name - コンパイルエラー（$BUILD/$name.compile.log）"
        FAILED=$((FAILED + 1))
        continue
    fi

    if ! iverilog -g2012 -o "$BUILD/${name}_sim" \
            "$BUILD/$name.sv" "$BUILD/${name}_tb.sv" \
            > "$BUILD/$name.iverilog.log" 2>&1; then
        echo "[FAIL] $name - iverilogエラー（$BUILD/$name.iverilog.log）"
        FAILED=$((FAILED + 1))
        continue
    fi

    if (cd "$BUILD" && vvp "${name}_sim" > "$name.sim.log" 2>&1); then
        pass_count=$(grep -c "^PASS:" "$BUILD/$name.sim.log" || true)
        echo "[PASS] $name (${pass_count} assertions)"
        PASSED=$((PASSED + 1))
    else
        echo "[FAIL] $name - シミュレーション失敗:"
        grep -E "^(PASS|FAIL):" "$BUILD/$name.sim.log" | tail -3 | sed 's/^/    /'
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "結果: PASS=$PASSED FAIL=$FAILED"
[ "$FAILED" -eq 0 ]
