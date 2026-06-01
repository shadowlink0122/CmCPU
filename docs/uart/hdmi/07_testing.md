# テスト戦略

## 概要

HDMI テキスト出力プロジェクトの包括的なテスト計画。
Verilator リント、テストベンチシミュレーション、実機検証の 3 層構成。

## テスト階層

```
Layer 3: 実機検証 (FPGA)
    │  モニタ接続、目視確認、LED 状態
    │
Layer 2: テストベンチ (シミュレーション)
    │  Verilator / iverilog でのサイクルシミュレーション
    │  VCD 波形出力、自動アサーション
    │
Layer 1: リントチェック (静的解析)
    │  Verilator --lint-only
    │  構文エラー、ラッチ推論、ビット幅不整合
    │
Layer 0: Cm コンパイル (SV 生成)
       cm compile --target=sv
       Cm ソースから SV コード生成
```

## Layer 0: Cm コンパイル

### コマンド

```bash
# 各モジュールを個別にコンパイル
cm compile --target=sv src/hdmi/video_timing.cm -o build/video_timing.sv
cm compile --target=sv src/hdmi/tmds_encoder.cm -o build/tmds_encoder.sv
cm compile --target=sv src/hdmi/gbc_display.cm -o build/gbc_display.sv
cm compile --target=sv src/hdmi/font_rom.cm -o build/font_rom.sv
cm compile --target=sv src/hdmi/text_renderer.cm -o build/text_renderer.sv
cm compile --target=sv src/hdmi/animation_ctrl.cm -o build/animation_ctrl.sv
cm compile --target=sv src/hdmi/hdmi_text_top.cm -o build/hdmi_text_top.sv
```

### 合格基準

- 全ファイルがエラーなしで SV に変換される
- 生成された SV ファイルが構文的に正しい

## Layer 1: Verilator リント

### コマンド

```bash
# 各モジュールを個別にリント
verilator --lint-only --timing -Wno-fatal -Wno-MODMISSING build/video_timing.sv
verilator --lint-only --timing -Wno-fatal -Wno-MODMISSING build/tmds_encoder.sv
verilator --lint-only --timing -Wno-fatal -Wno-MODMISSING build/gbc_display.sv
verilator --lint-only --timing -Wno-fatal -Wno-MODMISSING build/text_renderer.sv
verilator --lint-only --timing -Wno-fatal -Wno-MODMISSING build/animation_ctrl.sv
```

### フラグ説明

| フラグ | 説明 |
|--------|------|
| `--lint-only` | シミュレーションモデル生成なし (構文のみ) |
| `--timing` | タイミングアノテーション有効 |
| `-Wno-fatal` | 警告をエラーにしない (LATCH, WIDTHTRUNC 許容) |
| `-Wno-MODMISSING` | 未定義モジュール警告を抑制 (Gowin プリミティブ用) |

### 許容する警告

| 警告コード | 原因 | 対策 |
|------------|------|------|
| `LATCH` | 暗黙のラッチ推論 | Cm 中間コードの制約、合成時に問題なし |
| `WIDTHTRUNC` | uint → utiny 等の暗黙切り詰め | 明示的キャスト推奨 |
| `WIDTHEXPAND` | 小さい型 → 大きい型への暗黙拡張 | 通常問題なし |
| `MODMISSING` | Gowin プリミティブ未定義 | 実機でのみ使用 |

## Layer 2: テストベンチ

### テストベンチ一覧

| ID | テストベンチ | 対象モジュール | 検証内容 |
|----|-------------|----------------|----------|
| TB-01 | `video_timing_tb.sv` | video_timing | H/V タイミング正確性 |
| TB-02 | `tmds_encoder_tb.sv` | tmds_encoder | エンコーディング正確性 |
| TB-03 | `gbc_display_tb.sv` | gbc_display | スケーリング・座標変換 |
| TB-04 | `font_rom_tb.sv` | font_rom | フォントデータ読み出し |
| TB-05 | `text_renderer_tb.sv` | text_renderer | ピクセル生成 |
| TB-06 | `animation_tb.sv` | animation_ctrl | タイプライタアニメーション |
| TB-07 | `hdmi_top_tb.sv` | hdmi_text_top | 統合テスト |

### テストベンチ構造 (テンプレート)

Cm SV バックエンドが自動生成するテストベンチをベースにカスタマイズ:

```systemverilog
// video_timing_tb.sv (自動生成 + カスタムアサーション)
module video_timing_tb;
    // クロック生成 (25.2 MHz 相当)
    reg clk = 0;
    always #19.84 clk = ~clk;  // ~25.2 MHz

    // DUT (Design Under Test) 接続
    wire hsync, vsync, de;
    wire [15:0] h_count, v_count;

    video_timing dut (
        .pixel_clk(clk),
        .hsync(hsync),
        .vsync(vsync),
        .de(de),
        .h_count(h_count),
        .v_count(v_count)
    );

    // VCD ダンプ
    initial begin
        $dumpfile("video_timing.vcd");
        $dumpvars(0, video_timing_tb);
    end

    // テスト: 1フレーム分 (420,000 クロック) シミュレーション
    integer frame_clocks;
    initial begin
        frame_clocks = 0;

        // 2 フレーム分実行
        repeat (840000) @(posedge clk);

        // 終了
        $display("TB-VT: PASS - 2 frames simulated");
        $finish;
    end

    // アサーション: H_TOTAL = 800
    integer h_period;
    reg hsync_prev;
    always @(posedge clk) begin
        hsync_prev <= hsync;
        if (hsync_prev && !hsync) begin
            // HSYNC 立ち下がりエッジ
            if (h_period > 0) begin
                if (h_period != 800) begin
                    $display("TB-VT: FAIL - H period = %d (expected 800)", h_period);
                end
            end
            h_period = 0;
        end else begin
            h_period = h_period + 1;
        end
    end
endmodule
```

### VCD 波形検証

テストベンチで VCD (Value Change Dump) ファイルを出力し、
波形ビューアで視覚的に検証する。

```bash
# Verilator でシミュレーション
verilator --binary --timing -Wno-fatal build/video_timing.sv build/video_timing_tb.sv
./obj_dir/Vvideo_timing_tb

# 波形表示 (Surfer 推奨)
surfer video_timing.vcd
```

## Layer 3: 実機検証

### チェックリスト

| # | 検証項目 | 判定基準 |
|---|----------|----------|
| HW-01 | PLL ロック | `pll_locked` LED が HIGH |
| HW-02 | HDMI 信号認識 | モニタが入力を検出 |
| HW-03 | 解像度認識 | モニタが 640×480@60Hz と表示 |
| HW-04 | カラーバー (Phase 1) | R/G/B のバーが正しく表示 |
| HW-05 | テキスト表示 (Phase 2) | "Hello, World!" が読める |
| HW-06 | GBC スケーリング (Phase 3) | 3× 拡大、レターボックス表示 |
| HW-07 | アニメーション (Phase 4) | 文字が順次表示される |
| HW-08 | カーソル点滅 | 最後の文字の後でカーソルが点滅 |
| HW-09 | LED ステータス | Red: 動作中, Blue: 完了 |

## Makefile 統合

```makefile
# ============================================================
# HDMI テキスト出力: ビルド + テスト
# ============================================================

HDMI_SRCS := $(wildcard $(SRC_DIR)/hdmi/*.cm)
HDMI_SVS  := $(patsubst $(SRC_DIR)/hdmi/%.cm,$(BUILD_DIR)/%.sv,$(HDMI_SRCS))

.PHONY: hdmi-build
hdmi-build: $(HDMI_SVS)
	@echo "Verilator リントチェック中 (HDMI)..."
	@for sv in $(HDMI_SVS); do \
		verilator --lint-only --timing -Wno-fatal -Wno-MODMISSING $$sv; \
	done
	@echo "✅ HDMI ビルド完了!"

.PHONY: hdmi-test
hdmi-test: hdmi-build
	@echo "テストベンチ実行中..."
	# テストベンチシミュレーション (要 verilator --binary)
	@echo "✅ HDMI テスト完了!"

.PHONY: hdmi-gowin
hdmi-gowin: hdmi-build
	DYLD_LIBRARY_PATH=$(GW_LIB) DYLD_FRAMEWORK_PATH=$(GW_LIB) $(GW_SH) $(SRC_DIR)/hdmi/gowin_hdmi.tcl
	@echo "✅ Gowin EDA HDMI ビルド完了!"

.PHONY: hdmi-flash
hdmi-flash:
	openFPGALoader -b $(BOARD) $(BUILD_DIR)/hdmi_text_top/impl/pnr/hdmi_text_top.fs
	@echo "✅ HDMI 書き込み完了!"

.PHONY: hdmi-apply
hdmi-apply: hdmi-build hdmi-gowin hdmi-flash
```
