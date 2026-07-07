#!/bin/bash
# ============================================================
# 全回路のシミュレーションテスト
# ============================================================
# 各回路を -D SIM でSV化し、#[sv::testbench] 関数から生成された
# テストベンチを iverilog + vvp で実行して検証する
# ============================================================
set -u
cd "$(dirname "$0")/.."

CM=Cm/cm
BUILD=build/test
mkdir -p "$BUILD"

CIRCUITS=(
    "blink:src/blink/blink.cm"
    "pwm_breath:src/pwm/pwm_breath.cm"
    "button_counter:src/button/button_counter.cm"
    "uart_hello:src/uart/uart_hello.cm"
    "uart_button:src/uart/uart_button.cm"
    "hdmi_timing:src/hdmi/timing_test.cm"
)

PASSED=0
FAILED=0

for entry in "${CIRCUITS[@]}"; do
    name="${entry%%:*}"
    src="${entry#*:}"

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
