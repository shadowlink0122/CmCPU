#!/bin/bash
# ============================================================
# HDMI SV ポスト処理スクリプト
# ============================================================
# Cm が生成した SV に対して、Gowin プリミティブの
# モジュール名とポート接続を修正する
# ============================================================

set -euo pipefail

SV_FILE="$1"

if [ ! -f "$SV_FILE" ]; then
    echo "ERROR: ファイルが見つかりません: $SV_FILE"
    exit 1
fi

# --- モジュール名の修正 ---
# OSER10_R/G/B/CK → OSER10
sed -i '' 's/OSER10_R/OSER10/g' "$SV_FILE"
sed -i '' 's/OSER10_G/OSER10/g' "$SV_FILE"
sed -i '' 's/OSER10_B/OSER10/g' "$SV_FILE"
sed -i '' 's/OSER10_CK/OSER10/g' "$SV_FILE"

# TLVDS_D2/D1/D0/CK → TLVDS_OBUF
sed -i '' 's/TLVDS_D2 tlvds_d2/TLVDS_OBUF tlvds_d2/g' "$SV_FILE"
sed -i '' 's/TLVDS_D1 tlvds_d1/TLVDS_OBUF tlvds_d1/g' "$SV_FILE"
sed -i '' 's/TLVDS_D0 tlvds_d0/TLVDS_OBUF tlvds_d0/g' "$SV_FILE"
sed -i '' 's/TLVDS_CK tlvds_ck/TLVDS_OBUF tlvds_ck/g' "$SV_FILE"

# --- OSER10 oser_r: D0-D9 をビットインデックスに修正 ---
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

echo "✅ HDMI SV ポスト処理完了: $SV_FILE"
