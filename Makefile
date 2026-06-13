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

# UART Hello 回路の設定
UART_SRC := $(SRC_DIR)/uart/uart_hello.cm
UART_CST := $(SRC_DIR)/uart/tang_console_138k.cst
UART_SV := $(BUILD_DIR)/uart_hello.sv
UART_TCL := $(SRC_DIR)/uart/gowin_build.tcl
UART_FS := $(BUILD_DIR)/uart_hello/impl/pnr/uart_hello.fs

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
	@echo "Lチカ (blink):"
	@echo "  make build        - Cm → SV 変換 + リントチェック"
	@echo "  make gowin        - Gowin EDA フルフロー (SV → FS)"
	@echo "  make flash        - FPGAに書き込み (.fs)"
	@echo "  make apply        - build + gowin + flash 一括実行"
	@echo ""
	@echo "UART Hello:"
	@echo "  make uart-build   - Cm → SV 変換 + リントチェック"
	@echo "  make uart-gowin   - Gowin EDA フルフロー (SV → FS)"
	@echo "  make uart-flash   - FPGAに書き込み (.fs)"
	@echo "  make uart-apply   - build + gowin + flash 一括実行"
	@echo ""
	@echo "HDMI カラーバー:"
	@echo "  make hdmi-build   - Cm → SV 変換 + ポスト処理"
	@echo "  make hdmi-gowin   - Gowin EDA フルフロー (SV → FS)"
	@echo "  make hdmi-flash   - FPGAに書き込み (.fs)"
	@echo "  make hdmi-apply   - build + gowin + flash 一括実行"
	@echo ""
	@echo "共通:"
	@echo "  make build-cm     - Cmコンパイラ自体をビルド"
	@echo "  make clean        - ビルド出力をクリーン"
	@echo "  make setup        - 開発環境セットアップ (macOS)"

# ============================================================
# Cm ビルド: Cm → SV 変換 + リントチェック
# ============================================================
.PHONY: build
build: $(BLINK_SV)
	@echo "Verilator リントチェック中..."
	verilator --lint-only --timing -Wno-fatal -Wno-MODMISSING $(BLINK_SV)
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

# ============================================================
# UART Hello: Cm → SV + リントチェック
# ============================================================
.PHONY: uart-build
uart-build: $(UART_SV)
	@echo "Verilator リントチェック中..."
	verilator --lint-only --timing -Wno-fatal -Wno-MODMISSING $(UART_SV)
	@echo ""
	@echo "=========================================="
	@echo "✅ UART ビルド完了! $(UART_SV)"
	@echo "=========================================="

$(UART_SV): $(UART_SRC)
	@echo "Cm → SystemVerilog 変換中 (UART)..."
	@mkdir -p $(BUILD_DIR)
	$(CM) compile --target=sv $(UART_SRC) -o $(UART_SV)
	@echo "✅ SV生成完了: $(UART_SV)"

# ============================================================
# UART Hello: Gowin EDA フルフロー
# ============================================================
.PHONY: uart-gowin
uart-gowin: $(UART_SV)
	@echo "Gowin EDA で合成・配置配線・ビットストリーム生成中 (UART)..."
	DYLD_LIBRARY_PATH=$(GW_LIB) DYLD_FRAMEWORK_PATH=$(GW_LIB) $(GW_SH) $(UART_TCL)
	@echo ""
	@echo "=========================================="
	@echo "✅ Gowin EDA UART ビルド完了! $(UART_FS)"
	@echo "=========================================="

# ============================================================
# UART Hello: FPGA書き込み
# ============================================================
.PHONY: uart-flash
uart-flash:
	@echo "FPGAに書き込み中 (UART)..."
	openFPGALoader -b $(BOARD) $(UART_FS)
	@echo "✅ UART 書き込み完了!"

# UART: Cm → SV → FS → FPGA 一括実行
.PHONY: uart-apply
uart-apply: uart-build uart-gowin uart-flash

# ============================================================
# Button UART: 変数定義
# ============================================================
BTN_SRC := $(SRC_DIR)/uart/uart_button.cm
BTN_SV := $(BUILD_DIR)/uart_button.sv
BTN_TCL := $(SRC_DIR)/uart/gowin_button.tcl
BTN_FS := $(BUILD_DIR)/uart_button/impl/pnr/uart_button.fs

# ============================================================
# Button UART: Cm → SV + リントチェック
# ============================================================
.PHONY: btn-build
btn-build: $(BTN_SV)
	@echo "Verilator リントチェック中..."
	verilator --lint-only --timing -Wno-fatal -Wno-MODMISSING $(BTN_SV)
	@echo ""
	@echo "=========================================="
	@echo "✅ Button UART ビルド完了! $(BTN_SV)"
	@echo "=========================================="

$(BTN_SV): $(BTN_SRC)
	@echo "Cm → SystemVerilog 変換中 (Button)..."
	@mkdir -p $(BUILD_DIR)
	$(CM) compile --target=sv $(BTN_SRC) -o $(BTN_SV)
	@echo "✅ SV生成完了: $(BTN_SV)"

.PHONY: btn-gowin
btn-gowin: $(BTN_SV)
	@echo "Gowin EDA で合成中 (Button)..."
	DYLD_LIBRARY_PATH=$(GW_LIB) DYLD_FRAMEWORK_PATH=$(GW_LIB) $(GW_SH) $(BTN_TCL)
	@echo "✅ Gowin EDA Button ビルド完了!"

.PHONY: btn-flash
btn-flash:
	@echo "FPGAに書き込み中 (Button)..."
	openFPGALoader -b $(BOARD) $(BTN_FS)
	@echo "✅ Button 書き込み完了!"

.PHONY: btn-apply
btn-apply: btn-build btn-gowin btn-flash

# ============================================================
# HDMI カラーバー: 変数定義
# ============================================================
HDMI_SRC := $(SRC_DIR)/hdmi/main.cm
HDMI_SV := $(BUILD_DIR)/hdmi/hdmi_colorbar.sv
HDMI_TCL := $(SRC_DIR)/hdmi/gowin_hdmi.tcl
HDMI_FS := $(BUILD_DIR)/hdmi/hdmi_colorbar/impl/pnr/hdmi_colorbar.fs

# ============================================================
# HDMI カラーバー: Cm → SV
# ============================================================
.PHONY: hdmi-build
hdmi-build: $(HDMI_SV)
	@echo "Verilator リントチェック中..."
	/usr/local/bin/verilator --lint-only --timing -Wno-MODMISSING $(HDMI_SV)
	@echo ""
	@echo "=========================================="
	@echo "✅ HDMI ビルド完了! $(HDMI_SV)"
	@echo "=========================================="

$(HDMI_SV): $(HDMI_SRC)
	@echo "Cm → SystemVerilog 変換中 (HDMI)..."
	@mkdir -p $(BUILD_DIR)/hdmi
	$(CM) compile --target=sv $(HDMI_SRC) -o $(HDMI_SV)
	@echo "✅ SV生成完了: $(HDMI_SV)"

# ============================================================
# HDMI カラーバー: Gowin EDA フルフロー
# ============================================================
.PHONY: hdmi-gowin
hdmi-gowin: $(HDMI_SV)
	@echo "Gowin EDA で合成・配置配線・ビットストリーム生成中 (HDMI)..."
	@if [ -f "$(HDMI_FS)" ]; then echo "[WARN] 古いビットストリームを削除: $(HDMI_FS)"; rm -f "$(HDMI_FS)"; fi
	DYLD_LIBRARY_PATH=$(GW_LIB) DYLD_FRAMEWORK_PATH=$(GW_LIB) $(GW_SH) $(HDMI_TCL)
	@echo ""
	@echo "=========================================="
	@echo "✅ Gowin EDA HDMI ビルド完了! $(HDMI_FS)"
	@echo "=========================================="

# ============================================================
# HDMI カラーバー: FPGA書き込み
# ============================================================
.PHONY: hdmi-flash
hdmi-flash:
	@echo "FPGAに書き込み中 (HDMI)..."
	eval "$$(/opt/homebrew/bin/brew shellenv)" && openFPGALoader --cable ft2232 -b $(BOARD) $(HDMI_FS)
	@echo "✅ HDMI 書き込み完了!"

# HDMI: Cm → SV → FS → FPGA 一括実行
.PHONY: hdmi-apply
hdmi-apply: hdmi-build hdmi-gowin hdmi-flash

# ============================================================
# HDMI テキスト/アニメーション: 変数定義
# ============================================================
TEXT_SRC := $(SRC_DIR)/hdmi/hdmi_text_top.cm
TEXT_SV := $(BUILD_DIR)/hdmi/hdmi_text.sv
TEXT_TCL := $(SRC_DIR)/hdmi/gowin_hdmi_text.tcl
TEXT_FS := $(BUILD_DIR)/hdmi/hdmi_text/impl/pnr/hdmi_text.fs

# ============================================================
# HDMI テキスト/アニメーション: Cm → SV
# ============================================================
.PHONY: text-build
text-build: $(TEXT_SV)
	@echo "Verilator リントチェック中..."
	/usr/local/bin/verilator --lint-only --timing -Wno-MODMISSING $(TEXT_SV)
	@echo ""
	@echo "=========================================="
	@echo "✅ HDMI テキストビルド完了! $(TEXT_SV)"
	@echo "=========================================="

$(TEXT_SV): $(TEXT_SRC)
	@echo "Cm → SystemVerilog 変換中 (HDMI Text)..."
	@mkdir -p $(BUILD_DIR)/hdmi
	$(CM) compile --target=sv $(TEXT_SRC) -o $(TEXT_SV)
	@echo "✅ SV生成完了: $(TEXT_SV)"

# ============================================================
# HDMI テキスト/アニメーション: Gowin EDA フルフロー
# ============================================================
.PHONY: text-gowin
text-gowin: $(TEXT_SV)
	@echo "Gowin EDA で合成・配置配線・ビットストリーム生成中 (HDMI Text)..."
	@if [ -f "$(TEXT_FS)" ]; then echo "[WARN] 古いビットストリームを削除: $(TEXT_FS)"; rm -f "$(TEXT_FS)"; fi
	DYLD_LIBRARY_PATH=$(GW_LIB) DYLD_FRAMEWORK_PATH=$(GW_LIB) $(GW_SH) $(TEXT_TCL)
	@echo ""
	@echo "=========================================="
	@echo "✅ Gowin EDA HDMI テキストビルド完了! $(TEXT_FS)"
	@echo "=========================================="

# ============================================================
# HDMI テキスト/アニメーション: FPGA書き込み
# ============================================================
.PHONY: text-flash
text-flash:
	@echo "FPGAに書き込み中 (HDMI Text)..."
	eval "$$(/opt/homebrew/bin/brew shellenv)" && openFPGALoader --cable ft2232 -b $(BOARD) $(TEXT_FS)
	@echo "✅ HDMI テキスト書き込み完了!"

# HDMI テキスト: Cm → SV → FS → FPGA 一括実行
.PHONY: text-apply
text-apply: text-build text-gowin text-flash


