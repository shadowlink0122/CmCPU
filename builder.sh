#!/bin/bash
# ============================================================
# builder.sh — Cm → SV → Gowin EDA → FPGA ビルド&デプロイ
# ============================================================
# 使い方:
#   ./builder.sh hdmi              # src/hdmi/ をビルド (Cm→SV + リント)
#   ./builder.sh uart hello        # src/uart/uart_hello.cm を指定
#   ./builder.sh hdmi --apply      # ビルド + Gowin合成 + FPGA書き込み
#   ./builder.sh blink --apply     # blink を一括デプロイ
#   ./builder.sh hdmi --apply --sram  # SRAM 書き込みモード
# ============================================================

set -euo pipefail

# ============================================================
# 設定
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CM="${SCRIPT_DIR}/Cm/cm"
SRC_DIR="${SCRIPT_DIR}/src"
BUILD_DIR="${SCRIPT_DIR}/build"

# Gowin EDA パス
GW_HOME="/Applications/GowinIDE.app/Contents/Resources/Gowin_EDA"
GW_SH="${GW_HOME}/IDE/bin/gw_sh"
GW_LIB="${GW_HOME}/IDE/lib"

# FPGA ボード設定
BOARD="tangmega138k"

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# ヘルパー関数
# ============================================================
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    echo "使い方: ./builder.sh <ディレクトリ> [プロジェクト名] [オプション]"
    echo ""
    echo "引数:"
    echo "  <ディレクトリ>     src/ 以下のディレクトリ名 (blink, uart, hdmi)"
    echo "  [プロジェクト名]   ディレクトリ内に複数 .cm がある場合に指定"
    echo ""
    echo "オプション:"
    echo "  --apply            Gowin EDA 合成 + FPGA 書き込みまで実行"
    echo "  --skip-lint        Verilator リントをスキップ"
    echo "  --sram             Flash の代わりに SRAM 書き込み (--apply と併用)"
    echo ""
    echo "利用可能なプロジェクト:"
    for dir in "${SRC_DIR}"/*/; do
        local name
        name=$(basename "$dir")
        local cm_files
        cm_files=$(find "$dir" -maxdepth 1 -name "*.cm" | sort)
        if [ -n "$cm_files" ]; then
            echo -e "  ${GREEN}${name}${NC}"
            while IFS= read -r f; do
                echo "    - $(basename "$f" .cm)"
            done <<< "$cm_files"
        fi
    done
    exit 1
}

# ============================================================
# .cm / .tcl / .fs パスの自動検出
# ============================================================
detect_project() {
    local dir="$1"
    local project_hint="${2:-}"
    local src_path="${SRC_DIR}/${dir}"

    if [ ! -d "$src_path" ]; then
        error "ディレクトリが見つかりません: ${src_path}"
        echo ""
        usage
    fi

    # .cm ファイル一覧
    local cm_files
    cm_files=($(find "$src_path" -maxdepth 1 -name "*.cm" | sort))

    if [ ${#cm_files[@]} -eq 0 ]; then
        error "${src_path} に .cm ファイルがありません"
        exit 1
    fi

    # プロジェクト選択
    if [ ${#cm_files[@]} -eq 1 ]; then
        # 1ファイルのみ → 自動選択
        CM_SRC="${cm_files[0]}"
    elif [ -n "$project_hint" ]; then
        # ヒントで絞り込み
        local matched=""
        for f in "${cm_files[@]}"; do
            local base
            base=$(basename "$f" .cm)
            if [[ "$base" == *"$project_hint"* ]]; then
                matched="$f"
                break
            fi
        done
        if [ -z "$matched" ]; then
            error "プロジェクト '${project_hint}' が見つかりません"
            echo "利用可能:"
            for f in "${cm_files[@]}"; do
                echo "  - $(basename "$f" .cm)"
            done
            exit 1
        fi
        CM_SRC="$matched"
    else
        # 対話選択
        info "複数のプロジェクトが見つかりました:"
        local i=1
        for f in "${cm_files[@]}"; do
            echo "  ${i}) $(basename "$f" .cm)"
            i=$((i + 1))
        done
        echo -n "選択 [1-${#cm_files[@]} または プロジェクト名]: "
        read -r choice
        local chosen_file=""
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#cm_files[@]} ]; then
            chosen_file="${cm_files[$((choice - 1))]}"
        else
            for f in "${cm_files[@]}"; do
                local base
                base=$(basename "$f" .cm)
                if [ "$base" = "$choice" ]; then
                    chosen_file="$f"
                    break
                fi
            done
        fi

        if [ -n "$chosen_file" ]; then
            CM_SRC="$chosen_file"
        else
            error "無効な選択: ${choice}"
            exit 1
        fi
    fi

    # プロジェクト名 (拡張子なしのベース名)
    PROJECT_NAME=$(basename "$CM_SRC" .cm)
    if [ "$PROJECT_NAME" = "main" ]; then
        if [ "$dir" = "hdmi" ]; then
            PROJECT_NAME="hdmi_colorbar"
        else
            PROJECT_NAME="$dir"
        fi
    elif [ "$PROJECT_NAME" = "hdmi_text_top" ]; then
        PROJECT_NAME="hdmi_text"
    fi
    info "プロジェクト: ${PROJECT_NAME}"

    # ビルド出力ディレクトリ
    PROJECT_BUILD_DIR="${BUILD_DIR}/${dir}"
    SV_OUT="${PROJECT_BUILD_DIR}/${PROJECT_NAME}.sv"

    # Gowin TCL スクリプトの検出
    # 優先順位: gowin_{project_name}.tcl → gowin_build.tcl → *.tcl
    TCL_FILE=""
    if [ -f "${src_path}/gowin_${PROJECT_NAME}.tcl" ]; then
        TCL_FILE="${src_path}/gowin_${PROJECT_NAME}.tcl"
    elif [ -f "${src_path}/gowin_build.tcl" ]; then
        TCL_FILE="${src_path}/gowin_build.tcl"
    else
        # ディレクトリ名ベースで検索
        local tcl_match
        tcl_match=$(find "$src_path" -maxdepth 1 -name "gowin_*.tcl" | head -1)
        if [ -n "$tcl_match" ]; then
            TCL_FILE="$tcl_match"
        fi
    fi

    # .fs ファイルパスの推定 (Gowin EDA の出力パス規則)
    FS_FILE="${PROJECT_BUILD_DIR}/${PROJECT_NAME}/impl/pnr/${PROJECT_NAME}.fs"

    info "ソース:  ${CM_SRC}"
    info "SV出力:  ${SV_OUT}"
    [ -n "$TCL_FILE" ] && info "TCL:     ${TCL_FILE}"
    info "FS出力:  ${FS_FILE}"
}

# ============================================================
# ステップ 1: Cm → SV コンパイル
# ============================================================
step_build() {
    info "ステップ 1/4: Cm → SystemVerilog コンパイル"
    mkdir -p "$PROJECT_BUILD_DIR"

    if ! "$CM" compile --target=sv "$CM_SRC" -o "$SV_OUT"; then
        error "Cm コンパイル失敗: ${CM_SRC}"
        exit 1
    fi
    ok "SV 生成完了: ${SV_OUT}"
}

# ============================================================
# ステップ 2: Verilator リント
# ============================================================
step_lint() {
    if [ "$SKIP_LINT" = true ]; then
        warn "Verilator リントをスキップ"
        return
    fi

    info "ステップ 2/4: Verilator リントチェック"

    # リント実行: -Wno-MODMISSING は Gowin プリミティブ (OSER10, PLL 等) 用
    # -Wno-UNUSED/WIDTHTRUNC/WIDTHEXPAND/UNDRIVEN は Cm自動生成コード特有の警告を抑止
    local lint_output
    lint_output=$(verilator --lint-only --timing -Wno-MODMISSING -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNDRIVEN "$SV_OUT" 2>&1) || true

    # 警告・エラーのカウント
    local warn_count
    warn_count=$(echo "$lint_output" | grep -c "%Warning\|%Error" || true)

    if [ "$warn_count" -gt 0 ]; then
        echo "$lint_output"
        echo ""
        error "Verilator リント違反: ${warn_count} 件"
        error "リントをスキップするには --skip-lint を指定してください"
        exit 1
    fi
    ok "リントチェック完了 (警告 0 件)"
}

# ============================================================
# ステップ 3: Gowin EDA 合成 + 配置配線 + ビットストリーム生成
# ============================================================
step_gowin() {
    if [ -z "$TCL_FILE" ]; then
        error "Gowin TCL スクリプトが見つかりません"
        error "src/${TARGET_DIR}/ に gowin_*.tcl を配置してください"
        exit 1
    fi

    info "ステップ 3/4: Gowin EDA 合成 (${TCL_FILE})"

    if [ ! -f "$GW_SH" ]; then
        error "Gowin EDA が見つかりません: ${GW_SH}"
        error "GowinIDE をインストールしてください"
        exit 1
    fi

    # 古い P&R 出力を削除 (合成のみフォールバック時に誤書き込みを防止)
    if [ -f "$FS_FILE" ]; then
        warn "古いビットストリームを削除: ${FS_FILE}"
        rm -f "$FS_FILE"
    fi

    if ! DYLD_LIBRARY_PATH="$GW_LIB" DYLD_FRAMEWORK_PATH="$GW_LIB" "$GW_SH" "$TCL_FILE"; then
        error "Gowin EDA 合成失敗"
        exit 1
    fi
    ok "Gowin EDA ビルド完了"
}

# ============================================================
# ステップ 4: FPGA 書き込み
# ============================================================
step_flash() {
    if [ ! -f "$FS_FILE" ]; then
        if [ -f "${PROJECT_BUILD_DIR}/${PROJECT_NAME}/impl/gwsynthesis/${PROJECT_NAME}.vg" ]; then
            error "ビットストリームファイルが見つかりません (合成のみ実行されたため P&R 未完了)"
            error "FPG676 パッケージ対応環境で P&R を実行してください"
        else
            error "ビットストリームファイルが見つかりません: ${FS_FILE}"
            error "Gowin EDA の出力パスを確認してください"
        fi
        exit 1
    fi

    if [ "$SRAM_MODE" = true ]; then
        info "ステップ 4/4: FPGA SRAM 書き込み"
        if ! openFPGALoader -b "$BOARD" --sram "$FS_FILE"; then
            error "FPGA SRAM 書き込み失敗 (デバイスが接続されているか確認してください)"
            exit 1
        fi
    else
        info "ステップ 4/4: FPGA Flash 書き込み"
        if ! openFPGALoader -b "$BOARD" "$FS_FILE"; then
            error "FPGA Flash 書き込み失敗 (デバイスが接続されているか確認してください)"
            exit 1
        fi
    fi
    ok "FPGA 書き込み完了!"
}

# ============================================================
# メイン処理
# ============================================================

# オプション解析
APPLY_MODE=false
SKIP_LINT=false
SRAM_MODE=false
TARGET_DIR=""
PROJECT_HINT=""

for arg in "$@"; do
    case "$arg" in
        --apply)      APPLY_MODE=true ;;
        --skip-lint)  SKIP_LINT=true ;;
        --sram)       SRAM_MODE=true ;;
        --help|-h)    usage ;;
        -*)           error "不明なオプション: ${arg}"; usage ;;
        *)
            if [ -z "$TARGET_DIR" ]; then
                TARGET_DIR="$arg"
            elif [ -z "$PROJECT_HINT" ]; then
                PROJECT_HINT="$arg"
            else
                error "引数が多すぎます: ${arg}"
                usage
            fi
            ;;
    esac
done

if [ -z "$TARGET_DIR" ]; then
    error "ディレクトリを指定してください"
    echo ""
    usage
fi

echo ""
echo "=========================================="
echo " CmCPU ビルド: src/${TARGET_DIR}"
echo "=========================================="
echo ""

# プロジェクト検出
detect_project "$TARGET_DIR" "$PROJECT_HINT"
echo ""

# ビルド実行
step_build
echo ""
step_lint
echo ""

if [ "$APPLY_MODE" = false ]; then
    echo "=========================================="
    ok "ビルド完了! src/${TARGET_DIR}/${PROJECT_NAME}"
    echo "=========================================="
    echo ""
    info "FPGA にデプロイするには --apply を追加してください"
    exit 0
fi

# --apply: Gowin 合成 + FPGA 書き込み
step_gowin
echo ""
step_flash
echo ""

echo "=========================================="
ok "デプロイ完了! src/${TARGET_DIR}/${PROJECT_NAME}"
echo "=========================================="
