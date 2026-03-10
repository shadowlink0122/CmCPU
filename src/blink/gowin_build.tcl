# ============================================================
# Gowin EDA Tcl スクリプト: SV → FS 変換
# ============================================================
# 使い方: CmCPU ルートで実行: gw_sh src/blink/gowin_build.tcl
# ============================================================

# プロジェクトルート（gw_sh 実行時のカレントディレクトリ）
set project_root [pwd]

# デバイス設定
# Tang Console 138K: GW5AST-LV138PG484A (Arora V, PBGA484 パッケージ)
set device_pn "GW5AST-LV138PG484AC1/I0"
set device_version "C"

# ファイルパス（絶対パスで指定）
set sv_file "${project_root}/build/blink.sv"
set cst_file "${project_root}/src/blink/tang_console_138k.cst"
set output_dir "${project_root}/build"
set project_name "blink"

# プロジェクト作成
create_project -name $project_name -dir $output_dir -pn $device_pn -device_version $device_version -force

# ソースファイルの追加
add_file $sv_file

# ピン制約ファイルの追加
add_file $cst_file

# 合成設定
set_option -verilog_std sysv2017
set_option -top_module blink
set_option -output_base_name blink

# デュアルパーパスピンをGPIOとして使用
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1

# 合成 + 配置配線 + ビットストリーム生成を一括実行
run all

puts "✅ ビルド完了! ${output_dir}/${project_name}.fs"
