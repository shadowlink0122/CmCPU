# ============================================================
# Gowin EDA Tcl: UART Button SV → FS
# ============================================================
# 使い方: CmCPU ルートで実行: gw_sh src/uart/gowin_button.tcl
# ============================================================

set project_root [pwd]
set device_pn "GW5AST-LV138PG484AC1/I0"
set device_version "C"

set sv_file "${project_root}/build/uart/uart_button.sv"
set cst_file "${project_root}/src/uart/tang_console_138k_button.cst"
set output_dir "${project_root}/build/uart"
set project_name "uart_button"

create_project -name $project_name -dir $output_dir -pn $device_pn -device_version $device_version -force
add_file $sv_file
add_file $cst_file

set_option -verilog_std sysv2017
set_option -top_module uart_button
set_option -output_base_name uart_button

set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1

run all

puts "✅ ビルド完了! ${output_dir}/${project_name}/impl/pnr/${project_name}.fs"
