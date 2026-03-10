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

## ディレクトリ構成

```
CmCPU/
├── Cm/                  # Cmコンパイラ（サブモジュール）
├── src/
│   └── blink/           # Lチカ回路
│       ├── blink.cm     # Cmソースコード
│       └── tang_console_138k.cst  # ピン制約ファイル
├── build/               # ビルド出力（.sv, .bit等）
├── docs/                # ドキュメント
└── Makefile
```

## ライセンス

MIT
