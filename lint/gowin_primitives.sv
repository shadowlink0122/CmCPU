// ============================================================
// Gowin FPGAプリミティブのVerilatorリント用ブラックボックス・スタブ
// ============================================================
// 実体はGowin EDA/デバイス側が提供するため、ここではポート定義のみを
// 宣言してリント時の未定義モジュールエラーを解消する。
// 合成(Gowin EDA)やシミュレーション(-D SIM)では使用しない。
// ============================================================
/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNDRIVEN */
/* verilator lint_off UNUSED */

// 内蔵オシレータ
module OSC #(
    parameter FREQ_DIV = 100
) (
    output logic OSCOUT
);
endmodule

// PLL (GW5A系)
module PLL #(
    parameter FCLKIN        = 50,
    parameter IDIV_SEL      = 0,
    parameter FBDIV_SEL     = 0,
    parameter MDIV_SEL      = 8,
    parameter MDIV_FRAC_SEL = 0,
    parameter ODIV0_SEL     = 8,
    parameter ODIV1_SEL     = 8,
    parameter CLKOUT0_EN    = "FALSE",
    parameter CLKOUT1_EN    = "FALSE",
    parameter CLKFB_SEL     = "INTERNAL"
) (
    input  logic CLKIN,
    input  logic CLKFB,
    input  logic RESET,
    input  logic PLLPWD,
    input  logic RESET_I,
    input  logic RESET_O,
    input  logic ENCLK0,
    input  logic ENCLK1,
    output logic CLKOUT0,
    output logic CLKOUT1,
    output logic LOCK
);
endmodule

// OSER10: 10:1 出力シリアライザ
module OSER10 #(
    parameter GSREN = "false",
    parameter LSREN = "true"
) (
    input  logic PCLK,
    input  logic FCLK,
    input  logic RESET,
    input  logic D0,
    input  logic D1,
    input  logic D2,
    input  logic D3,
    input  logic D4,
    input  logic D5,
    input  logic D6,
    input  logic D7,
    input  logic D8,
    input  logic D9,
    output logic Q
);
endmodule

// TLVDS_OBUF: LVDS差動出力バッファ
module TLVDS_OBUF (
    input  logic I,
    output logic O,
    output logic OB
);
endmodule
