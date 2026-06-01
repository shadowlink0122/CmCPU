# HDMI 出力 UART プロジェクト概要

## 目的

Tang Console 138K (GW5AST-LV138PG484A) 上で、HDMI 経由のテキスト表示回路を
Cm 言語 (SystemVerilog バックエンド) で実装する。
ゲームボーイカラー (GBC) の画面仕様をベースとした表示設定を実現し、
"Hello World" のアニメーション出力をデモとして動作させる。

## 要件

| # | 要件 | 検証方法 |
|---|------|----------|
| R1 | HDMI から文字が出力されること | モニタ接続による目視 + テストベンチ |
| R2 | GBC 標準画面設定 (160×144, 15bit RGB, 10:9 アスペクト比) | パラメータ確認 + シミュレーション |
| R3 | Hello World の出力とアニメーション表示 | モニタ接続目視 + VCD 波形検証 |
| R4 | テストが含まれていること | Verilator lint + テストベンチ |

## ターゲットハードウェア

- **FPGA**: Gowin GW5AST-LV138PG484A (Arora V, 138K LUT)
- **ボード**: Sipeed Tang Console 138K
- **クロック**: 50MHz 水晶オシレータ (Pin: V10) / 内蔵 OSC 52.5MHz
- **HDMI 出力**: TMDS 差動ペア (Bank 3)
  - D2P/D2N: AA22/AA23
  - D1P/D1N: V24/W24
  - D0P/D0N: AB24/AC24
  - CKP/CKN: Y22/Y23

## アーキテクチャ概要

```
┌──────────────────────────────────────────────────┐
│                    Top Module                     │
│  (hdmi_text_top.cm)                              │
│                                                   │
│  ┌──────────┐  ┌──────────────┐  ┌────────────┐ │
│  │  PLL     │  │  Video       │  │  TMDS      │ │
│  │  (Gowin) │──│  Timing Gen  │──│  Encoder   │ │
│  │  25MHz   │  │  640×480     │  │  ×3ch      │ │
│  │  125MHz  │  └──────┬───────┘  └─────┬──────┘ │
│  └──────────┘         │                │         │
│                 ┌─────┴──────┐   ┌─────┴──────┐ │
│                 │  GBC       │   │  Serializer│ │
│                 │  Framebuf  │   │  (OSER10/  │ │
│                 │  160×144   │   │   DDR)     │ │
│                 └─────┬──────┘   └─────┬──────┘ │
│                 ┌─────┴──────┐   ┌─────┴──────┐ │
│                 │  Font ROM  │   │  Diff I/O  │ │
│                 │  8×8 ASCII │   │  TMDS Out  │ │
│                 └────────────┘   └────────────┘ │
│                                                   │
│  ┌──────────────────────────────────────────────┐ │
│  │  Text / Animation Controller                 │ │
│  │  - Hello World 文字列生成                     │ │
│  │  - カーソル位置管理                           │ │
│  │  - アニメーション FSM                         │ │
│  └──────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────┘
```

## モジュール構成

| モジュール | ファイル | 責務 |
|------------|----------|------|
| **Top** | `hdmi_text_top.cm` | トップレベル配線・PLL インスタンス化 |
| **Video Timing** | `video_timing.cm` | 640×480@60Hz タイミング生成 (H/V sync, DE) |
| **GBC Display** | `gbc_display.cm` | GBC 画面設定 (160×144→480×432 スケーリング) |
| **Font ROM** | `font_rom.cm` | 8×8 ASCII フォントデータ (BRAM) |
| **Text Renderer** | `text_renderer.cm` | フォント→ピクセル変換、カラーパレット適用 |
| **Animation Controller** | `animation_ctrl.cm` | Hello World アニメーション FSM |
| **TMDS Encoder** | `tmds_encoder.cm` | 8b/10b TMDS エンコーディング (×3ch) |
| **Serializer** | `tmds_serializer.cm` | 10:1 シリアライズ (OSER10 プリミティブ) |

## 実装フェーズ

### Phase 1: 基盤 — ビデオタイミング + TMDS (目標: カラーバー表示)

1. PLL 設定 (25.2MHz pixel clock + 126MHz bit clock)
2. 640×480@60Hz ビデオタイミングジェネレータ
3. TMDS エンコーダ (3チャネル)
4. シリアライザ (Gowin OSER10 / DDR)
5. カラーバーテストパターン生成
6. テストベンチ: タイミング検証

### Phase 2: テキスト表示 — フォント + レンダリング

1. 8×8 ASCII フォント ROM (BRAM)
2. テキストレンダラ (文字→ピクセル)
3. GBC カラーパレット適用
4. "Hello World" 静的表示
5. テストベンチ: フォント読み出し検証

### Phase 3: GBC 画面設定 — スケーリング + パレット

1. 160×144 → 480×432 (3x 整数スケーリング)
2. 15bit RGB カラーパレット (32768色)
3. 10:9 アスペクト比 (レターボックス)
4. テストベンチ: スケーリング検証

### Phase 4: アニメーション + 統合テスト

1. Hello World 1文字ずつ表示アニメーション
2. カーソル点滅
3. 統合テストベンチ
4. FPGA 実機検証

## ビルドフロー

```bash
# Phase 1: Cm → SV 変換 + Verilator リント
make hdmi-build

# Phase 2: Gowin EDA 合成・配置配線
make hdmi-gowin

# Phase 3: FPGA 書き込み
make hdmi-flash

# 一括実行
make hdmi-apply
```

## ディレクトリ構造

```
CmCPU/
├── src/
│   └── hdmi/                    # HDMI テキスト出力ソース
│       ├── hdmi_text_top.cm     # トップモジュール
│       ├── video_timing.cm      # ビデオタイミング
│       ├── gbc_display.cm       # GBC 画面設定
│       ├── font_rom.cm          # フォント ROM
│       ├── text_renderer.cm     # テキストレンダラ
│       ├── animation_ctrl.cm    # アニメーション制御
│       ├── tmds_encoder.cm      # TMDS エンコーダ
│       ├── tmds_serializer.cm   # シリアライザ
│       ├── tang_console_138k_hdmi.cst  # ピン制約
│       └── gowin_hdmi.tcl       # Gowin ビルドスクリプト
├── docs/
│   └── uart/
│       └── hdmi/                # ← 本ドキュメント群
└── build/
    └── hdmi/                    # ビルド出力
```

## 参考資料

- [DVI 1.0 Specification](https://www.ddwg.org/lib/dvi_10.pdf) — TMDS エンコーディング仕様
- [Sipeed TangMega-138K-example](https://github.com/sipeed/TangMega-138K-example) — HDMI カラーバーサンプル
- [Gowin DVI TX IP](https://www.gowinsemi.com/) — 公式 DVI TX IP ドキュメント
- [Game Boy Color 仕様](https://gbdev.io/pandocs/) — 画面解像度・カラー仕様
