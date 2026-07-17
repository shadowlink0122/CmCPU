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

# Verilator リント設定
# Gowinプリミティブ (OSC/PLL/OSER10/TLVDS_OBUF) は未定義モジュールになるため、
# lint/gowin_primitives.sv のブラックボックス・スタブを併せて渡して解決する
# (-Wno-MODMISSING は古いVerilatorに存在しないため使用しない)
VERILATOR ?= verilator
LINT_STUBS := lint/gowin_primitives.sv
VERILATOR_LINT := $(VERILATOR) --lint-only --timing -Wno-fatal -Wno-MULTITOP

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
	@echo "CmCPU プロジェクト - Make コマンド（動詞-対象 で統一）"
	@echo ""
	@echo "テスト:"
	@echo "  make test          - 全回路のシミュレーションテスト実行"
	@echo "  make test-<対象>   - フォルダ単位のテスト"
	@echo "                       対象: blink / pwm / button / uart / cpu / gpu /"
	@echo "                             hdmi-colorbar / hdmi-text / modules"
	@echo ""
	@echo "ビルド (Cm → SV 変換 + Verilatorリント):"
	@echo "  make build-<対象>  - blink / pwm / button / uart-hello / uart-button /"
	@echo "                       hdmi-colorbar / hdmi-text / cpu / gpu"
	@echo ""
	@echo "合成・書き込み (Gowin EDA。対象: blink / uart-hello / uart-button / hdmi-colorbar / hdmi-text):"
	@echo "  make gowin-<対象>  - 合成〜ビットストリーム生成 (SV → FS)"
	@echo "  make flash-<対象>  - FPGAに書き込み (.fs)"
	@echo "  make apply-<対象>  - build + gowin + flash 一括実行"
	@echo ""
	@echo "OSSフロー (blinkのみ・実験的):"
	@echo "  make synth / pnr / bitstream / apply-oss / flash-sram"
	@echo ""
	@echo "共通:"
	@echo "  make build-cm      - Cmコンパイラ自体をビルド"
	@echo "  make clean         - ビルド出力をクリーン"
	@echo "  make setup         - 開発環境セットアップ (macOS)"

# ============================================================
# Cm ビルド: Cm → SV 変換 + リントチェック
# ============================================================
.PHONY: build-blink
build-blink: $(BLINK_SV)
	@echo "Verilator リントチェック中..."
	$(VERILATOR_LINT) $(BLINK_SV) $(LINT_STUBS)
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
.PHONY: gowin-blink
gowin-blink: $(BLINK_SV)
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
.PHONY: apply-oss
apply-oss: synth pnr bitstream
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
.PHONY: flash-blink
flash-blink:
	@echo "FPGAに書き込み中 (Flash)..."
	openFPGALoader -b $(BOARD) $(BLINK_FS)
	@echo "✅ 書き込み完了!"

# Cm → SV → FS → FPGA 一括実行
.PHONY: apply-blink
apply-blink: build-blink gowin-blink flash-blink

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
# 全回路のシミュレーションテスト（cm test + #[test]）
test:
	@./scripts/test_circuits.sh

# フォルダ単位のテスト（例: make test-cpu → src/cpu 配下を実行）
# ターゲット名のハイフンはフォルダ名のアンダースコアに対応する（test-hdmi-colorbar → src/hdmi_colorbar）
test-%:
	@./scripts/test_circuits.sh "src/$(subst -,_,$*)"

clean:
	@echo "ビルド出力をクリーン中..."
	@rm -rf $(BUILD_DIR)
	@echo "✅ クリーン完了!"

# ============================================================
# UART Hello: Cm → SV + リントチェック
# ============================================================
.PHONY: build-uart-hello
build-uart-hello: $(UART_SV)
	@echo "Verilator リントチェック中..."
	$(VERILATOR_LINT) $(UART_SV) $(LINT_STUBS)
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
.PHONY: gowin-uart-hello
gowin-uart-hello: $(UART_SV)
	@echo "Gowin EDA で合成・配置配線・ビットストリーム生成中 (UART)..."
	DYLD_LIBRARY_PATH=$(GW_LIB) DYLD_FRAMEWORK_PATH=$(GW_LIB) $(GW_SH) $(UART_TCL)
	@echo ""
	@echo "=========================================="
	@echo "✅ Gowin EDA UART ビルド完了! $(UART_FS)"
	@echo "=========================================="

# ============================================================
# UART Hello: FPGA書き込み
# ============================================================
.PHONY: flash-uart-hello
flash-uart-hello:
	@echo "FPGAに書き込み中 (UART)..."
	openFPGALoader -b $(BOARD) $(UART_FS)
	@echo "✅ UART 書き込み完了!"

# UART: Cm → SV → FS → FPGA 一括実行
.PHONY: apply-uart-hello
apply-uart-hello: build-uart-hello gowin-uart-hello flash-uart-hello

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
.PHONY: build-uart-button
build-uart-button: $(BTN_SV)
	@echo "Verilator リントチェック中..."
	$(VERILATOR_LINT) $(BTN_SV) $(LINT_STUBS)
	@echo ""
	@echo "=========================================="
	@echo "✅ Button UART ビルド完了! $(BTN_SV)"
	@echo "=========================================="

$(BTN_SV): $(BTN_SRC)
	@echo "Cm → SystemVerilog 変換中 (Button)..."
	@mkdir -p $(BUILD_DIR)
	$(CM) compile --target=sv $(BTN_SRC) -o $(BTN_SV)
	@echo "✅ SV生成完了: $(BTN_SV)"

.PHONY: gowin-uart-button
gowin-uart-button: $(BTN_SV)
	@echo "Gowin EDA で合成中 (Button)..."
	DYLD_LIBRARY_PATH=$(GW_LIB) DYLD_FRAMEWORK_PATH=$(GW_LIB) $(GW_SH) $(BTN_TCL)
	@echo "✅ Gowin EDA Button ビルド完了!"

.PHONY: flash-uart-button
flash-uart-button:
	@echo "FPGAに書き込み中 (Button)..."
	openFPGALoader -b $(BOARD) $(BTN_FS)
	@echo "✅ Button 書き込み完了!"

.PHONY: apply-uart-button
apply-uart-button: build-uart-button gowin-uart-button flash-uart-button

# ============================================================
# HDMI カラーバー: 変数定義
# ============================================================
HDMI_SRC := $(SRC_DIR)/hdmi_colorbar/main.cm
HDMI_SV := $(BUILD_DIR)/hdmi/hdmi_colorbar.sv
HDMI_TCL := $(SRC_DIR)/hdmi_colorbar/synth/gowin_hdmi.tcl
HDMI_FS := $(BUILD_DIR)/hdmi/hdmi_colorbar/impl/pnr/hdmi_colorbar.fs

# ============================================================
# HDMI カラーバー: Cm → SV
# ============================================================
.PHONY: build-hdmi-colorbar
build-hdmi-colorbar: $(HDMI_SV)
	@echo "Verilator リントチェック中..."
	$(VERILATOR_LINT) $(HDMI_SV) $(LINT_STUBS)
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
.PHONY: gowin-hdmi-colorbar
gowin-hdmi-colorbar: $(HDMI_SV)
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
.PHONY: flash-hdmi-colorbar
flash-hdmi-colorbar:
	@echo "FPGAに書き込み中 (HDMI)..."
	eval "$$(/opt/homebrew/bin/brew shellenv)" && openFPGALoader --cable ft2232 -b $(BOARD) $(HDMI_FS)
	@echo "✅ HDMI 書き込み完了!"

# HDMI: Cm → SV → FS → FPGA 一括実行
.PHONY: apply-hdmi-colorbar
apply-hdmi-colorbar: build-hdmi-colorbar gowin-hdmi-colorbar flash-hdmi-colorbar

# ============================================================
# HDMI テキスト/アニメーション: 変数定義
# ============================================================
TEXT_SRC := $(SRC_DIR)/hdmi_text/main.cm
TEXT_SV := $(BUILD_DIR)/hdmi/hdmi_text.sv
TEXT_TCL := $(SRC_DIR)/hdmi_text/synth/gowin_hdmi_text.tcl
TEXT_FS := $(BUILD_DIR)/hdmi/hdmi_text/impl/pnr/hdmi_text.fs

# ============================================================
# HDMI テキスト/アニメーション: Cm → SV
# ============================================================
.PHONY: build-hdmi-text
build-hdmi-text: $(TEXT_SV)
	@echo "Verilator リントチェック中..."
	$(VERILATOR_LINT) $(TEXT_SV) $(LINT_STUBS)
	@echo ""
	@echo "=========================================="
	@echo "✅ HDMI テキストビルド完了! $(TEXT_SV)"
	@echo "=========================================="

$(SRC_DIR)/hdmi_text/font/font_rom.cm: $(SRC_DIR)/hdmi_text/font/font_rom.txt $(SRC_DIR)/hdmi_text/font/generate_font.py
	python3 $(SRC_DIR)/hdmi_text/font/generate_font.py

$(TEXT_SV): $(TEXT_SRC) $(SRC_DIR)/hdmi_text/font/font_rom.cm
	@echo "Cm → SystemVerilog 変換中 (HDMI Text)..."
	@mkdir -p $(BUILD_DIR)/hdmi
	$(CM) compile --target=sv $(TEXT_SRC) -o $(TEXT_SV)
	@echo "✅ SV生成完了: $(TEXT_SV)"
	cp $(SRC_DIR)/hdmi_text/font/font_rom.hex $(BUILD_DIR)/hdmi/

# ============================================================
# HDMI テキスト/アニメーション: Gowin EDA フルフロー
# ============================================================
.PHONY: gowin-hdmi-text
gowin-hdmi-text: $(TEXT_SV)
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
.PHONY: flash-hdmi-text
flash-hdmi-text:
	@echo "FPGAに書き込み中 (HDMI Text)..."
	eval "$$(/opt/homebrew/bin/brew shellenv)" && openFPGALoader --cable ft2232 -b $(BOARD) $(TEXT_FS)
	@echo "✅ HDMI テキスト書き込み完了!"

# HDMI テキスト: Cm → SV → FS → FPGA 一括実行
.PHONY: apply-hdmi-text
apply-hdmi-text: build-hdmi-text gowin-hdmi-text flash-hdmi-text

# ============================================================
# v0.16.0サンプル: PWM呼吸LED / ボタンカウンタ
# 制約ファイル(.cst/.tcl)は #[sv::pin] + --emit-constraints で自動生成
# ============================================================
.PHONY: build-pwm
build-pwm:
	@echo "Cm → SystemVerilog 変換中 (PWM呼吸LED)..."
	@mkdir -p $(BUILD_DIR)/pwm
	$(CM) compile --target=sv $(SRC_DIR)/pwm/pwm_breath.cm -o $(BUILD_DIR)/pwm/pwm_breath.sv --emit-constraints
	@echo "Verilator リントチェック中..."
	$(VERILATOR_LINT) $(BUILD_DIR)/pwm/pwm_breath.sv $(LINT_STUBS)
	@echo "✅ PWMビルド完了! $(BUILD_DIR)/pwm/pwm_breath.sv (+ .cst / _build.tcl)"

.PHONY: build-button
build-button:
	@echo "Cm → SystemVerilog 変換中 (ボタンカウンタ)..."
	@mkdir -p $(BUILD_DIR)/button
	$(CM) compile --target=sv $(SRC_DIR)/button/button_counter.cm -o $(BUILD_DIR)/button/button_counter.sv --emit-constraints
	@echo "Verilator リントチェック中..."
	$(VERILATOR_LINT) $(BUILD_DIR)/button/button_counter.sv $(LINT_STUBS)
	@echo "✅ ボタンカウンタビルド完了! $(BUILD_DIR)/button/button_counter.sv (+ .cst / _build.tcl)"

# ============================================================
# CPU/GPUサンプル: SimpleCPU（16bit命令アキュムレータ型）
#                  SimpleGPU（矩形フィルラスタライザ）
# ============================================================
.PHONY: build-cpu
build-cpu:
	@echo "Cm → SystemVerilog 変換中 (SimpleCPU)..."
	@mkdir -p $(BUILD_DIR)/cpu
	$(CM) compile --target=sv $(SRC_DIR)/cpu/simple_cpu.cm -o $(BUILD_DIR)/cpu/simple_cpu.sv
	@echo "Verilator リントチェック中..."
	$(VERILATOR_LINT) $(BUILD_DIR)/cpu/simple_cpu.sv $(LINT_STUBS)
	@echo "✅ SimpleCPUビルド完了! $(BUILD_DIR)/cpu/simple_cpu.sv"

.PHONY: build-gpu
build-gpu:
	@echo "Cm → SystemVerilog 変換中 (SimpleGPU)..."
	@mkdir -p $(BUILD_DIR)/gpu
	$(CM) compile --target=sv $(SRC_DIR)/gpu/simple_gpu.cm -o $(BUILD_DIR)/gpu/simple_gpu.sv
	@echo "Verilator リントチェック中..."
	$(VERILATOR_LINT) $(BUILD_DIR)/gpu/simple_gpu.sv $(LINT_STUBS)
	@echo "✅ SimpleGPUビルド完了! $(BUILD_DIR)/gpu/simple_gpu.sv"



