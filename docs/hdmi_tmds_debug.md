# HDMI カラーバー出力: 設計と開発記録

## 1. アーキテクチャ概要

### ターゲット
- **ボード**: Tang Console 138K (GW5AST-LV138FPG676)
- **解像度**: 640×480@60Hz (VGA タイミング)
- **インターフェース**: HDMI/DVI モード

### 信号パス
```
50MHz → PLL → pixel_clk (≈25.2MHz) + serial_clk (≈126MHz)
                ↓
         Video Timing → Color Bar → TMDS Encoder (×3ch) → OSER10 → TLVDS_OBUF → HDMI
```

### ファイル構成

| ファイル | 説明 |
|---------|------|
| `src/hdmi/hdmi_colorbar_top.sv` | **メインRTL** (手書き SV) — TMDS エンコーダ + トップモジュール |
| `src/hdmi/hdmi_colorbar.cm` | Cm ソース (参考用、SV バックエンドのバグにより直接使用不可) |
| `src/hdmi/gowin_hdmi.tcl` | Gowin EDA ビルドスクリプト |
| `src/hdmi/tang_console_138k_hdmi.cst` | ピン制約 (FPG676 パッケージ, 実機用) |
| `src/hdmi/tang_console_138k_hdmi_pg484.cst` | ピン制約 (PG484 フォールバック) |
| `src/hdmi/postprocess_sv.sh` | Cm 生成 SV 用ポスト処理 (現在は不使用) |

---

## 2. TMDS エンコーダ設計

`hdmi_colorbar_top.sv` に含まれる `tmds_encoder` モジュールの設計:

### パイプライン構造 (合計 2 サイクル)

| ステージ | 処理 | 実装方式 |
|---------|------|---------|
| Stage 1 | 入力レジスタ | `always @(posedge clk)` — din, ctrl, de を 1 サイクル遅延 |
| 組み合わせ | 遷移最小化 | `wire` — popcount → XOR/XNOR 選択 → q_m[8:0] 構築 |
| Stage 2 | DC バランス | `always @(posedge clk)` — 累積ディスパリティ追跡 + 10-bit 出力 |

### DVI 1.0 コントロールトークン

| {VSYNC, HSYNC} | トークン (10-bit) | 10 進数 |
|----------------|------------------|--------|
| {0, 0} | `1101010100` | 852 |
| {0, 1} | `0010101011` | 171 |
| {1, 0} | `0101010100` | 340 |
| {1, 1} | `1010101011` | 683 |

### DC バランスカウンタ更新式

| ケース | 条件 | cnt 更新 |
|--------|------|----------|
| 1 (q_m[8]=1) | cnt==0 or N1==4 | cnt + 2N1 - 8 |
| 1 (q_m[8]=0) | cnt==0 or N1==4 | cnt + 8 - 2N1 |
| 2 (反転) | (cnt>0 & N1>4) or (cnt<0 & N1<4) | cnt + 2·q_m[8] + 8 - 2N1 |
| 3 (そのまま) | else | cnt + 2·q_m[8] + 2N1 - 10 |

---

## 3. ピン配置 (PG484 フォールバック)

| 信号 | ピン (P, N) | ソース |
|------|-------------|--------|
| System Clock | V22 | Sipeed 公式 |
| TMDS D0 (Blue) | J14, H14 | Sipeed 公式 |
| TMDS D1 (Green) | J15, H15 | Sipeed 公式 |
| TMDS D2 (Red) | K17, J17 | Sipeed 公式 |
| TMDS Clock | G15, G16 | Sipeed 公式 |
| LED | U12 | — |

**参照**: [Sipeed TangMega-138K-example hdmi.cst](https://github.com/sipeed/TangMega-138K-example/blob/main/hdmi_colorbar/eda_proj/src/hdmi.cst)

---

## 4. ビルドコマンド

```bash
# 手書き SV → Gowin 合成 → ビットストリーム
make hdmi-gowin

# FPGA に書き込み
make hdmi-flash

# 一括実行 (Cm→SV + 合成 + 書き込み)
make hdmi-apply
```

---

## 5. 発見されたバグと修正履歴

### Cm SV バックエンド (codegen.cpp)

| バグ | 影響 | 修正 |
|------|------|------|
| **二項演算の括弧不足** | `(a & b) == c` が `a & (b == c)` に展開 → TMDS 条件判定が常に誤動作 | 全二項演算を `()` で囲む |
| **混合ビット幅未キャスト** | `int + ushort` で幅不一致 → Verilator WIDTHEXPAND 警告 | 狭い方に `N'(var)` を挿入 |
| **三項演算子の条件括弧落ち** | `if/else` → `? :` 変換時に条件の括弧が消失 | 条件式に括弧を保持 |

### Cm SV バックエンド — async func 構造的制約

| 制約 | 影響 | 現状 |
|------|------|------|
| **複数 if ブロックのネスト化** | 同一 `async func` 内の独立した `if` ブロックが、先行ブロックの else チェーン内にネストされる | **未修正** — 手書き SV で回避 |
| **非ブロッキング代入の中間値参照** | `<=` で代入した中間値を同サイクルで参照 → 1 サイクル遅延 | **未修正** — 組み合わせ/パイプライン分離が必要 |

> **注意**: 上記の構造的制約が修正されるまで、複雑な RTL (TMDS エンコーダ等) は手書き SV を使用してください。

---

## 6. PLL パラメータ

| パラメータ | 値 | 説明 |
|-----------|-----|------|
| FCLKIN | 50 | 入力クロック (MHz) |
| IDIV_SEL | 2 | 入力分周 (IDIV = IDIV_SEL + 1 = 3) |
| FBDIV_SEL | 1 | フィードバック分周 |
| MDIV_SEL | 30 | VCO 乗算 |
| MDIV_FRAC_SEL | 2 | 小数部 |
| ODIV0_SEL | 30 | CLKOUT0 分周 → pixel_clk |
| ODIV1_SEL | 6 | CLKOUT1 分周 → serial_clk |

**比率**: ODIV0/ODIV1 = 30/6 = 5 → serial_clk = 5 × pixel_clk (DDR OSER10 用)
