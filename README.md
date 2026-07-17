# CmCPU

Cm言語のSystemVerilogバックエンドを使用してCPU回路を設計するプロジェクト。

## ターゲットハードウェア

- **ボード**: Sipeed Tang Console 138K
- **FPGA**: Gowin GW5AST-LV138PG484A
- **クロック**: 50MHz

## 前提条件

### macOS

```bash
# Cmコンパイラのビルドに必要
brew install llvm@17 cmake openssl@3

# FPGA書き込みツール
brew install openfpgaloader

# SVリントチェック（オプション）
brew install verilator
```

## ビルド手順

```bash
# 1. サブモジュールの初期化
git submodule update --init --recursive

# 2. Cmコンパイラのビルド
make build-cm

# 3. Cm → SystemVerilog 変換 + リントチェック
make build-blink

# 4. FPGAへの書き込み（Gowin EDAでビットストリーム生成後）
make flash-blink
```

## サンプル一覧

| サンプル | ビルド | 内容 |
|---|---|---|
| blink | `make build-blink` | Lチカ（内蔵OSC + CFG LED、手書き.cst/.tclの従来フロー） |
| pwm | `make build-pwm` | **PWM呼吸LED** — `#[sv::pin]` + `--emit-constraints` で .cst/.tcl を自動生成（v0.16.0） |
| button | `make build-button` | **ボタンカウンタ** — `#[sv::sync]` によるCDC 2FF同期 + デバウンス + エッジ検出（v0.16.0） |
| uart | `make build-uart-hello` | UART送信（"Hello" 送出） |
| hdmi | `make build-hdmi-colorbar` / `make build-hdmi-text` | HDMI出力（カラーバー / テキスト表示。フォントROMはBRAM + $readmemh） |
| cpu | `make build-cpu` | **SimpleCPU** — 16bit命令アキュムレータ型CPU（ROM上の総和プログラムを実行、matchデコード） |
| gpu | `make build-gpu` | **SimpleGPU** — 矩形フィルラスタライザ（クリア→フィルFSM + デュアルポートRAM読み出し） |

pwm / button は制約ファイルを手書きしません。生成された
`build/<name>/<name>_build.tcl` を `gw_sh` に渡すだけで合成まで実行できます。

## テスト

全回路にシミュレーションテストが付属しています（v0.16.0の
`#[test]` 検証フレームワークと `cm test` コマンドを使用）:

```bash
make test
```

各テストは `cm test` が `//! platform: sv` を検出してSV+テストベンチを生成し、
iverilog + vvp で実行します。テストモードでは定義 `TEST` が自動追加されるため、
各回路は `#ifdef TEST` でクロック外部注入・タイミング定数短縮に切り替わります。
`#[test]` を付けた関数が `step(n)` でクロックを進め `assert` で検証し、
不成立時は `$fatal` で失敗します。

テストは自動発見されます: テストラッパー `src/**/*_test.cm`
（対象モジュールと同じ階層に配置）と、`#[test]` 関数を内蔵する回路ファイル。

| テスト | 対象 | 検証内容 |
|---|---|---|
| blink_test | src/blink | LEDトグル周期 |
| pwm_breath_test | src/pwm | PWM相補出力・呼吸動作 |
| button_counter_test | src/button | 同期→デバウンス→押下エッジ→2bitカウント |
| uart_hello_test | src/uart | 起動待機→スタートビット→14バイト送信完了 |
| uart_button_test | src/uart | 押下検出→"Pressed: N"送信開始→完了 |
| modules_hdmi_timing_test | src/modules/hdmi | VGA水平・垂直タイミング（アクティブ/FP/SYNC/BP・VSYNCパルス・フレーム境界、DE） |
| modules_hdmi_out_test | src/modules/hdmi | 汎用HDMI出力モジュール単体（固定色→3ch同一データ符号・コントロールトークン） |
| hdmi_colorbar_pattern_test | src/hdmi_colorbar | カラーバー8色の境界（白/黄/シアン/黒） |
| modules_hdmi_encoder_test | src/modules/hdmi | TMDSコントロールトークン（CTRL_00/11/10）とデータ符号 |
| hdmi_text_renderer_test | src/hdmi_text | フォントROM経由の文字描画（'H'横棒の黒画素・白背景） |
| hdmi_text_gbc_display_test | src/hdmi_text | 表示領域の座標変換（論理X/Y追従・アクティブ判定・行末飽和） |
| hdmi_text_animation_ctrl_test | src/hdmi_text | タイトル描画境界（書き込み最大アドレス700・境界セルの空白維持） |
| hdmi_colorbar_main_test | src/hdmi_colorbar/main.cm | カラーバートップ統合（バー色ごとのTMDS符号一致性・コントロールトークン） |
| hdmi_text_main_test | src/hdmi_text | テキストトップ統合（TMDS符号・アニメーション完了後のタイトル行描画） |
| cpu_simple_cpu_test | src/cpu | 総和プログラム実行（result=55）→HALT→停止後の安定性 |
| cpu_alu_test | src/cpu | 全加算器真理値表・加算/桁あふれ・2の補数減算・論理演算・シフト |
| gpu_simple_gpu_test | src/gpu | クリア→矩形フィル→フレームバッファ読み出し（矩形内外） |

PLL / OSER10 / TLVDS_OBUF はGowinベンダプリミティブのため
シミュレーション対象外です（`#ifdef TEST` で除外し、実機フローと
verilatorリントで検証）。合成用ビルド（`make build-<対象>`）はテストモードでは
ないため `#[test]` 関数ごと除去され、影響を受けません
（内蔵OSC・実タイミング定数のまま）。

## CI

GitHub Actions（`.github/workflows/ci.yml`）で push / PR ごとに
Cmコンパイラのビルド → 全回路のSV生成+verilatorリント → `make test`
（iverilogシミュレーション）を実行します。

## ディレクトリ構成

```
CmCPU/
├── Cm/                  # Cmコンパイラ（サブモジュール）
├── src/
│   ├── blink/           # Lチカ回路（手書き.cst/.tclフロー）
│   ├── pwm/             # PWM呼吸LED（制約自動生成フロー）
│   ├── button/          # ボタンカウンタ（CDC同期）
│   ├── uart/            # UART送信
│   └── hdmi/            # HDMI出力（カラーバー/テキスト）
├── build/               # ビルド出力（.sv, .cst, .tcl, .fs等）
├── docs/                # ドキュメント
└── Makefile
```

## ライセンス

MIT
