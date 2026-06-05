#!/bin/bash
# ============================================================
# HDMI SV ポスト処理スクリプト
# ============================================================
# Cm が生成した SV に対して、Gowin プリミティブの
# モジュール名・ポート接続・ビット幅リテラルを修正する
# ============================================================

set -euo pipefail

SV_FILE="$1"

if [ ! -f "$SV_FILE" ]; then
    echo "ERROR: ファイルが見つかりません: $SV_FILE"
    exit 1
fi

# === 修正 1: 未使用ポート (clk, rst) を削除 ===
# Cm SV バックエンドが自動生成する clk/rst ポートはこの回路で不要
# ポート宣言行を削除し、末尾カンマも修正
sed -i '' '/^    input logic clk,$/d' "$SV_FILE"
sed -i '' '/^    input logic rst,$/d' "$SV_FILE"

# === 修正 2: モジュール名の修正 ===
# OSER10_R/G/B/CK → OSER10 (sv::module_name が効かない場合のフォールバック)
sed -i '' 's/OSER10_R /OSER10 /g' "$SV_FILE"
sed -i '' 's/OSER10_G /OSER10 /g' "$SV_FILE"
sed -i '' 's/OSER10_B /OSER10 /g' "$SV_FILE"
sed -i '' 's/OSER10_CK /OSER10 /g' "$SV_FILE"

# TLVDS_D2/D1/D0/CK → TLVDS_OBUF
sed -i '' 's/TLVDS_D2 tlvds_d2/TLVDS_OBUF tlvds_d2/g' "$SV_FILE"
sed -i '' 's/TLVDS_D1 tlvds_d1/TLVDS_OBUF tlvds_d1/g' "$SV_FILE"
sed -i '' 's/TLVDS_D0 tlvds_d0/TLVDS_OBUF tlvds_d0/g' "$SV_FILE"
sed -i '' 's/TLVDS_CK tlvds_ck/TLVDS_OBUF tlvds_ck/g' "$SV_FILE"

# === 修正 3: OSER10 D0-D9 ビットインデックス接続 ===
# oser_r: tmds_r のビット
sed -i '' '/oser_r (/,/);/{
    s/\.D0(D0)/.D0(tmds_r[0])/
    s/\.D1(D1)/.D1(tmds_r[1])/
    s/\.D2(D2)/.D2(tmds_r[2])/
    s/\.D3(D3)/.D3(tmds_r[3])/
    s/\.D4(D4)/.D4(tmds_r[4])/
    s/\.D5(D5)/.D5(tmds_r[5])/
    s/\.D6(D6)/.D6(tmds_r[6])/
    s/\.D7(D7)/.D7(tmds_r[7])/
    s/\.D8(D8)/.D8(tmds_r[8])/
    s/\.D9(D9)/.D9(tmds_r[9])/
}' "$SV_FILE"

# oser_g: tmds_g のビット
sed -i '' '/oser_g (/,/);/{
    s/\.D0(D0)/.D0(tmds_g[0])/
    s/\.D1(D1)/.D1(tmds_g[1])/
    s/\.D2(D2)/.D2(tmds_g[2])/
    s/\.D3(D3)/.D3(tmds_g[3])/
    s/\.D4(D4)/.D4(tmds_g[4])/
    s/\.D5(D5)/.D5(tmds_g[5])/
    s/\.D6(D6)/.D6(tmds_g[6])/
    s/\.D7(D7)/.D7(tmds_g[7])/
    s/\.D8(D8)/.D8(tmds_g[8])/
    s/\.D9(D9)/.D9(tmds_g[9])/
}' "$SV_FILE"

# oser_b: tmds_b のビット
sed -i '' '/oser_b (/,/);/{
    s/\.D0(D0)/.D0(tmds_b[0])/
    s/\.D1(D1)/.D1(tmds_b[1])/
    s/\.D2(D2)/.D2(tmds_b[2])/
    s/\.D3(D3)/.D3(tmds_b[3])/
    s/\.D4(D4)/.D4(tmds_b[4])/
    s/\.D5(D5)/.D5(tmds_b[5])/
    s/\.D6(D6)/.D6(tmds_b[6])/
    s/\.D7(D7)/.D7(tmds_b[7])/
    s/\.D8(D8)/.D8(tmds_b[8])/
    s/\.D9(D9)/.D9(tmds_b[9])/
}' "$SV_FILE"

# === 修正 4: PLL/OSER10 ポートのビット幅リテラル修正 ===
# Gowin プリミティブの 1bit ポートに 32bit リテラル (0/1) を接続すると
# EX3670 警告が発生するため、1'b0 / 1'b1 に修正する
#
# パターン: .PORT_NAME(0) → .PORT_NAME(1'b0)
#           .PORT_NAME(1) → .PORT_NAME(1'b1)
# ただし .D0(0) 等のデータポートや .FCLKIN(50) 等のパラメータは除外

# PLL インスタンスのブール入力ポート修正
sed -i '' '/pll_inst (/,/);/{
    s/\.CLKFB(0)/.CLKFB(1'\''b0)/
    s/\.RESET(0)/.RESET(1'\''b0)/
    s/\.PLLPWD(0)/.PLLPWD(1'\''b0)/
    s/\.RESET_I(0)/.RESET_I(1'\''b0)/
    s/\.RESET_O(0)/.RESET_O(1'\''b0)/
    s/\.ENCLK0(1)/.ENCLK0(1'\''b1)/
    s/\.ENCLK1(1)/.ENCLK1(1'\''b1)/
}' "$SV_FILE"

# OSER10 インスタンスの RESET ポート修正
sed -i '' '/oser_r (/,/);/{
    s/\.RESET(0)/.RESET(1'\''b0)/
}' "$SV_FILE"
sed -i '' '/oser_g (/,/);/{
    s/\.RESET(0)/.RESET(1'\''b0)/
}' "$SV_FILE"
sed -i '' '/oser_b (/,/);/{
    s/\.RESET(0)/.RESET(1'\''b0)/
}' "$SV_FILE"
sed -i '' '/oser_ck (/,/);/{
    s/\.RESET(0)/.RESET(1'\''b0)/
}' "$SV_FILE"

# OSER10 oser_ck: クロックパターン D0-D9 のビット幅修正
sed -i '' '/oser_ck (/,/);/{
    s/\.D0(1)/.D0(1'\''b1)/
    s/\.D1(1)/.D1(1'\''b1)/
    s/\.D2(1)/.D2(1'\''b1)/
    s/\.D3(1)/.D3(1'\''b1)/
    s/\.D4(1)/.D4(1'\''b1)/
    s/\.D5(0)/.D5(1'\''b0)/
    s/\.D6(0)/.D6(1'\''b0)/
    s/\.D7(0)/.D7(1'\''b0)/
    s/\.D8(0)/.D8(1'\''b0)/
    s/\.D9(0)/.D9(1'\''b0)/
}' "$SV_FILE"

# === 修正 5: 差動出力ポート (_n) の宣言を削除 ===
# TLVDS_OBUF が差動出力を内部で処理するため、
# トップモジュールでは _p ポートのみを宣言する
# _n ポートは TLVDS_OBUF の OB 出力として自動的にドライブされる
# (CST で P,N を1行で指定する形式と組み合わせて動作)

# === 修正 6: always_ff → always に変換 ===
# Gowin EDA は always_ff ブロック内でブロッキング代入（中間計算変数）と
# 非ブロッキング代入（レジスタ出力）を混合すると合成エラーを起こす。
# 汎用の always ブロックに変換することで回避する。
sed -i '' 's/always_ff @/always @/g' "$SV_FILE"

# === 修正 7: ローカル変数初期化行の削除 ===
# Cm が関数ローカル変数の初期値として生成する「var = 32'd0;」行を削除。
# これらは always ブロック先頭に毎クロック実行されるが、
# 直後のロジックで必ず上書きされるため不要であり、
# Gowin EDA の合成を阻害する可能性がある。
# パターン: 行頭空白 + 変数名 + " = 32'd0;" のみの行を削除
sed -i '' "/^[[:space:]]*[a-z_][a-z_0-9]* = 32'd0;$/d" "$SV_FILE"

echo "✅ HDMI SV ポスト処理完了: $SV_FILE"
