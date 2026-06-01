# トップモジュール統合設計

## 概要

全サブモジュールを統合するトップレベルモジュール `hdmi_text_top` の設計。
Gowin プリミティブ (rPLL, OSER10, TLVDS_OBUF) とユーザーロジックの
接続を管理する。

## モジュール接続図

```
                    ┌──────────────────────────────────────────────────────────┐
                    │                    hdmi_text_top                         │
                    │                                                          │
 clk_50m ──────────┤──► rPLL ──┬──► pixel_clk (25.2 MHz)                     │
 (Pin V10)         │          └──► serial_clk (126 MHz)                      │
                    │                    │                                      │
                    │    pixel_clk ──────┤                                      │
                    │                    ▼                                      │
                    │         ┌─────────────────┐                              │
                    │         │  video_timing    │                              │
                    │         │  ├── hsync       │                              │
                    │         │  ├── vsync       │                              │
                    │         │  ├── de          │                              │
                    │         │  ├── h_count     │                              │
                    │         │  └── v_count     │                              │
                    │         └────────┬─────────┘                              │
                    │                  │                                        │
                    │                  ▼                                        │
                    │         ┌─────────────────┐                              │
                    │         │  gbc_display     │                              │
                    │         │  ├── gbc_x       │                              │
                    │         │  ├── gbc_y       │                              │
                    │         │  └── gbc_active  │                              │
                    │         └────────┬─────────┘                              │
                    │                  │                                        │
                    │    ┌─────────────┼──────────────────┐                    │
                    │    ▼             ▼                  ▼                    │
                    │ ┌──────────┐ ┌──────────────┐ ┌──────────────┐          │
                    │ │ font_rom │ │text_renderer │ │animation_ctrl│          │
                    │ └────┬─────┘ └──────┬───────┘ └──────┬───────┘          │
                    │      │              │                │                    │
                    │      └──────────────┤                │                    │
                    │                     ▼                │                    │
                    │              ┌────────────┐          │                    │
                    │              │ RGB Pixel  │◄─────────┘                   │
                    │              │ (R,G,B 8bit)│                              │
                    │              └──────┬─────┘                              │
                    │                     │                                     │
                    │     ┌───────────────┼───────────────┐                    │
                    │     ▼               ▼               ▼                    │
                    │ ┌──────────┐   ┌──────────┐   ┌──────────┐              │
                    │ │tmds_enc_r│   │tmds_enc_g│   │tmds_enc_b│              │
                    │ └────┬─────┘   └────┬─────┘   └────┬─────┘              │
                    │      ▼              ▼              ▼                     │
                    │ ┌──────────┐   ┌──────────┐   ┌──────────┐              │
                    │ │ OSER10_R │   │ OSER10_G │   │ OSER10_B │   OSER10_CK │
                    │ └────┬─────┘   └────┬─────┘   └────┬─────┘   ────┬──── │
                    │      ▼              ▼              ▼             ▼      │
                    │ ┌──────────┐   ┌──────────┐   ┌──────────┐ ┌────────┐  │
                    │ │TLVDS_R   │   │TLVDS_G   │   │TLVDS_B   │ │TLVDS_CK│  │
                    │ └──┬───┬───┘   └──┬───┬───┘   └──┬───┬───┘ └─┬──┬───┘  │
                    │    │   │          │   │          │   │        │  │      │
                    └────┼───┼──────────┼───┼──────────┼───┼────────┼──┼──────┘
                         │   │          │   │          │   │        │  │
                    tmds_d2  tmds_d2  tmds_d1  tmds_d1  tmds_d0  tmds_d0  tmds_clk
                    _p(AA22) _n(AA23) _p(V24)  _n(W24)  _p(AB24) _n(AC24) _p(Y22)
                                                                          _n(Y23)
```

## 信号フロー

### データパス

1. **pixel_clk** が video_timing を駆動
2. video_timing が h_count, v_count, de, hsync, vsync を生成
3. gbc_display が座標変換 (hc,vc → gbc_x, gbc_y)
4. text_renderer が gbc_x, gbc_y からフォント ROM を参照しピクセル生成
5. animation_ctrl がテキストバッファを更新
6. RGB 8bit データが 3 つの tmds_encoder に入力
7. tmds_encoder が 10bit TMDS シンボルを出力
8. OSER10 がシリアライズ
9. TLVDS_OBUF が差動信号に変換

### コントロールパス

- animation_ctrl → text_renderer: テキストバッファ書き込み (text_addr, text_char, text_we)
- animation_ctrl → text_renderer: カーソル位置 (cursor_col, cursor_row, cursor_visible)
- video_timing → tmds_encoder: ブランキング期間でコントロールトークン送信

## トップモジュール Cm 擬似コード

```cm
//! platform: sv

// ============================================================
// HDMI テキスト出力トップモジュール
// ============================================================
// ターゲット: Tang Console 138K (GW5AST-LV138PG484A)
// クロック: 50MHz 外部オシレータ → PLL → 25.2MHz + 126MHz
// 出力: HDMI (DVI モード) 640×480@60Hz
// ============================================================

// === 外部クロック ===
#[input] posedge clk_50m;          // 50MHz システムクロック

// === HDMI TMDS 出力 (差動) ===
#[output] bool tmds_d2_p = false;  // Red+
#[output] bool tmds_d2_n = false;  // Red-
#[output] bool tmds_d1_p = false;  // Green+
#[output] bool tmds_d1_n = false;  // Green-
#[output] bool tmds_d0_p = false;  // Blue+
#[output] bool tmds_d0_n = false;  // Blue-
#[output] bool tmds_clk_p = false; // Clock+
#[output] bool tmds_clk_n = false; // Clock-

// === ステータス LED ===
#[output] bool led_ready = false;  // アニメーション中 (Red)
#[output] bool led_done  = false;  // 完了 (Blue)

// === 内部クロック ===
bool pixel_clk  = false;           // 25.2 MHz
bool serial_clk = false;           // 126 MHz
bool pll_locked  = false;          // PLL ロック

// === PLL インスタンス ===
extern struct rPLL {
    // ... (03_serializer_pll.md 参照)
}
rPLL pll_inst;

// === サブモジュール接続 ===
// (各モジュールのインスタンス化と信号接続)
```

> [!IMPORTANT]
> **Cm SV バックエンドのマルチモジュール対応**:
> 現在の Cm SV バックエンドでは、各 `.cm` ファイルが独立した
> SystemVerilog モジュールとして生成される。
> トップモジュールでのサブモジュール接続には以下の選択肢がある:
>
> 1. **単一ファイル方式**: 全ロジックを 1 つの `.cm` ファイルに統合
>    (既存の `uart_hello.cm` パターン)
> 2. **手動ラッパー方式**: 各 `.cm` → `.sv` を個別生成し、
>    手書きの SV トップモジュールで接続
> 3. **import 方式**: Cm のモジュールインポート機能を使用
>    (SV バックエンドでの対応状況を確認する必要あり)
>
> **推奨**: Phase 1 は単一ファイル方式で、Phase 2 以降で手動ラッパーに移行。

## テスト計画

| テスト | 検証内容 | 合格基準 |
|--------|----------|----------|
| TB-TOP-01 | PLL ロック | pll_locked が安定 HIGH (シミュレーションでは想定値) |
| TB-TOP-02 | 信号接続 | 全サブモジュールの入出力が正しく接続 |
| TB-TOP-03 | HDMI 出力 | TMDS 差動ペアにデータが出力 |
| TB-TOP-04 | LED ステータス | led_ready / led_done が状態に応じて変化 |
| TB-TOP-05 | 統合動作 | Hello World が正しく表示 (実機検証) |
