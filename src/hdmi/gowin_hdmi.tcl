# ============================================================
# Gowin EDA Tcl スクリプト: HDMI カラーバー SV → FS 変換
# ============================================================
# 使い方: CmCPU ルートで実行: gw_sh src/hdmi/gowin_hdmi.tcl
# ============================================================

# プロジェクトルート（gw_sh 実行時のカレントディレクトリ）
set project_root [pwd]

# デバイス設定
set device_pn "GW5AST-LV138FPG676AC2/I1"
set device_version "C"

# ファイルパス（絶対パスで指定）
set sv_file "${project_root}/build/hdmi/hdmi_colorbar.sv"
set cst_file "${project_root}/src/hdmi/tang_console_138k_hdmi.cst"
set output_dir "${project_root}/build/hdmi"
set project_name "hdmi_colorbar"

# 一時プロジェクトを作成してデバイスのサポート状況をチェック
set check_dir "${project_root}/.tmp/device_check"
file mkdir $check_dir

if { [catch {create_project -name check_dev -dir $check_dir -pn $device_pn -device_version $device_version -force} msg] } {
    puts "⚠️  GW5AST-LV138FPG676AC2/I1 が見つからないため、GW5AST-LV138PG484AC1/I0 にフォールバックします（PG484用ダミーピンマップでフルビルド）。"
    set device_pn "GW5AST-LV138PG484AC1/I0"
    set cst_file "${project_root}/src/hdmi/tang_console_138k_hdmi_pg484.cst"
    set run_synthesis_only 0
} else {
    set run_synthesis_only 0
}

# 本番のプロジェクト作成
create_project -name $project_name -dir $output_dir -pn $device_pn -device_version $device_version -force

# ソースファイルの追加
add_file $sv_file

# ピン制約ファイルの追加（フルビルド時のみ）
if { !$run_synthesis_only } {
    add_file $cst_file
}

# 合成設定
set_option -verilog_std sysv2017
set_option -top_module hdmi_colorbar
set_option -output_base_name hdmi_colorbar

# デュアルパーパスピンをGPIOとして使用
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1

if { $run_synthesis_only } {
    puts "Gowin Synthesis 開始..."
    run syn
    puts "✅ Gowin Synthesis 完了! (PG484フォールバックのためP&Rはスキップしました)"
} else {
    puts "Gowin Synthesis + P&R + Bitstream 開始..."
    run all
    puts "✅ HDMI ビルド完了! ${output_dir}/${project_name}/impl/pnr/${project_name}.fs"
}
