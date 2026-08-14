# CmCPU

Cm言語のSystemVerilogバックエンドを使用してFPGA回路を設計するプロジェクト。

## ターゲットハードウェア

- **ボード**: Sipeed Tang Console 138K
- **FPGA**: Gowin GW5AST-LV138PG484A
- **クロック**: Gowin内蔵OSC 210MHz を分周して使用（HDMI系のみ外部50MHz入力 + PLL）

## 前提条件

### macOS

```bash
# Cmコンパイラのビルドに必要
brew install llvm@17 cmake openssl@3

# FPGA書き込みツール
brew install openfpgaloader

# SVリントチェック（オプション）
brew install verilator

# シミュレーションテスト
brew install icarus-verilog
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
| blink | `make build-blink` | Lチカ（手書き.cst/.tclの従来フロー） |
| pwm | `make build-pwm` | PWM呼吸LED（`#[sv::pin]` + `--emit-constraints` で .cst/.tcl を自動生成） |
| button | `make build-button` | ボタンカウンタ（押下回数を2bit LEDに表示） |
| uart | `make build-uart-hello` / `make build-uart-button` | UART送信（"Hello" 送出 / ボタン押下通知） |
| hdmi | `make build-hdmi-colorbar` / `make build-hdmi-text` | HDMI出力（カラーバー / テキスト表示） |
| cpu | `make build-cpu` | SimpleCPU（デモプログラムを実行し結果をMMIOへ出力。SV生成+リント+シミュレーションのみ） |
| gpu | `make build-gpu` | SimpleGPU（矩形フィルとフレームバッファ読み出し。SV生成+リント+シミュレーションのみ） |

blink / uart / hdmi には `make gowin-<name>`（gw_shでの合成）と `make flash-<name>`（書き込み）、および一括実行の `make apply-<name>` があります。
pwm / button は制約ファイルを手書きせず、生成された `*_build.tcl`（例: `build/pwm/pwm_breath_build.tcl`）を `gw_sh` に渡すだけで合成まで実行できます。

## テスト

全回路にシミュレーションテストが付属しています:

```bash
make test          # 全回路
make test-cpu      # フォルダ単位（src/cpu 配下のみ）
```

テストは `scripts/test_circuits.sh` が自動発見します（テストラッパー `src/**/*_test.cm` と、`#[test]` 関数を内蔵する回路ファイル）。
各テストは `cm test` が `//! platform: sv` を検出してSV+テストベンチを生成し、iverilog + vvp で実行します。
テストモードでは定義 `TEST` が自動追加されるため、各回路は `#ifdef TEST` でクロック外部注入・タイミング定数短縮に切り替わります。
PLL / OSER10 / TLVDS_OBUF などのGowinベンダプリミティブはシミュレーション対象外です（`#ifdef TEST` で除外し、verilatorリントと実機フローで検証）。

## CI

GitHub Actions（`.github/workflows/ci.yml`）で push / PR ごとに、Cmコンパイラのビルド → 全回路のSV生成+verilatorリント → `make test`（iverilogシミュレーション）を実行します。

## ディレクトリ構成

```
CmCPU/
├── Cm/                  # Cmコンパイラ（サブモジュール）
├── src/
│   ├── blink/           # Lチカ回路
│   ├── pwm/             # PWM呼吸LED
│   ├── button/          # ボタンカウンタ
│   ├── uart/            # UART送信
│   ├── hdmi_colorbar/   # HDMIカラーバー出力
│   ├── hdmi_text/       # HDMIテキスト表示
│   ├── cpu/             # SimpleCPU
│   ├── gpu/             # SimpleGPU
│   └── modules/         # 共有モジュール（HDMI出力・共通定義）
├── scripts/             # テスト実行スクリプト
├── build/               # ビルド出力（.sv, .cst, .tcl, .fs等）
├── docs/                # ドキュメント
└── Makefile
```

## ライセンス

MIT
