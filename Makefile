# ============================================================
# CmCPU プロジェクト Makefile
# ============================================================
# Cm言語 → SystemVerilog → FPGA ビルドフロー
# ターゲット: Sipeed Tang Mega 60K Console (GW5AT-LV60PG484A)
# ============================================================

# パス設定
CM := ./Cm/cm
BUILD_DIR := build
SRC_DIR := src

# Lチカ回路の設定
BLINK_SRC := $(SRC_DIR)/blink/blink.cm
BLINK_CST := $(SRC_DIR)/blink/tang_console_138k.cst
BLINK_SV := $(BUILD_DIR)/blink.sv

# FPGA 合成ビルド成果物
BLINK_JSON := $(BUILD_DIR)/blink.json
BLINK_PNR := $(BUILD_DIR)/blink_pnr.json
BLINK_FS := $(BUILD_DIR)/blink/impl/pnr/blink.fs

# FPGAボード・デバイス設定
BOARD := tangmega138k
DEVICE := GW5AST-LV138PG484A
DEVICE_SHORT := GW5AST-138

# FPGAツールチェーンパス
# Gowin EDA (公式ツール)
GW_HOME := /Applications/GowinIDE.app/Contents/Resources/Gowin_EDA
GW_SH := $(GW_HOME)/IDE/bin/gw_sh
GW_LIB := $(GW_HOME)/IDE/lib
GOWIN_TCL := $(SRC_DIR)/blink/gowin_build.tcl
# nextpnr-himbaechel: プロジェクトローカルビルド
NEXTPNR := .tmp/nextpnr/build/nextpnr-himbaechel
# gowin_pack: Apycula (Python ユーザーインストール)
GOWIN_PACK := $(HOME)/Library/Python/3.14/bin/gowin_pack

# ============================================================
# デフォルトターゲット
# ============================================================
.PHONY: help
help:
	@echo "CmCPU プロジェクト - Make コマンド"
	@echo ""
	@echo "Cm ビルド:"
	@echo "  make build        - Cm → SV 変換 + リントチェック"
	@echo "  make build-cm     - Cmコンパイラ自体をビルド"
	@echo ""
	@echo "FPGA 合成:"
	@echo "  make gowin        - Gowin EDA フルフロー (SV → FS) ← 推奨"
	@echo "  make appy         - Apycula OSS フルフロー (実験的)"
	@echo ""
	@echo "FPGA 書き込み:"
	@echo "  make flash        - FPGAに書き込み (.fs)"
	@echo "  make flash-sram   - SRAM書き込み (.bit)"
	@echo ""
	@echo "ユーティリティ:"
	@echo "  make clean        - ビルド出力をクリーン"
	@echo "  make setup        - 開発環境セットアップ (macOS)"

# ============================================================
# Cm ビルド: Cm → SV 変換 + リントチェック
# ============================================================
.PHONY: build
build: $(BLINK_SV)
	@echo "Verilator リントチェック中..."
	verilator --lint-only --timing -Wno-fatal $(BLINK_SV)
	@echo ""
	@echo "=========================================="
	@echo "✅ ビルド完了! $(BLINK_SV)"
	@echo "=========================================="

$(BLINK_SV): $(BLINK_SRC)
	@echo "Cm → SystemVerilog 変換中..."
	@mkdir -p $(BUILD_DIR)
	$(CM) compile --target=sv $(BLINK_SRC) -o $(BLINK_SV)
	@echo "✅ SV生成完了: $(BLINK_SV)"

# ============================================================
# Cmコンパイラのビルド
# ============================================================
.PHONY: build-cm
build-cm:
	@echo "Cmコンパイラをビルド中..."
	@cd Cm && make build
	@echo "✅ Cmコンパイラのビルド完了!"

# ============================================================
# FPGA 合成フロー (Gowin EDA 公式): SV → FS
# ============================================================
.PHONY: gowin
gowin: $(BLINK_SV)
	@echo "Gowin EDA で合成・配置配線・ビットストリーム生成中..."
	DYLD_LIBRARY_PATH=$(GW_LIB) DYLD_FRAMEWORK_PATH=$(GW_LIB) $(GW_SH) $(GOWIN_TCL)
	@echo ""
	@echo "=========================================="
	@echo "✅ Gowin EDA ビルド完了! $(BLINK_FS)"
	@echo "=========================================="

# ============================================================
# FPGA 合成フロー (Apycula OSS): SV → FS  [実験的]
# ============================================================
# 注意: GW5AST-138 のパッケージデータは Apycula で未実装のため
#       pnr ステップは現在動作しません。

# 統合ターゲット: make appy = synth + pnr + bitstream
.PHONY: appy
appy: synth pnr bitstream
	@echo ""
	@echo "=========================================="
	@echo "✅ FPGA ビルド完了! $(BLINK_FS)"
	@echo "=========================================="

# ステップ1: Yosys 合成 (SV → JSON ネットリスト)
.PHONY: synth
synth: $(BLINK_JSON)

$(BLINK_JSON): $(BLINK_SV)
	@echo "Yosys 合成中 (SV → JSON)..."
	@mkdir -p $(BUILD_DIR)
	yosys -p "read_verilog -sv $(BLINK_SV); synth_gowin -top blink -json $(BLINK_JSON)"
	@echo "✅ 合成完了: $(BLINK_JSON)"

# ステップ2: nextpnr 配置配線 (JSON → PNR JSON)
.PHONY: pnr
pnr: $(BLINK_PNR)

$(BLINK_PNR): $(BLINK_JSON) $(BLINK_CST)
	@echo "nextpnr 配置配線中 (JSON → PNR JSON)..."
	$(NEXTPNR) --device $(DEVICE) --json $(BLINK_JSON) --write $(BLINK_PNR) --vopt cst=$(BLINK_CST)
	@echo "✅ 配置配線完了: $(BLINK_PNR)"

# ステップ3: gowin_pack ビットストリーム生成 (PNR JSON → FS)
.PHONY: bitstream
bitstream: $(BLINK_FS)

$(BLINK_FS): $(BLINK_PNR)
	@echo "gowin_pack ビットストリーム生成中 (PNR JSON → FS)..."
	$(GOWIN_PACK) -d $(DEVICE_SHORT) -o $(BLINK_FS) $(BLINK_PNR)
	@echo "✅ ビットストリーム生成完了: $(BLINK_FS)"

# ============================================================
# FPGA書き込み
# ============================================================
.PHONY: flash
flash:
	@echo "FPGAに書き込み中 (Flash)..."
	openFPGALoader -b $(BOARD) $(BLINK_FS)
	@echo "✅ 書き込み完了!"

# Cm → SV → FS → FPGA 一括実行
.PHONY: apply
apply: build gowin flash

.PHONY: flash-sram
flash-sram:
	@echo "FPGAに書き込み中 (SRAM)..."
	openFPGALoader -b $(BOARD) --sram $(BUILD_DIR)/blink.bit
	@echo "✅ SRAM書き込み完了!"

# ============================================================
# 開発環境セットアップ (macOS)
# ============================================================
.PHONY: setup
setup:
	@echo "macOS 開発環境をセットアップ中..."
	@echo ""
	@echo "1. Cmコンパイラの依存関係をインストール..."
	brew install llvm@17 cmake openssl@3
	@echo ""
	@echo "2. FPGAツールをインストール..."
	brew install openfpgaloader yosys verilator
	@echo ""
	@echo "3. Apycula (gowin_pack) をインストール..."
	pip3 install --user apycula
	@echo ""
	@echo "4. Cmコンパイラをビルド..."
	$(MAKE) build-cm
	@echo ""
	@echo "=========================================="
	@echo "✅ セットアップ完了!"
	@echo "=========================================="

# ============================================================
# クリーン
# ============================================================
.PHONY: clean
clean:
	@echo "ビルド出力をクリーン中..."
	@rm -rf $(BUILD_DIR)
	@echo "✅ クリーン完了!"

