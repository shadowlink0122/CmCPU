# Feature: SV バックエンドのマルチモジュール / import 対応

## 概要

Cm SV バックエンドにおける複数ファイルからの SystemVerilog モジュール生成と、
トップモジュールでのサブモジュールインスタンス化対応。

## 現状

### 確認済みの状況

- 各 `.cm` ファイルが独立した SV モジュールとして生成される
- `extern struct` でベンダープリミティブ (OSC, rPLL) をインスタンス化可能
- Cm の `import` プリプロセッサはテキスト展開方式 (SV バックエンドでの挙動未確認)

### 現在の制約

1. **単一ファイル**: 既存の `uart_hello.cm` / `uart_button.cm` は
   全ロジックが 1 ファイルに含まれている
2. **extern struct**: ベンダープリミティブ専用で、ユーザー定義モジュールの
   インスタンス化に使用できるか不明
3. **import**: テキスト展開のため、複数 `always_ff` ブロックの名前衝突が
   発生する可能性がある

## 必要性

HDMI プロジェクトでは 8 以上のサブモジュールが必要:

```
hdmi_text_top.cm (トップ)
  ├── video_timing.cm
  ├── gbc_display.cm
  ├── font_rom.cm
  ├── text_renderer.cm
  ├── animation_ctrl.cm
  ├── tmds_encoder.cm (×3 インスタンス)
  └── tmds_serializer.cm (×4 インスタンス)
```

単一ファイルに全ロジックを書くと 1000 行以上になり、保守が困難。

## 実装要件

### 方式 1: extern struct による Cm モジュールインスタンス化

`extern struct` を拡張し、他の `.cm` ファイルから生成された
SV モジュールをインスタンス化可能にする:

```cm
// tmds_encoder.cm で生成される SV モジュール
//   module tmds_encoder(input clk, input [7:0] data_in, ...);

// hdmi_text_top.cm でのインスタンス化
extern struct tmds_encoder {
    #[input]  posedge clk       = pixel_clk;
    #[input]  utiny   data_in   = red_data;
    #[input]  bool    c0        = hsync;
    #[input]  bool    c1        = vsync;
    #[input]  bool    de        = de_active;
    #[output] ushort  tmds_out  = tmds_red;
}
tmds_encoder tmds_enc_r;  // Red チャネル
tmds_encoder tmds_enc_g;  // Green チャネル
tmds_encoder tmds_enc_b;  // Blue チャネル
```

### 方式 2: import + namespace 分離

Cm の import を使いつつ、SV バックエンドで
名前空間分離を行う:

```cm
// hdmi_text_top.cm
import "video_timing.cm";    // → video_timing_ プレフィックスが付く？
import "tmds_encoder.cm";
```

### 方式 3: 手動 SV ラッパー (推奨フォールバック)

各 `.cm` ファイルを個別に SV に変換し、手書きの SV トップモジュールで接続:

```bash
# 各モジュール生成
cm compile --target=sv src/hdmi/video_timing.cm -o build/video_timing.sv
cm compile --target=sv src/hdmi/tmds_encoder.cm -o build/tmds_encoder.sv
```

```systemverilog
// build/hdmi_text_top.sv (手書き)
module hdmi_text_top(
    input  clk_50m,
    output tmds_d2_p, tmds_d2_n,
    // ...
);
    wire pixel_clk, serial_clk;

    // PLL
    rPLL pll_inst(...);

    // Video Timing
    video_timing vt_inst(
        .pixel_clk(pixel_clk),
        .hsync(hsync),
        .vsync(vsync),
        .de(de),
        .h_count(h_count),
        .v_count(v_count)
    );

    // TMDS Encoder (×3)
    tmds_encoder tmds_r(.clk(pixel_clk), .data_in(red), ...);
    tmds_encoder tmds_g(.clk(pixel_clk), .data_in(green), ...);
    tmds_encoder tmds_b(.clk(pixel_clk), .data_in(blue), ...);
endmodule
```

## 推奨アプローチ

### Phase 1: 単一ファイル + 手動分割

1. まず単一の `.cm` ファイル (`hdmi_text_top.cm`) に全ロジックを記述
2. 動作確認後、機能ごとに関数を分離
3. 最終的に手動 SV ラッパー (方式 3) に移行

### Phase 2 以降: extern struct 拡張

Cm コンパイラ側で `extern struct` をユーザーモジュールに拡張する。

## 優先度

**LOW** — 手動 SV ラッパーで回避可能。
ただし、プロジェクト規模が大きくなると生産性に影響する。

## 関連

- [Cm Preprocessor: Import System](../../../.gemini/antigravity-ide/knowledge/cm_preprocessor_system/artifacts/import_system.md)
- [SV Backend: Attributes and Mapping](../../../.gemini/antigravity-ide/knowledge/cm_systemverilog_backend_implementation/artifacts/attributes_and_mapping.md)
