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

# 3. Cm → SystemVerilog 変換
make compile-sv

# 4. リントチェック
make lint

# 5. FPGAへの書き込み（Gowin EDAでビットストリーム生成後）
make flash
```

## サンプル一覧

| サンプル | ビルド | 内容 |
|---|---|---|
| blink | `make build` | Lチカ（内蔵OSC + CFG LED、手書き.cst/.tclの従来フロー） |
| pwm | `make pwm-build` | **PWM呼吸LED** — `#[sv::pin]` + `--emit-constraints` で .cst/.tcl を自動生成（v0.16.0） |
| button | `make button-build` | **ボタンカウンタ** — `#[sv::sync]` によるCDC 2FF同期 + デバウンス + エッジ検出（v0.16.0） |
| uart | `make uart-build` | UART送信（"Hello" 送出） |
| hdmi | `make hdmi-build` / `make text-build` | HDMI出力（カラーバー / テキスト表示。フォントROMはBRAM + $readmemh） |

pwm / button は制約ファイルを手書きしません。生成された
`build/<name>/<name>_build.tcl` を `gw_sh` に渡すだけで合成まで実行できます。

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
